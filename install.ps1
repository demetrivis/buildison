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
  files   so arquivos: AGENTS.md, docs\agent, agents, commands, skills. Sem MCP e sem infra.
  lite    files + MCP spec-workflow
  full    lite + serena + .claude\settings.json (default)
  custom  pergunta MCPs, partes e itens

Sob medida (partem do preset e sobrescrevem so o que for passado):
  -Mcp spec-workflow,serena | none
  -Parts agents,commands,skills,settings
  -Skills / -Subagents / -Commands <nomes>   (default: todos, menos os que dependem de peca nao instalada)
A escolha fica em .buildison na raiz do projeto e e reaproveitada nas proximas execucoes.

-Update atualiza so o boilerplate (AGENTS.md, .claude\, .agents\, .spec-workflow\templates\, .mcp.json)
e preserva CLAUDE.md, docs\agent\context.md e docs\agent\decisions.md. Nao use -Force pra atualizar.

Agentes: claude, codex, opencode, antigravity (no -Global: claude e codex)
Flags: -Dir -Agents -Preset -Mcp -Parts -Skills -Subagents -Commands -List -Infra/-NoInfra
       -Serena/-NoSerena -Yes -Force -Update -Global -PluginSkills

  -Global instala agents, commands e skills pra TODOS os projetos da maquina:
    Claude Code -> ~\.claude\{agents,commands,skills}   Codex -> ~\.agents\skills
  Duas versoes: -Preset files (sem spec-workflow, default) ou -Preset lite (com: skill + MCP
  spec-workflow no escopo user do Claude e no ~/.codex/config.toml). Rodar de novo atualiza
  (rele ~\.buildison\global.env). Item que o buildison nao pos la e seu e nao e sobrescrito.
  -PluginSkills <lista|none> (so com -Global) leva pro Codex as skills de plugins do Claude Code
  instalados NESTA maquina (ex.: eng-arq). O conteudo vem do seu disco, nunca do repo buildison.

  Memoria vetorial (Qdrant) NAO e mais instalada aqui: virou a skill 'qdrant-setup'
  (+ command /qdrant). Peca ao agente "configura a memoria" depois de instalar.
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
  [switch]$Yes,
  [switch]$Force,
  [switch]$Update,
  [switch]$Global,
  [string[]]$PluginSkills = @(),
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$RepoUrl = 'https://github.com/demetrivis/buildison.git'

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
      '^(memory|memoria|qdrant|qdrant-memory)$' { Die "-Mcp memory saiu do instalador: a memoria Qdrant virou a skill 'qdrant-setup' (command /qdrant)." }
      '^(none|nenhum)$'                                   { ''; break }
      default { Die "-Mcp: '$x' desconhecido (use spec-workflow, serena ou none)" }
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
  Write-Host "  files   so arquivos - AGENTS.md, docs\agent, agents, commands, skills. Sem MCP e sem infra."
  Write-Host "  lite    files + MCP spec-workflow (planejamento). Nada pra instalar na maquina."
  Write-Host "  full    lite + serena + .claude\settings.json  (default)"
  Write-Host "  custom  pergunta MCPs, partes e quais itens"
  Write-Host "`nMCPs (-Mcp, ou none)" -ForegroundColor White
  Write-Host "  spec-workflow  planejamento requirements -> design -> tasks (npx, nada a instalar)"
  Write-Host "  serena         navegacao semantica do codigo (precisa de uv + serena)"
  Write-Host "`nPartes (-Parts): agents commands skills settings" -ForegroundColor White
  Write-Host ("`nAgents (-Subagents):  " + ((Get-ItemNames 'agents') -join ' '))
  Write-Host ("Skills (-Skills):     " + ((Get-ItemNames 'skills') -join ' '))
  Write-Host ("Commands (-Commands): " + ((Get-ItemNames 'commands') -join ' '))
  Write-Host "`nDependencias (saem sozinhas se a peca nao for instalada, a menos que voce peca pelo nome):"
  Write-Host "  skill spec-workflow -> spec-workflow | skill local-infra -> infra | agent suporte -> algum MCP"
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
  return
}
Ok "Fonte: $src"

