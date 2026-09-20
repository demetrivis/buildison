#requires -version 5
<#
.SYNOPSIS
buildison installer (Windows / PowerShell) - instala a toolbox de agentes (single source -> glue por agente)

.DESCRIPTION
Uso:
  irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1 | iex      # interativo
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Preset files
  .\install.ps1 -Dir . -Agents claude,codex -Preset lite
  .\install.ps1 -Mcp spec-workflow,serena -Skills golang,nestjs -Commands commit,pr
  .\install.ps1 -List
  .\install.ps1 -Update

Presets (-Preset):
  files   so arquivos: AGENTS.md, docs\agent, agents, commands, skills. Sem MCP, sem infra, sem Qdrant.
  lite    files + MCP spec-workflow
  full    lite + serena + memoria Qdrant + .claude\settings.json (default)
  custom  pergunta MCPs, partes e itens

Sob medida (partem do preset e sobrescrevem so o que for passado):
  -Mcp spec-workflow,serena,memory | none
  -Parts agents,commands,skills,settings
  -Skills / -Subagents / -Commands <nomes>   (default: todos, menos os que dependem de peca nao instalada)
A escolha fica em .buildison na raiz do projeto e e reaproveitada nas proximas execucoes.

-Update atualiza so o boilerplate (AGENTS.md, .claude\, .agents\, .spec-workflow\templates\, .mcp.json)
e preserva CLAUDE.md, docs\agent\context.md e docs\agent\decisions.md. Nao use -Force pra atualizar.

Agentes: claude, codex, opencode, antigravity
Flags: -Dir -Agents -Preset -Mcp -Parts -Skills -Subagents -Commands -List -Infra/-NoInfra
       -Serena/-NoSerena -Memory local|vps -QdrantUrl -Yes -Force -Update
