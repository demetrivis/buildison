#requires -version 5
<#
buildison switch (Windows / PowerShell) — troca o modo de memória (local | vps) do projeto atual.

Atualiza .mcp.json (Claude Code), opencode.json (OpenCode) e o bloco Codex em
~/.codex/config.toml. NÃO toca em .claude/, AGENTS.md, CLAUDE.md, docs/agent/ nem skills.

Uso:
  .\switch.ps1                                              # interativo (no diretório atual)
  .\switch.ps1 -Memory local
  .\switch.ps1 -Memory vps -QdrantUrl https://qdrant.<dom>
  .\switch.ps1 -Dir C:\caminho\projeto -Memory vps -QdrantUrl https://qdrant.<dom>

  # Remoto (irm | iex) — passe -Memory/-QdrantUrl em modo -Yes pra não travar
  $env:BUILDISON_ARGS = '-Memory vps -QdrantUrl https://qdrant.<dom>'
  irm https://raw.githubusercontent.com/demetrivis/buildison/main/switch.ps1 | iex

Persiste a escolha em $HOME/.buildison/vps.env.
#>
[CmdletBinding()]
param(
  [string]$Dir = "",
  [ValidateSet('','local','vps')] [string]$Memory = "",
  [string]$QdrantUrl = "",
  [switch]$Yes,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$Embed = 'sentence-transformers/all-MiniLM-L6-v2'

function Info($m){ Write-Host "> $m"  -ForegroundColor Cyan }
function Ok($m)  { Write-Host "OK $m" -ForegroundColor Green }
function Warn($m){ Write-Host "! $m"  -ForegroundColor Yellow }
function Die($m) { Write-Host "x $m"  -ForegroundColor Red; exit 1 }

if ($Help) { Get-Help $PSCommandPath -Detailed; exit 0 }

# permite passar args via env BUILDISON_ARGS quando invocado por irm|iex
if ($env:BUILDISON_ARGS) {
  $extra = [System.Management.Automation.PSParser]::Tokenize($env:BUILDISON_ARGS, [ref]$null) |
           ForEach-Object { $_.Content }
  for ($i = 0; $i -lt $extra.Count; $i++) {
    switch -Regex ($extra[$i]) {
      '^-Dir$'        { $Dir       = $extra[++$i] }
      '^-Memory$'     { $Memory    = $extra[++$i] }
      '^-QdrantUrl$'  { $QdrantUrl = $extra[++$i] }
      '^-Yes$'        { $Yes       = $true }
    }
  }
}

# ----- destino -----
$target = if ($Dir) { (Resolve-Path $Dir).Path } else { (Get-Location).Path }
if (-not (Test-Path $target)) { Die "Diretório inválido: $target" }
Ok "Projeto: $target"

# ----- carrega config per-máquina -----
$bldCfgDir = Join-Path $env:USERPROFILE '.buildison'
$bldCfg    = Join-Path $bldCfgDir 'vps.env'
if (-not $Memory -or (-not $QdrantUrl -and $Memory -eq 'vps')) {
  if (Test-Path $bldCfg) {
    Get-Content $bldCfg | ForEach-Object {
      if ($_ -match '^\s*BUILDISON_MEMORY_MODE=(.+)$' -and -not $Memory)   { $Memory = $Matches[1].Trim() }
      if ($_ -match '^\s*BUILDISON_QDRANT_URL=(.+)$'  -and -not $QdrantUrl) { $QdrantUrl = $Matches[1].Trim() }
    }
  }
}

# ----- prompts -----
if (-not $Memory) {
  if ($Yes) { Die '-Memory é obrigatório em -Yes (local|vps).' }
  Write-Host "`nTrocar para qual modo?" -ForegroundColor White
  Write-Host "  1) local - http://localhost:6333"
  Write-Host "  2) vps   - HTTPS com api-key"
  $mm = Read-Host "Escolha [1]"
  $Memory = if ($mm -eq '2') { 'vps' } else { 'local' }
}
if ($Memory -eq 'vps' -and -not $QdrantUrl) {
  if ($Yes) { Die '-Memory vps requer -QdrantUrl em -Yes.' }
  $QdrantUrl = Read-Host "URL do Qdrant na VPS (ex: https://qdrant.seu-dominio.com)"
  if (-not $QdrantUrl) { Die 'URL vazia.' }
}

# ----- valores derivados -----
$projName = (Split-Path $target -Leaf).ToLower() -replace '[^a-z0-9_]','_'
if (-not $projName) { $projName = 'project_main' }
$collection = "agent_$projName"
$qUrl = if ($Memory -eq 'vps') { $QdrantUrl } else { 'http://localhost:6333' }
Info "Modo: $Memory | URL: $qUrl | collection: $collection"

# ----- persiste a escolha per-máquina -----
New-Item -ItemType Directory -Force -Path $bldCfgDir | Out-Null
@"
BUILDISON_MEMORY_MODE=$Memory
BUILDISON_QDRANT_URL=$QdrantUrl
"@ | Set-Content -Path $bldCfg -Encoding UTF8

# ----- helpers -----
function Backup($path) {
  if (Test-Path $path) {
    $ts = [int][double]::Parse((Get-Date -UFormat %s))
    Copy-Item $path "$path.bak.$ts" -Force
  }
}
function Build-QdrantEnv {
  if ($Memory -eq 'vps') {
    [ordered]@{
      QDRANT_URL      = $qUrl
      QDRANT_API_KEY  = '${QDRANT_API_KEY}'   # literal — expandido pelo agente do ambiente do shell
      COLLECTION_NAME = $collection
      EMBEDDING_MODEL = $Embed
    }
  } else {
    [ordered]@{
      QDRANT_URL      = $qUrl
      COLLECTION_NAME = $collection
      EMBEDDING_MODEL = $Embed
    }
  }
}

# ----- Claude Code (.mcp.json) -----
$mcp = Join-Path $target '.mcp.json'
if (Test-Path $mcp) {
  Backup $mcp
  $obj = Get-Content $mcp -Raw | ConvertFrom-Json
  if (-not $obj.mcpServers)               { $obj | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) }
  if (-not $obj.mcpServers.'qdrant-memory') {
    $obj.mcpServers | Add-Member -NotePropertyName 'qdrant-memory' -NotePropertyValue ([pscustomobject]@{
      command='uvx'; args=@('mcp-server-qdrant')
    })
  }
  $obj.mcpServers.'qdrant-memory' | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject](Build-QdrantEnv)) -Force
  $obj | ConvertTo-Json -Depth 16 | Set-Content -Path $mcp -Encoding UTF8
  Ok ".mcp.json atualizado (backup *.bak.*)"
} else {
  Warn ".mcp.json não existe — rode .\install.ps1 primeiro."
}