# ---------- destino ----------
$globalDir = Join-Path $env:USERPROFILE '.buildison'
$globalCfg = Join-Path $globalDir 'global.env'       # a escolha do -Global (preset, filtros, agentes)
$globalMan = Join-Path $globalDir 'global.manifest'  # o que o -Global pos no disco - so isso ele mexe depois
if ($Global) {
  if ($Dir) { Die '-Global nao combina com -Dir: ele instala em ~\.claude (e ~\.agents\skills no Codex).' }
  Ok 'Destino: global - ~\.claude (Claude Code) | ~\.agents\skills (Codex)'
  $Target = $env:USERPROFILE
  $cfgFile = $globalCfg
} else {
  if (-not $Dir) {
    if ($Yes) { $Dir = (Get-Location).Path }
    else { $ans = Read-Host "Diretorio do projeto [$((Get-Location).Path)]"; $Dir = if ($ans) { $ans } else { (Get-Location).Path } }
  }
  if (-not (Test-Path $Dir)) { Die "Diretorio invalido: $Dir" }
  $Target = (Resolve-Path $Dir).Path
  if ($Target -eq (Resolve-Path $src).Path) { Die 'O destino nao pode ser o proprio repositorio buildison. Use -Dir.' }
  Ok "Destino: $Target"
  $cfgFile = Join-Path $Target '.buildison'
}

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
if ((Test-Path -LiteralPath $cfgFile -PathType Leaf) -and -not $presetSet) {
  foreach ($line in (Get-Content -LiteralPath $cfgFile)) {
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
  Info "Usando a escolha salva em $cfgFile (preset $Preset) - passe -Preset pra mudar"
}

# ---------- selecao de agentes ----------
$AgentsCsv = (Split-List $Agents) -join ','
# No global os agentes ficam salvos e valem mesmo trocando de -Preset: sem isso, "-Global -Preset
# lite -Yes" depois de um install com codex cairia no default (so claude) e tiraria as skills do Codex.
if ($Global -and -not $AgentsCsv -and (Test-Path -LiteralPath $globalCfg)) {
  foreach ($line in (Get-Content -LiteralPath $globalCfg)) {
    if ($line -match '^\s*BUILDISON_AGENTS=(.*)$') { $AgentsCsv = $Matches[1].Trim() }
  }
}
# idem pras skills de plugin: sao escolha sua, nao da versao
$PluginSkillsCsv = (Split-List $PluginSkills) -join ','
if ($PSBoundParameters.ContainsKey('PluginSkills') -and -not $Global) {
  Die '-PluginSkills so existe com -Global (leva skill de plugin do Claude pro ~\.agents\skills do Codex).'
}
if ($Global -and -not $PSBoundParameters.ContainsKey('PluginSkills') -and (Test-Path -LiteralPath $globalCfg)) {
  foreach ($line in (Get-Content -LiteralPath $globalCfg)) {
    if ($line -match '^\s*BUILDISON_PLUGIN_SKILLS=(.*)$') { $PluginSkillsCsv = $Matches[1].Trim() }
  }
}
if (Test-Csv $PluginSkillsCsv 'none') { $PluginSkillsCsv = '' }
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
if ($Global) {
  if ($selOpencode)    { Warn '-Global: OpenCode ainda nao tem instalacao global - ignorado' }
  if ($selAntigravity) { Warn '-Global: Antigravity ainda nao tem instalacao global - ignorado' }
  $selOpencode = $false; $selAntigravity = $false
  if (-not $selClaude -and -not $selCodex) { Die '-Global funciona com -Agents claude e/ou codex.' }
}

# ---------- preset ----------
# No -Global so existem duas versoes: sem e com spec-workflow. Serena, settings.json, CLAUDE.md e
# docs\agent\ sao por projeto por natureza.
if ($Global) {
  if (-not $presetSet -and -not $mcpSet -and -not $partsSet) {
    if ($Yes) { $Preset = 'files' } else {
      Write-Host "`nQual versao instalar no global?" -ForegroundColor White
      Write-Host "  1) Sem spec-workflow - agents, commands e skills. So arquivos."
      Write-Host "  2) Com spec-workflow - o mesmo + skill e MCP spec-workflow, valendo em todo projeto."
      $pr = Read-Host "Escolha [1]"
      $Preset = if ($pr -eq '2') { 'lite' } else { 'files' }
    }
    $presetSet = $true
  }
  if (-not $Preset) { $Preset = 'files' }
  if ($Preset -notin @('files', 'lite')) { Die '-Global tem duas versoes: -Preset files (sem spec-workflow) ou -Preset lite (com). Serena e settings.json sao por projeto.' }
}
if (-not $presetSet -and -not $mcpSet -and -not $partsSet) {
  if ($Yes) { $Preset = 'full' } else {
    Write-Host "`nO que instalar?" -ForegroundColor White
    Write-Host "  1) So arquivos - agents, skills, commands e AGENTS.md. Sem MCP e sem infra."
    Write-Host "  2) Leve        - arquivos + spec-workflow (planejamento). Nada pra instalar na maquina."
    Write-Host "  3) Completo    - leve + Serena + settings.json do Claude"
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
  default { $defMcp = 'spec-workflow,serena'; $defParts = 'agents,commands,skills,settings' }
}

if ($askCustom) {
  if ($Yes) { Die '-Preset custom e interativo. Com -Yes, use -Mcp/-Parts/-Skills/-Subagents/-Commands.' }
  if (-not $mcpSet) {
    Write-Host "`nQuais MCPs? (virgula; enter = nenhum)" -ForegroundColor White
    Write-Host "  1) spec-workflow - planejamento (npx, nada a instalar)"
    Write-Host "  2) serena        - navegacao semantica do codigo (precisa de uv)"
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
if ($Global) {
  if (Test-Csv $McpCsv 'serena') { Die '-Global: o Serena e por projeto (precisa do --project). Instale-o no projeto.' }
  if (Test-Csv $PartsCsv 'settings') {
    Warn '-Global: settings.json fica de fora (daria permissoes amplas em todo projeto da maquina)'
    $PartsCsv = ((Split-List $PartsCsv) | Where-Object { $_ -ne 'settings' }) -join ','
  }
}
$hasSpec   = Test-Csv $McpCsv 'spec-workflow'
$hasSerena = Test-Csv $McpCsv 'serena'

# ---------- pre-requisitos da maquina (opt-in; so pergunta o que faz sentido pro que foi escolhido) ----------
# O local-infra nao e mais oferecido sozinho - ele so aparecia porque o Qdrant guardava a
# memoria, e a memoria saiu daqui. Continua disponivel via -Infra e pela skill 'local-infra'.
$doInfra = [bool]$Infra
$doSerena = if ($Serena) { $true } elseif ($NoSerena -or $Yes -or -not $hasSerena) { $false } else {
  Write-Host "`nInstalar o Serena (navegacao semantica do codigo)?" -ForegroundColor White
  Write-Host "  CLI no host via uv (nao e container). Necessario pro MCP 'serena' conectar."
  (Read-Host "  [s/N]") -match '^[sSyY]'
}

# ---------- tags: o que existe neste projeto (filtra AGENTS.md, templates e itens) ----------
$Tags = @()
if ($hasSpec)   { $Tags += 'spec' }
if ($hasSerena) { $Tags += 'serena' }
if ($McpCsv)    { $Tags += 'mcp' }
if ($Preset -eq 'full' -or $doInfra -or $Global) { $Tags += 'infra' }

$mcpLabel = if ($McpCsv) { $McpCsv } else { 'nenhum' }
Info "Instalando: preset $Preset | MCP: $mcpLabel | partes: $PartsCsv"

# ---------- -Global: instala pra todos os projetos da maquina ----------
# O manifest (~\.buildison\global.manifest) lista o que ESTE modo pos no disco. E o que separa
# item do buildison de item seu: so o que esta nele e sobrescrito ou retirado.
function Test-ClaudeUserMcp([string]$name) {
  # Le o ~\.claude.json direto: o `claude mcp get` tambem enxerga o .mcp.json da pasta atual,
  # e ai um servidor de projeto passaria por global.
  $f = Join-Path $env:USERPROFILE '.claude.json'
  if (-not (Test-Path -LiteralPath $f)) { return $false }
  try { $j = Get-Content -Raw -LiteralPath $f | ConvertFrom-Json } catch { return $false }
  return [bool]($j.mcpServers -and ($j.mcpServers.PSObject.Properties.Name -contains $name))
}
function Move-ToRemoved([string]$path) {
  if (-not $script:globalBak) {
    $script:globalBak = Join-Path $globalDir ("removidos-" + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    New-Dir $script:globalBak
  }
  $rel = $path.Substring($env:USERPROFILE.Length).TrimStart('\', '/')
  $to = Join-Path $script:globalBak $rel
  New-Dir (Split-Path $to -Parent)
  Move-Item -LiteralPath $path -Destination $to -Force
}
function Invoke-ClaudeMcp([string[]]$cliArgs) {
  # Dois cuidados do PowerShell 5.1: com EAP=Stop, qualquer linha no stderr de um comando nativo
  # vira excecao; e um `--` solto na linha pode ser engolido pelo parser. Aqui os argumentos vao
  # como array (o '--' e so mais um valor) e so o exit code decide.
  $ErrorActionPreference = 'Continue'
  Push-Location $env:USERPROFILE
  try { & claude @cliArgs *> $null; return ($LASTEXITCODE -eq 0) } catch { return $false } finally { Pop-Location }
}
function Get-PluginRoot([string]$name) {
  # Marketplace fica em installed_plugins.json (com installPath); plugin sincronizado da conta do
  # claude.ai ("My Uploads" etc.) fica em ~\.claude\plugins\synced\<id>\<nome>\.
  $pdir = Join-Path $env:USERPROFILE '.claude\plugins'
  $reg = Join-Path $pdir 'installed_plugins.json'
  if (Test-Path -LiteralPath $reg) {
    try {
      $j = Get-Content -Raw -LiteralPath $reg | ConvertFrom-Json
      foreach ($prop in $j.plugins.PSObject.Properties) {
        if (($prop.Name -split '@')[0] -ne $name) { continue }
        foreach ($i in (@($prop.Value) | Sort-Object { $_.scope -ne 'user' })) {
          if ($i.installPath -and (Test-Path -LiteralPath $i.installPath)) { return $i.installPath }
        }
      }
    } catch { }
  }
  $synced = Join-Path $pdir 'synced'
  if (Test-Path -LiteralPath $synced) {
    foreach ($d in (Get-ChildItem -LiteralPath $synced -Directory)) {
      $p = Join-Path $d.FullName $name
      if (Test-Path -LiteralPath (Join-Path $p '.claude-plugin\plugin.json')) { return $p }
    }
  }
  return ''
}
function Add-GlobalItem($item, [string]$base, $old, $new) {
  # $true = instalou | $false = pulou (item seu). So mexe no que esta no manifest ($old).
  $dst = Join-Path $base $item.Name
  if ((Test-Path -LiteralPath $dst) -and ($old -notcontains $dst)) {
    if (-not $Force) { Warn "$dst ja existe e nao foi o buildison que pos la - mantido (-Force sobrescreve)"; return $false }
    Move-ToRemoved $dst
  }
  # remove antes de copiar: a copia mescla, e arquivo removido de dentro de uma skill ficaria orfao
  if (Test-Path -LiteralPath $dst) { Remove-Item -Recurse -Force -LiteralPath $dst }
  Copy-Tree $item $base
  $new.Add($dst)
  return $true
}
function Install-Global {
  $script:globalBak = ''
  New-Dir $globalDir
  $old = if (Test-Path -LiteralPath $globalMan) { @(Get-Content -LiteralPath $globalMan) } else { @() }
  $new = New-Object System.Collections.Generic.List[string]
  $specCmd = @('npx', '-y', '@pimzino/spec-workflow-mcp@latest', '.')
  $roots = @(); if ($selClaude) { $roots += 'claude' }; if ($selCodex) { $roots += 'codex' }
  if ($hasSpec) { Info 'Instalando no global - versao COM spec-workflow' } else { Info 'Instalando no global - versao SEM spec-workflow' }

  # Claude Code le agents/commands/skills de ~\.claude; o Codex so tem skills, em ~\.agents\skills
  foreach ($root in $roots) {
    foreach ($part in 'agents', 'commands', 'skills') {
      if ($root -eq 'codex' -and $part -ne 'skills') { continue }
      $base = if ($root -eq 'claude') { Join-Path $env:USERPROFILE ".claude\$part" } else { Join-Path $env:USERPROFILE '.agents\skills' }
      $pdir = Join-Path $src ".claude\$part"
      if (-not (Test-Path $pdir)) { continue }
      $n = 0
      foreach ($item in (Get-ChildItem -LiteralPath $pdir)) {
        if (-not (Test-ItemSelected $part ($item.Name -replace '\.md$', ''))) { continue }
        if (Add-GlobalItem $item $base $old $new) { $n++ }
      }
      if ($n) { Ok "$base\ ($n)" }
    }
  }

  # ---- skills de plugins do Claude -> Codex (-PluginSkills) ----
  # O Codex nao roda plugin do Claude, mas le a skill dele em ~\.agents\skills. O conteudo vem do
  # plugin instalado NESTA maquina - o repo buildison nao carrega nada de terceiro.
  $plugsOk = @()
  foreach ($plug in (Split-List $PluginSkillsCsv)) {
    if (-not $selCodex) { Info "plugin ${plug}: sem -Agents codex nao ha o que copiar (no Claude ele ja vem do proprio plugin)"; continue }
    $proot = Get-PluginRoot $plug
    if (-not $proot -or -not (Test-Path -LiteralPath (Join-Path $proot 'skills'))) {
      Warn "plugin '$plug' nao esta instalado no Claude Code desta maquina (ou nao tem skills) - pulado"; continue
    }
    $n = 0
    $cbase = Join-Path $env:USERPROFILE '.agents\skills'
    foreach ($item in (Get-ChildItem -LiteralPath (Join-Path $proot 'skills') -Directory)) {
      if (-not (Test-Path -LiteralPath (Join-Path $item.FullName 'SKILL.md'))) { continue }
      if (-not (Add-GlobalItem $item $cbase $old $new)) { continue }
      $n++
      # ${CLAUDE_PLUGIN_ROOT} so existe dentro do Claude Code: aponta pra pasta da copia
      $dst = Join-Path $cbase $item.Name
      $dstFwd = $dst -replace '\\', '/'
      $left = 0
      foreach ($f in (Get-ChildItem -LiteralPath $dst -Recurse -File -Filter '*.md')) {
        $t = [IO.File]::ReadAllText($f.FullName)
        $u = $t.Replace('${CLAUDE_PLUGIN_ROOT}/skills/' + $item.Name, $dstFwd).Replace('$CLAUDE_PLUGIN_ROOT/skills/' + $item.Name, $dstFwd)
        $left += ([regex]::Matches($u, 'CLAUDE_PLUGIN_ROOT')).Count
        if ($u -ne $t) { Write-Utf8 $f.FullName $u }
      }
      if ($left) { Warn "plugin ${plug}: $dst ainda cita CLAUDE_PLUGIN_ROOT fora da propria skill ($left vez(es)) - isso nao resolve no Codex" }
    }
    if ($n) { Ok "$cbase\ (+$n do plugin $plug | no Claude segue o plugin)"; $plugsOk += $plug }
  }

  # o que o buildison pos antes e nao entra mais: vai pra ~\.buildison\removidos-*, nao pro lixo
  $moved = 0
  foreach ($dst in $old) {
    if (-not $dst -or $dst.StartsWith('mcp:') -or $new.Contains($dst)) { continue }
    if (-not (Test-Path -LiteralPath $dst)) { continue }
    Move-ToRemoved $dst; $moved++
  }
  if ($moved) { Warn "$moved item(ns) que o buildison tinha posto no global sairam da selecao - movidos pra $script:globalBak" }

  # ---- MCP spec-workflow: so na versao "com" ----
  $hasClaudeCli = [bool](Get-Command claude -ErrorAction SilentlyContinue)
  if ($selClaude) {
    if ($hasSpec) {
      if (Test-ClaudeUserMcp 'spec-workflow') {
        Ok 'Claude: MCP spec-workflow ja esta no escopo user - mantido'
        if ($old -contains 'mcp:claude:spec-workflow') { $new.Add('mcp:claude:spec-workflow') }
      } elseif (-not $hasClaudeCli) {
        Warn "Claude: CLI 'claude' nao esta no PATH - MCP nao registrado. Rode: claude mcp add -s user spec-workflow -- $($specCmd -join ' ')"
      } else {
        $okAdd = Invoke-ClaudeMcp (@('mcp', 'add', '-s', 'user', 'spec-workflow', '--') + $specCmd)
        if ($okAdd) { Ok 'Claude: MCP spec-workflow no escopo user (vale em todo projeto)'; $new.Add('mcp:claude:spec-workflow') }
        else { Warn "Claude: falhou registrar o MCP. Rode: claude mcp add -s user spec-workflow -- $($specCmd -join ' ')" }
      }
    } elseif ($old -contains 'mcp:claude:spec-workflow') {
      # so tira se foi o -Global que pos: um spec-workflow registrado a mao fica
      $okRm = $false
      if ($hasClaudeCli) { $okRm = Invoke-ClaudeMcp @('mcp', 'remove', '-s', 'user', 'spec-workflow') }
      if ($okRm) { Ok 'Claude: MCP spec-workflow removido do escopo user (versao sem spec-workflow)' }
      else { Warn 'Claude: nao consegui remover o MCP. Rode: claude mcp remove -s user spec-workflow'; $new.Add('mcp:claude:spec-workflow') }
    }
  }
  $script:codexFailed = $false
  if ($selCodex) {
    if ($hasSpec) {
      if (-not (Update-CodexMcp)) { $script:codexFailed = $true }
      $new.Add('mcp:codex:spec-workflow')
    } elseif ($old -contains 'mcp:codex:spec-workflow') {
      # o ~/.codex/config.toml e o mesmo que os installs por projeto usam: tirar daqui quebraria
      # projeto que conta com ele. Fica, e voce decide.
      Info 'Codex: o spec-workflow continua no ~/.codex/config.toml (config compartilhada com projetos) - tire a mao se quiser'
    }
  }

  Write-Utf8 $globalMan (($new -join "`n") + "`n")
  Write-Utf8 $globalCfg ((@(
    '# buildison - o que esta instalado no GLOBAL (~\.claude e ~\.agents\skills). Rodar',
    '# "install.ps1 -Global" de novo rele este arquivo; passe -Preset files|lite pra trocar de versao.',
    "BUILDISON_PRESET=$Preset",
    "BUILDISON_MCP=$McpCsv",
    "BUILDISON_PARTS=$PartsCsv",
    "BUILDISON_SKILLS=$SkillsCsv",
    "BUILDISON_SUBAGENTS=$SubagentsCsv",
    "BUILDISON_COMMANDS=$CommandsCsv",
    "BUILDISON_AGENTS=$($roots -join ',')",
    "BUILDISON_PLUGIN_SKILLS=$PluginSkillsCsv"
  ) -join "`n") + "`n")

  if ($doInfra -or $doSerena) { Warn '-Infra/-Serena nao rodam junto com -Global no PowerShell: rode-os num install por projeto, ou use a skill local-infra.' }
  Write-Host ""
  if ($script:codexFailed) { Warn 'Codex NAO foi configurado: conserte as tabelas repetidas no ~/.codex/config.toml e rode de novo.' }
  $ver = if ($hasSpec) { 'com' } else { 'sem' }
  $plugTxt = if ($plugsOk.Count) { " | + skills de plugin no Codex: $($plugsOk -join ',')" } else { '' }
  Ok "Global instalado ($($roots -join ',')) - versao $ver spec-workflow$plugTxt"
  Write-Host "`nProximos passos:" -ForegroundColor White
  Write-Host '  1. Abra qualquer projeto: agents, commands e skills ja aparecem (reinicie o agente se estiver aberto).'
  if ($hasSpec -and $selClaude) {
    Write-Host '  2. Os templates proprios do buildison (.spec-workflow\templates\) so vem no install por projeto;'
    Write-Host '     no global o spec-workflow usa os templates padrao dele.'
  }
  Write-Host '  - Atualizar: rode o mesmo comando de novo. Trocar de versao: -Global -Preset files|lite.'
  Write-Host '  - Nao instale o buildison tambem por projeto: os itens aparecem duplicados.'
}
if ($Global) { Install-Global; exit 0 }

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

# ---------- JSON de MCP: regrava preservando o que o instalador nao gerencia ----------
# O arquivo e montado do zero a cada run; sem o merge, um MCP que voce (ou a skill qdrant-setup)
# adicionou sumia em silencio no proximo -Update.
function Merge-McpJson([string]$path, [string]$freshJson, [string[]]$managed) {
  $fresh = [ordered]@{}
  foreach ($p in ($freshJson | ConvertFrom-Json).mcpServers.PSObject.Properties) { $fresh[$p.Name] = $p.Value }
  $obj = $null
  if (Test-Path -LiteralPath $path) { try { $obj = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json } catch { $obj = $null } }
  if ($null -eq $obj) { $obj = [pscustomobject]@{} }
  $servers = [ordered]@{}
  if ($obj.mcpServers) {
    foreach ($p in $obj.mcpServers.PSObject.Properties) {
      # tira so o que ESTE instalador gerencia e nao foi pedido agora; o resto fica
      if (($managed -contains $p.Name) -and -not $fresh.Contains($p.Name)) { continue }
      $servers[$p.Name] = $p.Value
    }
  }
  foreach ($k in $fresh.Keys) { $servers[$k] = $fresh[$k] }
  $obj | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]$servers) -Force
  New-Dir (Split-Path $path -Parent)
  Write-Utf8 $path (($obj | ConvertTo-Json -Depth 16) + "`n")
}
# servidores de projeto presos no config GLOBAL do Antigravity (caminho absoluto ou colecao fixa)
function Get-AntigravityGlobalPinned {
  $out = @()
  foreach ($c in @((Join-Path $env:USERPROFILE '.gemini\config\mcp_config.json'), (Join-Path $env:USERPROFILE '.gemini\antigravity\mcp_config.json'))) {
    if (-not (Test-Path -LiteralPath $c)) { continue }
    try { $j = Get-Content -Raw -LiteralPath $c | ConvertFrom-Json } catch { continue }
    if (-not $j.mcpServers) { continue }
    foreach ($name in 'spec-workflow', 'serena', 'qdrant-memory') {
      $sv = $j.mcpServers.$name
      if (-not $sv) { continue }
      $fixed = @($sv.args | Where-Object { $_ -is [string] -and $_ -match '^(/|[A-Za-z]:[\\/])' })
      $coll = if ($sv.env) { $sv.env.COLLECTION_NAME } else { $null }
      if ($fixed.Count) { $out += "$name -> $($fixed[0])  ($c)" }
      elseif ($coll)    { $out += "$name -> COLLECTION_NAME=$coll  ($c)" }
    }
  }
  return $out
}

# ---------- Claude Code ----------
if ($selClaude) {
  Info "Configurando Claude Code..."
  if ((Test-Path -LiteralPath $globalMan) -and (Get-Item -LiteralPath $globalMan).Length -gt 0) {
    Warn "o buildison tambem esta no global (~\.claude): neste projeto os agents, commands e skills vao aparecer duplicados"
  }
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
    Merge-McpJson (Join-Path $Target '.mcp.json') ("{`n  `"mcpServers`": {`n" + ($entries -join ",`n") + "`n  }`n}`n") @('spec-workflow', 'serena')
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
    $oc = "{`n  `"`$schema`": `"https://opencode.ai/config.json`",`n  `"mcp`": {`n" + ($entries -join ",`n") + "`n  }`n}`n"
    $ocCfg = Join-Path $Target 'opencode.json'
    if ((Test-Path $ocCfg) -and -not $Force) {
      Write-Utf8 (Join-Path $Target 'opencode.buildison.json') $oc
      Warn "opencode.json ja existe - gravei opencode.buildison.json; faca merge do bloco mcp manualmente."
    } else { Write-Utf8 $ocCfg $oc; Ok "opencode.json" }
  }
  Ok "OpenCode: AGENTS.md (lido nativamente da raiz do projeto)"
}

# ---------- Antigravity (Google) - AGENTS.md nativo + .agents/ + MCP por projeto ----------
if ($selAntigravity) {
  Info "Configurando Antigravity..."
  $agentsSrc = Join-Path $src '.agents'
  $skDir = Join-Path $agentsSrc 'skills'
  if (Test-Path $skDir) {
    # Formato antigo deste instalador: skill como .agents\skills\<nome>.md solto, e commands/agentes
    # como .agents\workflows\<nome>.md. Workflows saem do Antigravity em 2026-11-01, arquivo solto nao
    # e skill no padrao atual, e os dois duplicariam os /comandos novos. So sai o que tem a marca do
    # gerador - o que voce escreveu a mao fica.
    $legacy = 0
    foreach ($d in 'skills', 'workflows') {
      $ld = Join-Path $Target ".agents\$d"
      if (-not (Test-Path -LiteralPath $ld)) { continue }
      foreach ($f in (Get-ChildItem -LiteralPath $ld -File -Filter '*.md')) {
        if ((Get-Content -Raw -LiteralPath $f.FullName) -match 'por gen-antigravity\.mjs') { Remove-Item -Force -LiteralPath $f.FullName; $legacy++ }
      }
    }
    $wfOld = Join-Path $Target '.agents\workflows'
    if ((Test-Path -LiteralPath $wfOld) -and -not (Get-ChildItem -LiteralPath $wfOld -Force)) { Remove-Item -Force -LiteralPath $wfOld }
    if ($legacy) { Info "Antigravity: $legacy arquivo(s) do formato antigo (skill solta / workflow) removidos" }
    $ns = 0; $nc = 0; $na = 0
    $skDst = Join-Path $Target '.agents\skills'
    foreach ($f in (Get-ChildItem -LiteralPath $skDir -Directory)) {
      # command convertido em skill segue o filtro de commands; o resto, o de skills
      $part = if (Test-Path (Join-Path $src ".claude\commands\$($f.Name).md")) { 'commands' } else { 'skills' }
      if (-not (Test-ItemSelected $part $f.Name)) { continue }
      $prevSkill = Join-Path $skDst $f.Name
      if (Test-Path -LiteralPath $prevSkill) { Remove-Item -Recurse -Force -LiteralPath $prevSkill }   # a copia mescla: arquivo que saiu da skill ficaria orfao
      Copy-Tree $f $skDst
      if ($part -eq 'commands') { $nc++ } else { $ns++ }
    }
    $agDir = Join-Path $agentsSrc 'agents'
    if (Test-Path $agDir) {
      foreach ($f in (Get-ChildItem -LiteralPath $agDir -File -Filter '*.md')) {
        if (Test-ItemSelected 'agents' ($f.Name -replace '\.md$', '')) { Copy-Tree $f (Join-Path $Target '.agents\agents'); $na++ }
      }
    }
    Ok ".agents\ ($ns skills + $nc commands como skill, $na agents)"
  } else {
    Warn ".agents\skills nao existe na fonte - rode 'node scripts/gen-antigravity.mjs' no repo buildison."
  }
  # MCP de projeto vai no config DO PROJETO (.agents\mcp_config.json), nunca no global. O global
  # vale pra todo projeto aberto no Antigravity: gravar ali prendia serena, spec-workflow e
  # qdrant-memory a UM projeto em todos os outros. Caminhos relativos, igual ao .mcp.json do Claude.
  if (-not $McpCsv) {
    Ok "Antigravity: sem MCP neste preset - .agents\mcp_config.json nao gerado"
  } else {
    $entries = @()
    if ($hasSpec)   { $entries += '    "spec-workflow": { "command": "npx", "args": ["-y", "@pimzino/spec-workflow-mcp@latest", "."] }' }
    if ($hasSerena) { $entries += '    "serena": { "command": "serena", "args": ["start-mcp-server", "--context", "ide-assistant", "--project", ".", "--enable-web-dashboard", "false", "--open-web-dashboard", "false", "--enable-gui-log-window", "false"] }' }
    Merge-McpJson (Join-Path $Target '.agents\mcp_config.json') ("{`n  `"mcpServers`": {`n" + ($entries -join ",`n") + "`n  }`n}`n") @('spec-workflow', 'serena')
    Ok "Antigravity: MCP em .agents\mcp_config.json ($McpCsv) - so neste projeto"
  }
  $agPinned = @(Get-AntigravityGlobalPinned)
  if ($agPinned.Count) {
    Warn 'O config GLOBAL do Antigravity prende MCP a um projeto - vale em TODO projeto que voce abrir:'
    foreach ($l in $agPinned) { Write-Host "    $l" }
    Warn 'Tire essas chaves de la (backup antes). Instalacoes antigas do buildison gravavam no global; esta nao grava mais.'
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
$steps = New-Object System.Collections.Generic.List[string]
if ($doInfra) { $steps.Add("Subir infra:  cd `$HOME\local-infra; docker compose up -d") }
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