#>
[CmdletBinding()]
param(
  [string]$Dir = "",
  [string[]]$Agents = @(),
  [ValidateSet('','files','lite','full','custom')] [string]$Preset = "",
  [string[]]$Mcp = @(),
  [string[]]$Parts = @(),
  [string[]]$Skills = @(),
  [string[]]$Subagents = @(),
  [string[]]$Commands = @(),
  [switch]$List,
  [switch]$Infra,
  [switch]$NoInfra,
  [switch]$Serena,
  [switch]$NoSerena,
  [ValidateSet('','local','vps')] [string]$Memory = "",
  [string]$QdrantUrl = "",
  [switch]$Yes,
  [switch]$Force,
  [switch]$Update,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$RepoUrl = 'https://github.com/demetrivis/buildison.git'
$Embed   = 'sentence-transformers/all-MiniLM-L6-v2'

function Info($m){ Write-Host "> $m"  -ForegroundColor Cyan }
function Ok($m)  { Write-Host "OK $m" -ForegroundColor Green }
function Warn($m){ Write-Host "! $m"  -ForegroundColor Yellow }
function Fail($m){ Write-Host "x $m"  -ForegroundColor Red }
function Die($m) { Fail $m; exit 1 }

if ($Help) { Get-Help $PSCommandPath -Detailed; return }

function New-RandomPassword {
  $bytes = New-Object 'System.Byte[]' 24
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

function New-Dir($p) { if ($p -and -not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }

# UTF-8 sem BOM e LF - BOM quebra parser de TOML/JSON de alguns agentes
function Write-Utf8([string]$path, [string]$text) {
  New-Dir (Split-Path $path -Parent)
  [IO.File]::WriteAllText($path, ($text -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding $false))
}

# listas: aceita "a,b", @('a','b') e "a b"
function Split-List($v) { @((@($v) -join ',') -split '[,\s]+' | Where-Object { $_ }) }
function Test-Csv([string]$csv, [string]$item) { (",$csv,").Contains(",$item,") }

function ConvertTo-McpCsv($v) {
  $out = @()
  foreach ($x in (Split-List $v)) {
    $n = switch -Regex ($x.ToLower()) {
      '^(1|spec|spec-workflow|specworkflow)$'             { 'spec-workflow'; break }
      '^(2|serena)$'                                      { 'serena'; break }
      '^(3|memory|memoria|memoria|qdrant|qdrant-memory)$' { 'memory'; break }
      '^(none|nenhum)$'                                   { ''; break }
      default { Die "-Mcp: '$x' desconhecido (use spec-workflow, serena, memory ou none)" }
    }
    if ($n -and ($out -notcontains $n)) { $out += $n }
  }
  $out -join ','
}
function ConvertTo-PartsCsv($v) {
  $out = @()
  foreach ($x in (Split-List $v)) {
    $n = switch -Regex ($x.ToLower()) {
      '^(agents|subagents)$'         { 'agents'; break }
      '^(commands|skills|settings)$' { $x.ToLower(); break }
      '^(all|tudo)$'                 { 'ALL'; break }
      default { Die "-Parts: '$x' desconhecido (use agents, commands, skills, settings)" }
    }
    if ($n -eq 'ALL') { $out = @('agents', 'commands', 'skills', 'settings') }
    elseif ($out -notcontains $n) { $out += $n }
  }
  $out -join ','
}
function ConvertTo-ItemsCsv($v) {
  (Split-List $v | ForEach-Object { ($_ -replace '\.md$', '') -replace '[\\/]', '' } | Where-Object { $_ }) -join ','
}

# ---------- catalogo (agents / skills / commands da fonte) ----------
function Get-ItemNames([string]$part) {
  $p = Join-Path $src ".claude\$part"
  if (-not (Test-Path $p)) { return @() }
  @(Get-ChildItem -LiteralPath $p | ForEach-Object { $_.Name -replace '\.md$', '' })
}
# Itens que so fazem sentido com uma peca instalada. Saem sozinhos quando ela falta -
# a menos que voce peca o item pelo nome (-Skills agent-memory forca).
function Get-ItemDep([string]$part, [string]$name) {
  switch ("$part/$name") {
    'skills/agent-memory'  { return 'memory' }
    'skills/spec-workflow' { return 'spec' }
    'skills/local-infra'   { return 'infra' }
    'agents/suporte'       { return 'mcp' }
  }
  return ''
}
function Test-ItemSelected([string]$part, [string]$name) {
  if (-not (Test-Csv $PartsCsv $part)) { return $false }
  $list = switch ($part) { 'skills' { $SkillsCsv } 'agents' { $SubagentsCsv } 'commands' { $CommandsCsv } }
  if ($list) { return (Test-Csv $list $name) }
  $dep = Get-ItemDep $part $name
  return ((-not $dep) -or ($Tags -contains $dep))
}

# Copia um arquivo com blocos <!-- bld:if TAG --> ... <!-- bld:end --> resolvidos pelas $Tags
# (aceita !TAG e aninhamento). Os marcadores somem; linhas em branco repetidas viram uma.
function Render-Tagged([string]$from, [string]$to) {
  $out = New-Object System.Collections.Generic.List[string]
  $stack = New-Object System.Collections.Generic.List[int]
  $off = 0; $nb = $false; $printed = $false
  foreach ($line in [IO.File]::ReadAllLines($from)) {
    if ($line -match '^\s*<!--\s*bld:if\s+(!?)([a-z0-9-]+)\s*-->\s*$') {
      $on = $Tags -contains $Matches[2]
      if ($Matches[1]) { $on = -not $on }
      $v = if ($on) { 0 } else { 1 }
      $stack.Add($v); $off += $v; continue
    }
    if ($line -match '^\s*<!--\s*bld:end\s*-->\s*$') {
      if ($stack.Count) { $off -= $stack[$stack.Count - 1]; $stack.RemoveAt($stack.Count - 1) }
      continue
    }
    if ($off -gt 0) { continue }
    if ($line -match '^\s*$') { if (-not $nb) { $nb = $true; if ($printed) { $out.Add('') } }; continue }
    $nb = $false; $printed = $true; $out.Add($line)
  }
  Write-Utf8 $to (($out -join "`n") + "`n")
}

function Get-Rel([string]$p) { if ($p.StartsWith($Target)) { $p.Substring($Target.Length).TrimStart('\', '/') } else { $p } }

# Duas naturezas de arquivo, e elas se comportam DIFERENTE num update:
#   boilerplate (AGENTS.md, settings.json) - atualiza no -Update e no -Force (com .bak)
#   do projeto  (context.md, decisions.md) - NUNCA sobrescreve num -Update; so -Force
function Copy-Keep($s, $d) {
  if ((Test-Path $d) -and -not $Force) { Warn "mantido (ja existe): $(Get-Rel $d)"; return }
  New-Dir (Split-Path $d -Parent); Copy-Item -Force $s $d; Ok (Get-Rel $d)
}
function Copy-Boiler($s, $d) {
  if ((Test-Path $d) -and -not $Update -and -not $Force) { Warn "mantido (ja existe): $(Get-Rel $d)"; return }
  if ((Test-Path $d) -and ((Get-FileHash $s).Hash -ne (Get-FileHash $d).Hash)) { Copy-Item -Force $d "$d.bak" }
  New-Dir (Split-Path $d -Parent); Copy-Item -Force $s $d; Ok (Get-Rel $d)
}
# Destino = pasta PAI. Pasta que ja existe e MESCLADA - Copy-Item de pasta pra pasta existente aninharia.
function Copy-Tree($item, [string]$dstParent) {
  New-Dir $dstParent
  if ($item.PSIsContainer) {
    $dst = Join-Path $dstParent $item.Name
    New-Dir $dst
    Copy-Item -Recurse -Force (Join-Path $item.FullName '*') $dst
  } else {
    Copy-Item -Force $item.FullName $dstParent
  }
}

# ---------- Codex: ~/.codex/config.toml ----------
# O config e GLOBAL e os nomes de tabela ([mcp_servers.serena] etc) sao fixos. Em TOML uma tabela
# declarada duas vezes invalida o arquivo INTEIRO, e ai o Codex descarta a config toda (inclusive
# [windows] - o ChatGPT/Codex Desktop entra em loop ou abre varias instancias). Por isso: bloco
# unico (os legados por-projeto sao removidos), nunca redeclara tabela que ja existe fora do bloco,
# e valida o resultado ANTES de gravar.
function Get-CodexTable([string]$name) {
  switch ($name) {
    'spec-workflow' {
      return ('[mcp_servers.spec-workflow]', 'command = "npx"', 'args = ["-y", "@pimzino/spec-workflow-mcp@latest", "."]') -join "`n"
    }
    'serena' {
      return ('[mcp_servers.serena]', 'command = "serena"', 'args = ["start-mcp-server", "--context", "codex", "--project-from-cwd", "--enable-web-dashboard", "false", "--open-web-dashboard", "false", "--enable-gui-log-window", "false"]') -join "`n"
    }
    'qdrant-memory' {
      $envParts = @('QDRANT_URL = "' + $qUrl + '"')
      if ($Memory -eq 'vps') { $envParts += 'QDRANT_API_KEY = "${QDRANT_API_KEY}"' }
      $envParts += 'COLLECTION_NAME = "' + $collection + '"'
      $envParts += 'EMBEDDING_MODEL = "' + $Embed + '"'
      return ('[mcp_servers.qdrant-memory]', 'command = "uvx"', 'args = ["mcp-server-qdrant"]', ('env = { ' + ($envParts -join ', ') + ' }')) -join "`n"
    }
  }
}
# tabelas ([a.b], nao [[array]]) declaradas mais de uma vez
function Get-TomlDupTables([string]$text) {
  $names = foreach ($l in ($text -split "`n")) {
    if ($l -match '^\s*\[([^\],\[]+)\]\s*(#.*)?$') { $Matches[1] -replace '[\s"]', '' }
  }
  @($names | Group-Object -CaseSensitive | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
}
# 0 = valido | 1 = invalido | 2 = sem python 3.11+ (so deu pra checar duplicatas)
function Test-TomlFile([string]$path) {
  $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    foreach ($c in 'python', 'py', 'python3') {
      if (-not (Get-Command $c -ErrorAction SilentlyContinue)) { continue }
      $pre = @(); if ($c -eq 'py') { $pre = @('-3') }
      & $c @pre -c 'import tomllib' *> $null
      if ($LASTEXITCODE -ne 0) { continue }
      & $c @pre -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], ''rb''))' $path *> $null
      if ($LASTEXITCODE -eq 0) { return 0 } else { return 1 }
    }
    return 2
  } finally { $ErrorActionPreference = $eap }
}
# tabela como estava no bloco anterior do buildison (inclui subtabelas [mcp_servers.X.env])
function Get-OldCodexTable($lines, [string]$name) {
  $h = "[mcp_servers.$name]"; $sub = "[mcp_servers.$name."
  $on = $false
  $out = foreach ($l in $lines) {
    if ($l -match '^\s*\[') {
      $cur = ($l -replace '\s*#.*$', '') -replace '[\s"]', ''
      $on = ($cur -ceq $h) -or $cur.StartsWith($sub)
    }
    if ($on -and $l -notmatch '^\s*$' -and $l -notmatch '^\s*#') { $l }
  }
  (@($out) -join "`n")
}
function Update-CodexMcp {
  $cfg = Join-Path $env:USERPROFILE '.codex\config.toml'
  New-Dir (Split-Path $cfg -Parent)
  $orig = if (Test-Path $cfg) { [IO.File]::ReadAllText($cfg) } else { '' }
  # tira QUALQUER bloco do buildison (o atual e os legados "# >>> buildison (projeto) >>>"),
  # guardando o conteudo dele a parte
  $kept = New-Object System.Collections.Generic.List[string]
  $oldBlock = New-Object System.Collections.Generic.List[string]
  $skip = $false; $blank = 0
  foreach ($l in ($orig -split "`r?`n")) {
    if ($l -match '^\s*# >>> buildison.*>>>') { $skip = $true; continue }
    if ($l -match '^\s*# <<< buildison.*<<<') { $skip = $false; continue }
    if ($skip) { $oldBlock.Add($l); continue }
    if ($l -match '^\s*$') { $blank++; continue }
    for (; $blank -gt 0; $blank--) { $kept.Add('') }
    $kept.Add($l)
  }
  $base = $kept -join "`n"
  $want = @()
  if ($hasSpec)   { $want += 'spec-workflow' }
  if ($hasSerena) { $want += 'serena' }
  if ($hasMemory) { $want += 'qdrant-memory' }
  # O config e de TODOS os projetos: o que um install anterior pos no bloco e este nao pediu
  # continua la (um projeto "lite" nao desliga a memoria que outro projeto usa).
  # Varre o bloco INTEIRO, nao so o trio do buildison: quem edita o ~/.codex/config.toml a mao
  # acaba pondo MCP proprio dentro dos marcadores, e regravar cego apagava isso em silencio.
  $keep = @()
  $seen = @{}
  foreach ($l in $oldBlock) {
    $t = ($l -replace '\s*#.*$', '') -replace '[\s"]', ''
    if ($t -match '^\[mcp_servers\.([^.\]]+)\]$') {
      $nm = $Matches[1]
      if ($seen.ContainsKey($nm)) { continue }
      $seen[$nm] = $true
      if ($want -contains $nm) { continue }
      $keep += $nm
    }
  }
  $pending = @()
  foreach ($n in @($want + $keep)) {
    if ($base -cmatch ('(?m)^[ \t]*\[[ \t]*mcp_servers[ \t]*\.[ \t]*"?' + [regex]::Escape($n) + '"?[ \t]*\][ \t]*(#.*)?$')) {
      Warn "Codex: [mcp_servers.$n] ja existe fora do bloco do buildison - mantido como esta (nao duplico)"
    } else { $pending += $n }
  }
  if ($keep.Count) { Info "Codex: mantido do bloco anterior (outro projeto, ou MCP seu): $($keep -join ', ')" }
  $new = $base
  if ($pending.Count) {
    $tables = foreach ($n in $pending) { if ($want -contains $n) { Get-CodexTable $n } else { Get-OldCodexTable $oldBlock $n } }
    $block = @(
      '# >>> buildison >>>',
      '# Bloco unico e global, regravado a cada install. Tabela que ja existir fora dele NAO e',
      '# repetida aqui (tabela duplicada = TOML invalido = o Codex descarta a config inteira).',
      (@($tables) -join "`n`n"),
      '# <<< buildison <<<'
    ) -join "`n"
    $new = if ($new) { "$new`n`n$block" } else { $block }
  }
  $new = $new + "`n"

  $dups = Get-TomlDupTables $new
  $valid = if ($dups) { 1 } else {
    $tmp = Join-Path $work 'codex-config.toml'
    Write-Utf8 $tmp $new
    Test-TomlFile $tmp
  }
  if ($valid -eq 1) {
    Fail "Codex: o ~/.codex/config.toml ficaria INVALIDO - nao gravei nada (seu arquivo continua como estava)."
    if ($dups) {
      Fail "Tabelas declaradas mais de uma vez (apague as repetidas e rode de novo):"
      $dups | ForEach-Object { Write-Host "    [$_]" -ForegroundColor Red }
    }
    return $false
  }
  if ($valid -eq 2) { Warn "Codex: sem python 3.11+ (tomllib) - validei so tabelas duplicadas" }
  if ($new.TrimEnd() -eq ($orig -replace "`r`n", "`n").TrimEnd()) { Ok "Codex: ~/.codex/config.toml ja estava em dia"; return $true }
  $bak = ''
  if (Test-Path $cfg) { $bak = "$cfg.bak.$([DateTimeOffset]::Now.ToUnixTimeSeconds())"; Copy-Item -Force $cfg $bak }
  Write-Utf8 $cfg $new
  $bakMsg = if ($bak) { " | backup $(Split-Path $bak -Leaf)" } else { '' }
  Ok "Codex: MCP em ~/.codex/config.toml (bloco unico, validado)$bakMsg"
  return $true
}

# ---------- localizar a fonte (repo clonado, ou clonar em temp p/ irm|iex) ----------
# Marcadores UNICOS do repo fonte (install.sh + bin/buildison.mjs) - nao usar AGENTS.md/.claude,
# que todo projeto instalado tem.
$src = $PSScriptRoot
if (-not $src -or -not (Test-Path (Join-Path $src 'install.sh')) -or -not (Test-Path (Join-Path $src 'bin\buildison.mjs'))) {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die 'git e necessario para baixar o buildison.' }
  $src = Join-Path $env:TEMP ('buildison-' + [guid]::NewGuid().ToString('N'))
  Info "Baixando buildison para $src ..."
  git clone --depth 1 $RepoUrl $src 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { Die "Falha ao clonar $RepoUrl" }
}
$work = Join-Path ([IO.Path]::GetTempPath()) ('buildison-work-' + [guid]::NewGuid().ToString('N'))
New-Dir $work

if ($List) {
  Write-Host "Presets (-Preset)" -ForegroundColor White
  Write-Host "  files   so arquivos - AGENTS.md, docs\agent, agents, commands, skills. Sem MCP, sem infra, sem Qdrant."
  Write-Host "  lite    files + MCP spec-workflow (planejamento). Nada pra instalar na maquina."
  Write-Host "  full    lite + serena + memoria Qdrant + .claude\settings.json  (default)"
  Write-Host "  custom  pergunta MCPs, partes e quais itens"
  Write-Host "`nMCPs (-Mcp, ou none)" -ForegroundColor White
  Write-Host "  spec-workflow  planejamento requirements -> design -> tasks (npx, nada a instalar)"
  Write-Host "  serena         navegacao semantica do codigo (precisa de uv + serena)"
  Write-Host "  memory         memoria vetorial Qdrant (precisa de Qdrant local ou VPS)"
  Write-Host "`nPartes (-Parts): agents commands skills settings" -ForegroundColor White
  Write-Host ("`nAgents (-Subagents):  " + ((Get-ItemNames 'agents') -join ' '))
  Write-Host ("Skills (-Skills):     " + ((Get-ItemNames 'skills') -join ' '))
  Write-Host ("Commands (-Commands): " + ((Get-ItemNames 'commands') -join ' '))
  Write-Host "`nDependencias (saem sozinhas se a peca nao for instalada, a menos que voce peca pelo nome):"
  Write-Host "  skill agent-memory -> memory | skill spec-workflow -> spec-workflow | skill local-infra -> infra | agent suporte -> algum MCP"
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
  return
}
Ok "Fonte: $src"

# ---------- destino ----------
if (-not $Dir) {
  if ($Yes) { $Dir = (Get-Location).Path }
  else { $ans = Read-Host "Diretorio do projeto [$((Get-Location).Path)]"; $Dir = if ($ans) { $ans } else { (Get-Location).Path } }
}
if (-not (Test-Path $Dir)) { Die "Diretorio invalido: $Dir" }
$Target = (Resolve-Path $Dir).Path
if ($Target -eq (Resolve-Path $src).Path) { Die 'O destino nao pode ser o proprio repositorio buildison. Use -Dir.' }
Ok "Destino: $Target"

# ---------- o que instalar: flags + o que ja esta no projeto (.buildison) ----------
$presetSet    = [bool]$Preset
$mcpSet       = $PSBoundParameters.ContainsKey('Mcp')
$partsSet     = $PSBoundParameters.ContainsKey('Parts')
$skillsSet    = $PSBoundParameters.ContainsKey('Skills')
$subagentsSet = $PSBoundParameters.ContainsKey('Subagents')
$commandsSet  = $PSBoundParameters.ContainsKey('Commands')
$askCustom    = ($Preset -eq 'custom')
$McpCsv       = (Split-List $Mcp) -join ','
$PartsCsv     = (Split-List $Parts) -join ','
$SkillsCsv    = (Split-List $Skills) -join ','
$SubagentsCsv = (Split-List $Subagents) -join ','
$CommandsCsv  = (Split-List $Commands) -join ','

# Um -Preset na linha de comando e uma escolha nova: ai o arquivo e ignorado.
$projCfg = Join-Path $Target '.buildison'
if ((Test-Path $projCfg) -and -not $presetSet) {
  foreach ($line in (Get-Content -LiteralPath $projCfg)) {
    if ($line -notmatch '^\s*(BUILDISON_\w+)=(.*)$') { continue }
    $k = $Matches[1]; $v = $Matches[2].Trim()
    switch ($k) {
      'BUILDISON_PRESET'    { $Preset = $v; $presetSet = $true }
      'BUILDISON_MCP'       { if (-not $mcpSet)       { $McpCsv = $v;       $mcpSet = $true } }
      'BUILDISON_PARTS'     { if (-not $partsSet)     { $PartsCsv = $v;     $partsSet = $true } }
      'BUILDISON_SKILLS'    { if (-not $skillsSet)    { $SkillsCsv = $v;    $skillsSet = $true } }
      'BUILDISON_SUBAGENTS' { if (-not $subagentsSet) { $SubagentsCsv = $v; $subagentsSet = $true } }
      'BUILDISON_COMMANDS'  { if (-not $commandsSet)  { $CommandsCsv = $v;  $commandsSet = $true } }
    }
  }
  Info "Usando a escolha salva em .buildison (preset $Preset) - passe -Preset pra mudar"
}

# ---------- selecao de agentes ----------
$AgentsCsv = (Split-List $Agents) -join ','
if (-not $AgentsCsv -and -not $Yes) {
  Write-Host "Quais agentes configurar?" -ForegroundColor White
  Write-Host "  1) Claude Code`n  2) Codex`n  3) OpenCode/Hermes`n  4) Antigravity (Google)`n  5) Todos"
  $sel = Read-Host "Escolha (ex: 1,2 ou 5)"
  if ($sel -match '5') { $AgentsCsv = 'claude,codex,opencode,antigravity' }
  else {
    $a = @()
    if ($sel -match '1') { $a += 'claude' }
    if ($sel -match '2') { $a += 'codex' }
    if ($sel -match '3') { $a += 'opencode' }
    if ($sel -match '4') { $a += 'antigravity' }
    $AgentsCsv = ($a -join ',')
  }
}
if (-not $AgentsCsv) { $AgentsCsv = 'claude' }
$selClaude      = Test-Csv $AgentsCsv 'claude'
$selCodex       = Test-Csv $AgentsCsv 'codex'
$selOpencode    = Test-Csv $AgentsCsv 'opencode'
$selAntigravity = Test-Csv $AgentsCsv 'antigravity'

# ---------- preset ----------
if (-not $presetSet -and -not $mcpSet -and -not $partsSet) {
  if ($Yes) { $Preset = 'full' } else {
    Write-Host "`nO que instalar?" -ForegroundColor White
    Write-Host "  1) So arquivos - agents, skills, commands e AGENTS.md. Sem MCP, sem infra, sem Qdrant."
    Write-Host "  2) Leve        - arquivos + spec-workflow (planejamento). Nada pra instalar na maquina."
    Write-Host "  3) Completo    - leve + Serena + memoria Qdrant + settings.json do Claude"
    Write-Host "  4) Sob medida  - escolho os MCPs e quais agents/skills/commands"
    $pr = Read-Host "Escolha [3]"
    switch ($pr) {
      '1'     { $Preset = 'files' }
      '2'     { $Preset = 'lite' }
      '4'     { $Preset = 'custom'; $askCustom = $true }
      default { $Preset = 'full' }
    }
  }
}
if (-not $Preset) { $Preset = 'custom' }   # veio so -Mcp/-Parts: parte dos defaults do full
switch ($Preset) {
  'files' { $defMcp = '';                            $defParts = 'agents,commands,skills' }
  'lite'  { $defMcp = 'spec-workflow';               $defParts = 'agents,commands,skills' }
  default { $defMcp = 'spec-workflow,serena,memory'; $defParts = 'agents,commands,skills,settings' }
}

if ($askCustom) {
  if ($Yes) { Die '-Preset custom e interativo. Com -Yes, use -Mcp/-Parts/-Skills/-Subagents/-Commands.' }
  if (-not $mcpSet) {
    Write-Host "`nQuais MCPs? (virgula; enter = nenhum)" -ForegroundColor White
    Write-Host "  1) spec-workflow - planejamento (npx, nada a instalar)"
    Write-Host "  2) serena        - navegacao semantica do codigo (precisa de uv)"
    Write-Host "  3) memory        - memoria vetorial Qdrant (precisa de Qdrant local ou VPS)"
    $McpCsv = Read-Host ">"; $mcpSet = $true
  }
  if (-not $partsSet) {
    Write-Host "`nQuais partes do .claude\? (enter = agents,commands,skills)" -ForegroundColor White
    Write-Host "  settings = .claude\settings.json (permissoes amplas + plugins) - so entra se pedir"
    $r = Read-Host ">"
    $PartsCsv = if ($r) { $r } else { 'agents,commands,skills' }; $partsSet = $true
  }
  $partsNow = ConvertTo-PartsCsv $PartsCsv
  foreach ($part in 'skills', 'agents', 'commands') {
    if (-not (Test-Csv $partsNow $part)) { continue }
    Write-Host "`nQuais $part? (virgula; enter = todos)" -ForegroundColor White
    Write-Host ("  " + ((Get-ItemNames $part) -join ' '))
    $r = Read-Host ">"
    switch ($part) {
      'skills'   { if (-not $skillsSet)    { $SkillsCsv = $r } }
      'agents'   { if (-not $subagentsSet) { $SubagentsCsv = $r } }
      'commands' { if (-not $commandsSet)  { $CommandsCsv = $r } }
    }
  }
}

if (-not $mcpSet)   { $McpCsv = $defMcp }
if (-not $partsSet) { $PartsCsv = $defParts }
$McpCsv       = ConvertTo-McpCsv $McpCsv
$PartsCsv     = ConvertTo-PartsCsv $PartsCsv
$SkillsCsv    = ConvertTo-ItemsCsv $SkillsCsv
$SubagentsCsv = ConvertTo-ItemsCsv $SubagentsCsv
$CommandsCsv  = ConvertTo-ItemsCsv $CommandsCsv
foreach ($pair in @(@('skills', $SkillsCsv), @('agents', $SubagentsCsv), @('commands', $CommandsCsv))) {
  foreach ($n in (Split-List $pair[1])) {
    $base = Join-Path $src ".claude\$($pair[0])\$n"
    if (-not (Test-Path $base) -and -not (Test-Path "$base.md")) { Warn "$($pair[0]): '$n' nao existe no buildison (ignorado) - veja -List" }
  }
}
$hasSpec   = Test-Csv $McpCsv 'spec-workflow'
$hasSerena = Test-Csv $McpCsv 'serena'
$hasMemory = Test-Csv $McpCsv 'memory'

# ---------- pre-requisitos da maquina (opt-in; so pergunta o que faz sentido pro que foi escolhido) ----------
$doInfra = if ($Infra) { $true } elseif ($NoInfra -or $Yes -or -not $hasMemory) { $false } else {
  Write-Host "`nMontar o local-infra (stack global da maquina)?" -ForegroundColor White
  Write-Host "  Stack Docker unico (Postgres + Redis + Qdrant + tunnels) que sobe UMA vez e serve TODOS"
  Write-Host "  os seus projetos. O Qdrant guarda a memoria dos agentes. Senhas aleatorias."
  Write-Host "  (pule se ja tem, se usa Qdrant na VPS, ou se nao usa Docker)"
  (Read-Host "  [s/N]") -match '^[sSyY]'
}
$doSerena = if ($Serena) { $true } elseif ($NoSerena -or $Yes -or -not $hasSerena) { $false } else {
  Write-Host "`nInstalar o Serena (navegacao semantica do codigo)?" -ForegroundColor White
  Write-Host "  CLI no host via uv (nao e container). Necessario pro MCP 'serena' conectar."
  (Read-Host "  [s/N]") -match '^[sSyY]'
}

# ---------- modo de memoria (local vs VPS) - so se a memoria foi escolhida ----------
$bldCfgDir = Join-Path $env:USERPROFILE '.buildison'
$bldCfg    = Join-Path $bldCfgDir 'vps.env'
if ($hasMemory) {
  if (-not $Memory -or -not $QdrantUrl) {
    if (Test-Path $bldCfg) {
      Get-Content $bldCfg | ForEach-Object {
        if ($_ -match '^\s*BUILDISON_MEMORY_MODE=(.+)$' -and -not $Memory)   { $Memory = $Matches[1].Trim() }
        if ($_ -match '^\s*BUILDISON_QDRANT_URL=(.+)$'  -and -not $QdrantUrl) { $QdrantUrl = $Matches[1].Trim() }
      }
    }
  }
  if (-not $Memory) {
    if ($Yes) { $Memory = 'local' } else {
      Write-Host "`nOnde fica a memoria (Qdrant) deste e dos proximos projetos desta maquina?" -ForegroundColor White
      Write-Host "  1) Local - http://localhost:6333 (do ~/local-infra). Simples; memoria so nesta maquina."
      Write-Host "  2) VPS   - HTTPS publico com api-key. Memoria segue voce entre maquinas."
      Write-Host "  (essa escolha e salva em $bldCfg e vale pra novos projetos.)"
      $mm = Read-Host "Escolha [1]"
      $Memory = if ($mm -eq '2') { 'vps' } else { 'local' }
    }
  }
  if ($Memory -eq 'vps' -and -not $QdrantUrl) {
    if ($Yes) { Die '-Memory vps requer -QdrantUrl <URL> em modo -Yes.' }
    $QdrantUrl = Read-Host "URL do Qdrant na VPS (ex: https://qdrant.seu-dominio.com)"
    if (-not $QdrantUrl) { Die 'URL vazia.' }
  }
  New-Dir $bldCfgDir
  Write-Utf8 $bldCfg ("# Config per-maquina do buildison - apague o arquivo pra ser perguntado de novo.`nBUILDISON_MEMORY_MODE=$Memory`nBUILDISON_QDRANT_URL=$QdrantUrl`n")
  Ok "Config per-maquina: $bldCfg"
}
if (-not $Memory) { $Memory = 'local' }

$qUrl = if ($Memory -eq 'vps') { $QdrantUrl } else { 'http://localhost:6333' }
# collection do Qdrant derivada do nome do projeto
$projName = (Split-Path $Target -Leaf).ToLower() -replace '[^a-z0-9_]', '_'
if (-not $projName) { $projName = 'project_main' }
$collection = "agent_$projName"
# Num -Update, respeita a collection que ja esta no .mcp.json (pode ter sido ajustada a mao)
if ($hasMemory -and $Update -and (Test-Path (Join-Path $Target '.mcp.json'))) {
  try {
    $prev = (Get-Content -Raw (Join-Path $Target '.mcp.json') | ConvertFrom-Json).mcpServers.'qdrant-memory'.env.COLLECTION_NAME
    if ($prev -and $prev -ne $collection) { Warn "mantendo collection existente: $prev (derivada seria $collection)"; $collection = $prev }
  } catch { }
}
if ($hasMemory) { Info "Memoria: $Memory ($qUrl) | collection $collection" }
$qEnvPairs = @("`"QDRANT_URL`": `"$qUrl`"")
if ($Memory -eq 'vps') { $qEnvPairs += '"QDRANT_API_KEY": "${QDRANT_API_KEY}"' }
$qEnvPairs += "`"COLLECTION_NAME`": `"$collection`""
$qEnvPairs += "`"EMBEDDING_MODEL`": `"$Embed`""
$qEnvJson = '{ ' + ($qEnvPairs -join ', ') + ' }'

# ---------- tags: o que existe neste projeto (filtra AGENTS.md, templates e itens) ----------
$Tags = @()
if ($hasSpec)   { $Tags += 'spec' }
if ($hasSerena) { $Tags += 'serena' }
if ($hasMemory) { $Tags += 'memory' }
if ($McpCsv)    { $Tags += 'mcp' }
if ($Preset -eq 'full' -or $doInfra -or ($hasMemory -and $Memory -eq 'local')) { $Tags += 'infra' }

$mcpLabel = if ($McpCsv) { $McpCsv } else { 'nenhum' }
Info "Instalando: preset $Preset | MCP: $mcpLabel | partes: $PartsCsv"

# ---------- core compartilhado ----------
Info "Instalando core compartilhado..."
Render-Tagged (Join-Path $src 'AGENTS.md') (Join-Path $work 'AGENTS.md')
Copy-Boiler (Join-Path $work 'AGENTS.md') (Join-Path $Target 'AGENTS.md')
# Copia dos TEMPLATES, nao do context.md/decisions.md do proprio buildison - aqueles descrevem
# o buildison e vazariam pra todo projeto herdado. (Fallback pra clones antigos.)
$ctxSrc = Join-Path $src 'docs\agent\templates\context.md';   if (-not (Test-Path $ctxSrc)) { $ctxSrc = Join-Path $src 'docs\agent\context.md' }
$decSrc = Join-Path $src 'docs\agent\templates\decisions.md'; if (-not (Test-Path $decSrc)) { $decSrc = Join-Path $src 'docs\agent\decisions.md' }
Render-Tagged $ctxSrc (Join-Path $work 'context.md')
Render-Tagged $decSrc (Join-Path $work 'decisions.md')
Copy-Keep (Join-Path $work 'context.md')   (Join-Path $Target 'docs\agent\context.md')
Copy-Keep (Join-Path $work 'decisions.md') (Join-Path $Target 'docs\agent\decisions.md')
if ($hasSpec -and (Test-Path (Join-Path $src '.spec-workflow\templates'))) {
  $twDst = Join-Path $Target '.spec-workflow\templates'
  New-Dir $twDst
  Copy-Item -Recurse -Force (Join-Path $src '.spec-workflow\templates\*') $twDst
  Ok ".spec-workflow\templates\"
}

# ---------- Claude Code ----------
if ($selClaude) {
  Info "Configurando Claude Code..."
  foreach ($part in 'agents', 'commands', 'skills') {
    $pdir = Join-Path $src ".claude\$part"
    if (-not (Test-Path $pdir)) { continue }
    $n = 0
    foreach ($item in (Get-ChildItem -LiteralPath $pdir)) {
      if (-not (Test-ItemSelected $part ($item.Name -replace '\.md$', ''))) { continue }
      Copy-Tree $item (Join-Path $Target ".claude\$part")
      $n++
    }
    if ($n) { Ok ".claude\$part\ ($n)" }
  }
  if ((Test-Csv $PartsCsv 'settings') -and (Test-Path (Join-Path $src '.claude\settings.json'))) {
    Copy-Boiler (Join-Path $src '.claude\settings.json') (Join-Path $Target '.claude\settings.json')
  }
  # A copia MESCLA (nao sincroniza): item renomeado/removido do buildison fica orfao. Nao deletamos
  # (pode ser customizacao sua), so listamos.
  if ($Update) {
    $orphans = @()
    foreach ($sub in 'agents', 'commands', 'skills') {
      $tdir = Join-Path $Target ".claude\$sub"
      if (-not (Test-Path $tdir)) { continue }
      foreach ($f in (Get-ChildItem -LiteralPath $tdir)) {
        if ($f.Name -like '*.bak') { continue }
        if (-not (Test-Path (Join-Path $src ".claude\$sub\$($f.Name)"))) { $orphans += ".claude\$sub\$($f.Name)" }
      }
    }
    if ($orphans) {
      Warn "Arquivos em .claude\ que nao existem mais no buildison (seus, ou resquicio de versao antiga):"
      $orphans | ForEach-Object { Write-Host "  $_" }
      Warn "Revise e remova os que forem resquicio."
    }
  }
  # !! O CLAUDE.md tem natureza DUPLA: os @imports sao boilerplate, mas o resto e documentacao do
  # projeto. Regravar cego destroi isso (ja aconteceu). Se ja existe, NAO tocamos.
  $claudeMdPath = Join-Path $Target 'CLAUDE.md'
  if ((Test-Path $claudeMdPath) -and -not $Force) {
    Warn "mantido (ja existe): CLAUDE.md - confira se tem os @imports de AGENTS.md e docs/agent/context.md"
  } else {
    # template unico (bash e PowerShell): as secoes de Serena/memoria saem pelas tags
    Render-Tagged (Join-Path $src 'docs\agent\templates\claude-md.md') $claudeMdPath
    Ok "CLAUDE.md"
  }
  if ($McpCsv) {
    $entries = @()
    if ($hasSpec)   { $entries += '    "spec-workflow": { "command": "npx", "args": ["-y", "@pimzino/spec-workflow-mcp@latest", "."] }' }
    if ($hasSerena) { $entries += '    "serena": { "command": "serena", "args": ["start-mcp-server", "--context", "claude-code", "--project", ".", "--enable-web-dashboard", "false", "--open-web-dashboard", "false", "--enable-gui-log-window", "false"] }' }
    if ($hasMemory) { $entries += "    `"qdrant-memory`": {`n      `"command`": `"uvx`",`n      `"args`": [`"mcp-server-qdrant`"],`n      `"env`": $qEnvJson`n    }" }
    Write-Utf8 (Join-Path $Target '.mcp.json') ("{`n  `"mcpServers`": {`n" + ($entries -join ",`n") + "`n  }`n}`n")
    Ok ".mcp.json ($McpCsv)"
  } else {
    Ok "Claude: sem MCP neste preset - .mcp.json nao gerado"
  }
}

# ---------- Codex (AGENTS.md ja copiado; MCP no ~/.codex/config.toml) ----------
$codexFailed = $false
if ($selCodex) {
  Info "Configurando Codex..."
  if ($McpCsv) {
    if (-not (Update-CodexMcp)) { $codexFailed = $true }
  } else {
    Ok "Codex: sem MCP neste preset - ~/.codex/config.toml nao foi tocado"
  }
  Ok "Codex: AGENTS.md (lido nativamente da raiz do projeto)"
}

# ---------- OpenCode/Hermes ----------
if ($selOpencode) {
  Info "Configurando OpenCode/Hermes..."
  if (-not $McpCsv) {
    Ok "OpenCode: sem MCP neste preset - opencode.json nao gerado"
  } else {
    $entries = @()
    if ($hasSpec)   { $entries += '    "spec-workflow": { "type": "local", "command": ["npx", "-y", "@pimzino/spec-workflow-mcp@latest", "."], "enabled": true }' }
    if ($hasSerena) { $entries += '    "serena": { "type": "local", "command": ["serena", "start-mcp-server", "--context", "ide", "--project-from-cwd", "--enable-web-dashboard", "false", "--open-web-dashboard", "false", "--enable-gui-log-window", "false"], "enabled": true }' }
    if ($hasMemory) { $entries += "    `"qdrant-memory`": {`n      `"type`": `"local`",`n      `"command`": [`"uvx`", `"mcp-server-qdrant`"],`n      `"environment`": $qEnvJson,`n      `"enabled`": true`n    }" }
    $oc = "{`n  `"`$schema`": `"https://opencode.ai/config.json`",`n  `"mcp`": {`n" + ($entries -join ",`n") + "`n  }`n}`n"
    $ocCfg = Join-Path $Target 'opencode.json'
    if ((Test-Path $ocCfg) -and -not $Force) {
      Write-Utf8 (Join-Path $Target 'opencode.buildison.json') $oc
      Warn "opencode.json ja existe - gravei opencode.buildison.json; faca merge do bloco mcp manualmente."
    } else { Write-Utf8 $ocCfg $oc; Ok "opencode.json" }
  }
  Ok "OpenCode: AGENTS.md (lido nativamente da raiz do projeto)"
}

# ---------- Antigravity (Google) - AGENTS.md nativo + .agents/ + MCP global ----------
# Config GLOBAL (nao por-projeto): usa caminho ABSOLUTO do projeto + a collection deste projeto.
# Windows: ~/.gemini/antigravity/mcp_config.json  (fallback ~/.gemini/config/mcp_config.json).
if ($selAntigravity) {
  Info "Configurando Antigravity..."
  $agentsSrc = Join-Path $src '.agents'
  if (Test-Path $agentsSrc) {
    $ns = 0; $nw = 0
    $skDir = Join-Path $agentsSrc 'skills'
    if (Test-Path $skDir) {
      foreach ($f in (Get-ChildItem -LiteralPath $skDir)) {
        if (Test-ItemSelected 'skills' ($f.Name -replace '\.md$', '')) { Copy-Tree $f (Join-Path $Target '.agents\skills'); $ns++ }
      }
    }
    $wfDir = Join-Path $agentsSrc 'workflows'
    if (Test-Path $wfDir) {
      foreach ($f in (Get-ChildItem -LiteralPath $wfDir)) {
        $name = $f.Name -replace '\.md$', ''
        $part = if (Test-Path (Join-Path $src ".claude\commands\$name.md")) { 'commands' }
                elseif (Test-Path (Join-Path $src ".claude\agents\$name.md")) { 'agents' } else { '' }
        if (-not $part -or (Test-ItemSelected $part $name)) { Copy-Tree $f (Join-Path $Target '.agents\workflows'); $nw++ }
      }
    }
    Ok ".agents\ ($ns skills, $nw workflows)"
  } else {
    Warn ".agents\ nao existe na fonte - rode 'node scripts/gen-antigravity.mjs' no repo buildison."
  }
  if (-not $McpCsv) {
    Ok "Antigravity: sem MCP neste preset - config global do Gemini nao foi tocado"
  } else {
    $agCands = @(
      (Join-Path $env:USERPROFILE '.gemini\antigravity\mcp_config.json'),
      (Join-Path $env:USERPROFILE '.gemini\config\mcp_config.json')
    )
    $agCfg = $agCands | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $agCfg) { $agCfg = $agCands[0] }
    if (Test-Path $agCfg) {
      Copy-Item $agCfg "$agCfg.bak.$([DateTimeOffset]::Now.ToUnixTimeSeconds())" -Force
      $agObj = Get-Content $agCfg -Raw | ConvertFrom-Json
    } else { $agObj = [pscustomobject]@{} }
    if (-not $agObj.mcpServers) { $agObj | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) -Force }
    if ($hasSpec) {
      $agObj.mcpServers | Add-Member -NotePropertyName 'spec-workflow' -Force -NotePropertyValue ([pscustomobject][ordered]@{ command = 'npx'; args = @('-y', '@pimzino/spec-workflow-mcp@latest', $Target) })
    }
    if ($hasSerena) {
      $agObj.mcpServers | Add-Member -NotePropertyName 'serena' -Force -NotePropertyValue ([pscustomobject][ordered]@{ command = 'serena'; args = @('start-mcp-server', '--context', 'ide-assistant', '--project', $Target, '--enable-web-dashboard', 'false', '--open-web-dashboard', 'false', '--enable-gui-log-window', 'false') })
    }
    if ($hasMemory) {
      $agEnv = [ordered]@{ QDRANT_URL = $qUrl }
      if ($Memory -eq 'vps') { $agEnv['QDRANT_API_KEY'] = '${QDRANT_API_KEY}' }
      $agEnv['COLLECTION_NAME'] = $collection
      $agEnv['EMBEDDING_MODEL'] = $Embed
      $agObj.mcpServers | Add-Member -NotePropertyName 'qdrant-memory' -Force -NotePropertyValue ([pscustomobject][ordered]@{ command = 'uvx'; args = @('mcp-server-qdrant'); env = [pscustomobject]$agEnv })
    }
    Write-Utf8 $agCfg (($agObj | ConvertTo-Json -Depth 16) + "`n")
    Ok "Antigravity: MCP em $agCfg ($McpCsv)"
  }
  Ok "Antigravity: AGENTS.md (lido nativamente da raiz)"
}

# ---------- registra a escolha no projeto ----------
Write-Utf8 $projCfg ((@(
  '# buildison - o que esta instalado neste projeto. As proximas execucoes (e o -Update) releem',
  '# este arquivo. Pra mudar: rode o instalador com outro -Preset, ou edite aqui.',
  "BUILDISON_PRESET=$Preset",
  "BUILDISON_MCP=$McpCsv",
  "BUILDISON_PARTS=$PartsCsv",
  "BUILDISON_SKILLS=$SkillsCsv",
  "BUILDISON_SUBAGENTS=$SubagentsCsv",
  "BUILDISON_COMMANDS=$CommandsCsv"
) -join "`n") + "`n")
Ok ".buildison"

# ---------- local-infra (opt-in) ----------
$infraPass = ""
if ($doInfra) {
  Info "Montando local-infra..."
  $infraDir = Join-Path $env:USERPROFILE 'local-infra'
  if ((Test-Path $infraDir) -and -not $Force) {
    Warn "local-infra ja existe em $infraDir (pulando). Use -Force pra recriar."
  } else {
    New-Dir (Join-Path $infraDir 'postgres-init')
    $infraPass = New-RandomPassword
    Write-Utf8 (Join-Path $infraDir '.env') @"
# Gerado pelo buildison installer (dev only)
POSTGRES_PASSWORD=$infraPass
NGROK_AUTHTOKEN=
CLOUDFLARE_TUNNEL_TOKEN=
"@
    Write-Utf8 (Join-Path $infraDir 'postgres-init\01-extensions.sql') @'
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
-- CREATE DATABASE projeto_x OWNER dev;
'@
    Write-Utf8 (Join-Path $infraDir 'docker-compose.yml') @'
services:
  postgres:
    image: postgres:16-alpine
    container_name: local-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: dev
      PGDATA: /var/lib/postgresql/data/pgdata
    ports: ["5432:5432"]
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./postgres-init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dev -d dev"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks: [local-infra]
  redis:
    image: redis:7-alpine
    container_name: local-redis
    restart: unless-stopped
    command: redis-server --appendonly yes --maxmemory 512mb --maxmemory-policy allkeys-lru
    ports: ["6379:6379"]
    volumes: [redis-data:/data]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    networks: [local-infra]
  qdrant:
    image: qdrant/qdrant:latest
    container_name: local-qdrant
    restart: unless-stopped
    ports: ["6333:6333", "6334:6334"]
    volumes: [qdrant-data:/qdrant/storage]
    networks: [local-infra]
  ngrok:
    image: ngrok/ngrok:latest
    container_name: local-ngrok
    restart: unless-stopped
    environment:
      NGROK_AUTHTOKEN: ${NGROK_AUTHTOKEN}
    command: "http --log=stdout host.docker.internal:8000"
    ports: ["4040:4040"]
    extra_hosts: ["host.docker.internal:host-gateway"]
    networks: [local-infra]
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: local-cloudflared
    restart: unless-stopped
    command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}
    extra_hosts: ["host.docker.internal:host-gateway"]
    networks: [local-infra]
volumes:
  postgres-data: { name: local-postgres-data }
  redis-data: { name: local-redis-data }
  qdrant-data: { name: local-qdrant-data }
networks:
  local-infra: { name: local-infra, driver: bridge }
'@
    Ok "local-infra criado em $infraDir (senha do Postgres aleatoria)"
  }
}

# ---------- Serena (opt-in) ----------
if ($doSerena) {
  Info "Configurando Serena..."
  if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Warn "uv nao encontrado - instale (winget install astral-sh.uv) e rode: uv tool install -p 3.13 serena-agent; serena init"
  } elseif ((Get-Command serena -ErrorAction SilentlyContinue) -and -not $Force) {
    Ok "Serena ja instalado"
  } else {
    uv tool install -p 3.13 serena-agent; serena init 2>$null
    Ok "Serena instalado"
  }
}

# ---------- resumo ----------
Write-Host ""
Ok "Instalacao concluida em $Target (preset $Preset | MCP: $mcpLabel)"
if ($codexFailed) { Warn "Codex NAO foi configurado: conserte as tabelas repetidas no ~/.codex/config.toml e rode de novo." }
if ($infraPass) {
  Write-Host "`nlocal-infra criado - guarde a credencial:" -ForegroundColor White
  Write-Host "  Postgres user: dev"
  Write-Host "  Postgres senha: $infraPass"
  Write-Host "  (em ~/local-infra/.env | conn: postgresql://dev:$infraPass@localhost:5432/<db>)"
}
if ($hasMemory -and $Memory -eq 'vps') {
  Write-Host "`nMemoria: VPS ($qUrl)" -ForegroundColor White
  Write-Host "  O .mcp.json usa `${QDRANT_API_KEY} (expandida do AMBIENTE do shell que abre o claude)."
  Write-Host "  Exporte a key UMA vez antes de rodar:"
  Write-Host "    `$env:QDRANT_API_KEY = '<sua-api-key>'     # por sessao (PowerShell)"
  Write-Host "    [Environment]::SetEnvironmentVariable('QDRANT_API_KEY','<sua-api-key>','User')  # persistente"
  Write-Host "  Doc: docs/infra/qdrant-vps-template.md (no buildison)"
}
$steps = New-Object System.Collections.Generic.List[string]
if ($hasMemory) {
  if ($Memory -eq 'local') {
    if ($doInfra) { $steps.Add("Subir infra:  cd `$HOME\local-infra; docker compose up -d") }
    else          { $steps.Add("Infra (se ainda nao tem): rode de novo com -Infra, ou suba seu ~/local-infra") }
  } else {
    $steps.Add("Garanta que a VPS Qdrant esta no ar (HTTPS) e QDRANT_API_KEY exportada")
  }
}
if ($hasSerena -and -not $doSerena) { $steps.Add("Serena: uv tool install -p 3.13 serena-agent; serena init") }
if ($selClaude) {
  if ($McpCsv) { $steps.Add("Claude:      abra o projeto e rode /mcp pra aprovar os servidores") }
  else         { $steps.Add("Claude:      abra o projeto - agents, skills e commands ja estao em .claude\") }
}
if ($selCodex) {
  if ($McpCsv) { $steps.Add("Codex:       abra o projeto (le AGENTS.md); MCP em ~/.codex/config.toml") }
  else         { $steps.Add("Codex:       abra o projeto (le AGENTS.md)") }
}
if ($selOpencode)    { $steps.Add("OpenCode:    abra o projeto (le AGENTS.md$(if ($McpCsv) { ' + opencode.json' }))") }
if ($selAntigravity) { $steps.Add("Antigravity: abra o projeto (le AGENTS.md + .agents\)") }
$steps.Add("Preencha docs\agent\context.md com o stack real do projeto.")
Write-Host "`nProximos passos:" -ForegroundColor White
for ($i = 0; $i -lt $steps.Count; $i++) { Write-Host ("  {0}. {1}" -f ($i + 1), $steps[$i]) }

Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