# ----- OpenCode (opencode.json) -----
$oc = Join-Path $target 'opencode.json'
if (Test-Path $oc) {
  Backup $oc
  $obj = Get-Content $oc -Raw | ConvertFrom-Json
  if (-not $obj.mcp)               { $obj | Add-Member -NotePropertyName mcp -NotePropertyValue ([pscustomobject]@{}) }
  if (-not $obj.mcp.'qdrant-memory') {
    $obj.mcp | Add-Member -NotePropertyName 'qdrant-memory' -NotePropertyValue ([pscustomobject]@{
      type='local'; command=@('uvx','mcp-server-qdrant'); enabled=$true
    })
  }
  $obj.mcp.'qdrant-memory' | Add-Member -NotePropertyName environment -NotePropertyValue ([pscustomobject](Build-QdrantEnv)) -Force
  $obj | ConvertTo-Json -Depth 16 | Set-Content -Path $oc -Encoding UTF8
  Ok "opencode.json atualizado"
}

# ----- Codex (~/.codex/config.toml) -----
$codex = Join-Path $env:USERPROFILE '.codex\config.toml'
$markBegin = "# >>> buildison ($projName) >>>"
$markEnd   = "# <<< buildison ($projName) <<<"
if ((Test-Path $codex) -and (Select-String -SimpleMatch -Quiet -Path $codex -Pattern $markBegin)) {
  Backup $codex
  $txt = Get-Content $codex -Raw
  $pattern = [regex]::Escape($markBegin) + "(.*?)" + [regex]::Escape($markEnd)
  $envLine = if ($Memory -eq 'vps') {
    'env = { QDRANT_URL = "' + $qUrl + '", QDRANT_API_KEY = "${QDRANT_API_KEY}", COLLECTION_NAME = "' + $collection + '", EMBEDDING_MODEL = "' + $Embed + '" }'
  } else {
    'env = { QDRANT_URL = "' + $qUrl + '", COLLECTION_NAME = "' + $collection + '", EMBEDDING_MODEL = "' + $Embed + '" }'
  }
  $new = [regex]::Replace($txt, $pattern, {
    param($m)
    $block = $m.Groups[0].Value
    $lines = $block -split "`r?`n"
    $inQ = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $line = $lines[$i].Trim()
      if ($line -eq '[mcp_servers.qdrant-memory]') { $inQ = $true; continue }
      if ($inQ -and $line.StartsWith('[') -and ($line -notmatch 'qdrant-memory')) { $inQ = $false }
      if ($inQ -and $lines[$i] -match '^\s*env\s*=') { $lines[$i] = $envLine }
    }
    ($lines -join "`n")
  }, [Text.RegularExpressions.RegexOptions]::Singleline)
  Set-Content -Path $codex -Value $new -Encoding UTF8
  Ok "Codex (bloco $projName) atualizado"
}

# ----- resumo -----
Write-Host ""
Ok "Switch concluído: modo $Memory"
if ($Memory -eq 'vps') {
  Write-Host ""
  Write-Host "Importante: o .mcp.json usa `${QDRANT_API_KEY} (lido do AMBIENTE do shell que abre o claude)." -ForegroundColor White
  Write-Host "  Exporte UMA vez antes:"
  Write-Host "    `$env:QDRANT_API_KEY = '<sua-key>'                                                # por sessão"
  Write-Host "    [Environment]::SetEnvironmentVariable('QDRANT_API_KEY','<sua-key>','User')        # persistente"
}
Write-Host ""
Write-Host "Reinicie o Claude Code (e Codex/OpenCode se usar) pra reler os configs."
