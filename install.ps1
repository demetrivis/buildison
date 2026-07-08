#requires -version 5
<#
buildison installer (Windows / PowerShell) — instala a toolbox de agentes (single source -> glue por agente)

Uso:
  irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1 | iex      # interativo
  .\install.ps1 -Dir . -Agents claude,codex,opencode,antigravity -Infra -Serena          # via clone, com flags

Agentes: claude, codex, opencode, antigravity
Flags: -Dir <path> -Agents <lista> -Infra/-NoInfra -Serena/-NoSerena -Yes -Force
#>
[CmdletBinding()]
param(
  [string]$Dir = "",
  [string]$Agents = "",
  [switch]$Infra,
  [switch]$NoInfra,
  [switch]$Serena,
  [switch]$NoSerena,
  [ValidateSet('','local','vps')] [string]$Memory = "",
  [string]$QdrantUrl = "",
  [switch]$Yes,
  [switch]$Force,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'
$RepoUrl = 'https://github.com/demetrivis/buildison.git'
$Embed   = 'sentence-transformers/all-MiniLM-L6-v2'

function Info($m){ Write-Host "> $m"  -ForegroundColor Cyan }
function Ok($m)  { Write-Host "OK $m" -ForegroundColor Green }
function Warn($m){ Write-Host "! $m"  -ForegroundColor Yellow }
function Die($m) { Write-Host "x $m"  -ForegroundColor Red; exit 1 }

if ($Help) { Get-Help $PSCommandPath -Detailed; exit 0 }

function New-RandomPassword {
  $bytes = New-Object 'System.Byte[]' 24
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  -join ($bytes | ForEach-Object { $_.ToString('x2') })
}

# ---------- localizar a fonte (repo clonado, ou clonar em temp p/ irm|iex) ----------
# Marcadores ÚNICOS do repo fonte (install.sh + bin/buildison.mjs) — não usar AGENTS.md/.claude,
# que todo projeto instalado tem.
$src = $PSScriptRoot
if (-not $src -or -not (Test-Path (Join-Path $src 'install.sh')) -or -not (Test-Path (Join-Path $src 'bin\buildison.mjs'))) {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die 'git é necessário para baixar o buildison.' }
  $src = Join-Path $env:TEMP ('buildison-' + [guid]::NewGuid().ToString('N'))
  Info "Baixando buildison para $src ..."
  git clone --depth 1 $RepoUrl $src 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { Die "Falha ao clonar $RepoUrl" }
}
Ok "Fonte: $src"

# ---------- destino ----------
if (-not $Dir) {
  if ($Yes) { $Dir = (Get-Location).Path }
  else { $ans = Read-Host "Diretório do projeto [$((Get-Location).Path)]"; $Dir = if ($ans) { $ans } else { (Get-Location).Path } }
}
if (-not (Test-Path $Dir)) { Die "Diretório inválido: $Dir" }
$Target = (Resolve-Path $Dir).Path
if ($Target -eq (Resolve-Path $src).Path) { Die 'O destino não pode ser o próprio repositório buildison. Use -Dir.' }
Ok "Destino: $Target"

# ---------- seleção de agentes ----------
if (-not $Agents -and -not $Yes) {
  Write-Host "Quais agentes configurar?" -ForegroundColor White
  Write-Host "  1) Claude Code`n  2) Codex`n  3) OpenCode/Hermes`n  4) Antigravity (Google)`n  5) Todos"
  $sel = Read-Host "Escolha (ex: 1,2 ou 5)"
  if ($sel -match '5') { $Agents = 'claude,codex,opencode,antigravity' }
  else {
    $a = @()
    if ($sel -match '1') { $a += 'claude' }
    if ($sel -match '2') { $a += 'codex' }
    if ($sel -match '3') { $a += 'opencode' }
    if ($sel -match '4') { $a += 'antigravity' }
    $Agents = ($a -join ',')
  }
}
if (-not $Agents) { $Agents = 'claude' }
$selClaude      = $Agents -match 'claude'
$selCodex       = $Agents -match 'codex'
$selOpencode    = $Agents -match 'opencode'
$selAntigravity = $Agents -match 'antigravity'

# pré-requisitos da máquina (opt-in)
$doInfra  = if ($Infra) { $true } elseif ($NoInfra) { $false } elseif ($Yes) { $false } else {
  Write-Host "`nMontar o local-infra (stack global da máquina)?" -ForegroundColor White
  Write-Host "  Stack Docker único (Postgres + Redis + Qdrant + tunnels) que sobe UMA vez e serve TODOS"
  Write-Host "  os seus projetos. O Qdrant guarda a memória dos agentes. Senhas aleatórias."
  (Read-Host "  [s/N]") -match '^[sSyY]'
}
$doSerena = if ($Serena) { $true } elseif ($NoSerena) { $false } elseif ($Yes) { $false } else {
  Write-Host "`nInstalar o Serena (navegação semântica do código)?" -ForegroundColor White
  Write-Host "  CLI no host via uv (não é container). Necessário pro MCP 'serena' conectar."
  (Read-Host "  [s/N]") -match '^[sSyY]'
}

# ---------- modo de memória (local vs VPS) — config per-máquina em ~/.buildison/vps.env ----------
$bldCfgDir = Join-Path $env:USERPROFILE '.buildison'
$bldCfg    = Join-Path $bldCfgDir 'vps.env'
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
    Write-Host "`nOnde fica a memória (Qdrant) deste e dos próximos projetos desta máquina?" -ForegroundColor White
    Write-Host "  1) Local - http://localhost:6333 (do ~/local-infra). Simples; memória só nesta máquina."
    Write-Host "  2) VPS   - HTTPS público com api-key. Memória segue você entre máquinas."
    Write-Host "  (essa escolha é salva em $bldCfg e vale pra novos projetos.)"
    $mm = Read-Host "Escolha [1]"
    $Memory = if ($mm -eq '2') { 'vps' } else { 'local' }
  }
}
if ($Memory -eq 'vps' -and -not $QdrantUrl) {
  if ($Yes) { Die '-Memory vps requer -QdrantUrl <URL> em modo -Yes.' }
  $QdrantUrl = Read-Host "URL do Qdrant na VPS (ex: https://qdrant.seu-dominio.com)"
  if (-not $QdrantUrl) { Die 'URL vazia.' }
}
# persiste a escolha
New-Item -ItemType Directory -Force -Path $bldCfgDir | Out-Null
@"
# Config per-maquina do buildison - apague o arquivo pra ser perguntado de novo.
BUILDISON_MEMORY_MODE=$Memory
BUILDISON_QDRANT_URL=$QdrantUrl
"@ | Set-Content -Path $bldCfg -Encoding UTF8
Ok "Config per-maquina: $bldCfg"

$qUrl = if ($Memory -eq 'vps') { $QdrantUrl } else { 'http://localhost:6333' }
Info "Memoria: $Memory ($qUrl)"

# collection do Qdrant derivada do nome do projeto
$projName = (Split-Path $Target -Leaf).ToLower() -replace '[^a-z0-9_]','_'
if (-not $projName) { $projName = 'project_main' }
$collection = "agent_$projName"
Info "Collection Qdrant: $collection"

function Copy-Keep($s, $d) {
  $dd = Split-Path $d -Parent
  if ($dd -and -not (Test-Path $dd)) { New-Item -ItemType Directory -Force -Path $dd | Out-Null }
  if ((Test-Path $d) -and -not $Force) { Warn "mantido (já existe): $d" }
  else { Copy-Item -Force $s $d; Ok (Split-Path $d -Leaf) }
}

Info "Instalando core compartilhado..."
Copy-Keep (Join-Path $src 'AGENTS.md')               (Join-Path $Target 'AGENTS.md')
Copy-Keep (Join-Path $src 'docs\agent\context.md')   (Join-Path $Target 'docs\agent\context.md')
Copy-Keep (Join-Path $src 'docs\agent\decisions.md') (Join-Path $Target 'docs\agent\decisions.md')
if (Test-Path (Join-Path $src '.spec-workflow\templates')) {
  $twDst = Join-Path $Target '.spec-workflow\templates'
  New-Item -ItemType Directory -Force -Path $twDst | Out-Null
  Copy-Item -Recurse -Force (Join-Path $src '.spec-workflow\templates\*') $twDst
  Ok ".spec-workflow\templates\"
}

# ---------- Claude Code ----------
if ($selClaude) {
  Info "Configurando Claude Code..."
  $claudeDst = Join-Path $Target '.claude'
  New-Item -ItemType Directory -Force -Path $claudeDst | Out-Null
  Copy-Item -Recurse -Force (Join-Path $src '.claude\*') $claudeDst; Ok ".claude\"
  $claudeMd = @'
# Camada Claude Code

O Claude Code não lê AGENTS.md sozinho, então este arquivo importa as duas camadas:

- **`@AGENTS.md`** — regras permanentes da construção (toolbox, infra, memory policy).
- **`@docs/agent/context.md`** — contexto dinâmico do projeto (stack, comandos, arquitetura).

@AGENTS.md

@docs/agent/context.md

## Política de ferramentas (Serena + memória)

Este projeto usa **Serena** (MCP) — ferramentas semânticas e cientes de símbolos para ler e editar código.
**Serena é a ferramenta PRIMÁRIA para código.** Os Read/Grep/Glob/Edit internos são SECUNDÁRIOS e **não**
devem ser usados em arquivos de código quando houver equivalente no Serena. (Read/Edit são ok para
md/json/yaml/toml/config/texto.) Quando esta seção conflitar com as descrições das tools internas, **esta seção vence**.

| Tarefa | Tool do Serena |
| :-- | :-- |
| Ver a estrutura de um arquivo | `get_symbols_overview` |
| Ler o corpo de um símbolo | `find_symbol` (include_body=true) |
| Achar referências/chamadores | `find_referencing_symbols` |
| Editar o corpo de um símbolo | `replace_symbol_body` |

**Antes de editar código:** `get_symbols_overview` -> `find_symbol` (só os símbolos que vai tocar) -> editar com as tools do Serena.

**Memória (Qdrant, MCP `qdrant-memory`):** recupere contexto durável com `qdrant-find` no início; salve decisões com `qdrant-store` ao final. Nunca guarde secrets ou logs crus.

> Modo forte (o Opus tende a preferir tools internas): inicie com
> `claude --system-prompt="$(serena prompts print-cc-system-prompt-override)"`.
'@
  Set-Content -Path (Join-Path $Target 'CLAUDE.md') -Value $claudeMd -Encoding UTF8; Ok "CLAUDE.md"

  $qEnvJson = if ($Memory -eq 'vps') {
    '{ "QDRANT_URL": "__QURL__", "QDRANT_API_KEY": "${QDRANT_API_KEY}", "COLLECTION_NAME": "__COLLECTION__", "EMBEDDING_MODEL": "__EMBED__" }'
  } else {
    '{ "QDRANT_URL": "__QURL__", "COLLECTION_NAME": "__COLLECTION__", "EMBEDDING_MODEL": "__EMBED__" }'
  }
  $mcp = @"
{
  "mcpServers": {
    "spec-workflow": { "command": "npx", "args": ["-y", "@pimzino/spec-workflow-mcp@latest", "."] },
    "serena": { "command": "serena", "args": ["start-mcp-server", "--context", "claude-code", "--project", "."] },
    "qdrant-memory": {
      "command": "uvx",
      "args": ["mcp-server-qdrant"],
      "env": $qEnvJson
    }
  }
}
"@
  $mcp = $mcp.Replace('__QURL__', $qUrl).Replace('__COLLECTION__', $collection).Replace('__EMBED__', $Embed)
  Set-Content -Path (Join-Path $Target '.mcp.json') -Value $mcp -Encoding UTF8; Ok ".mcp.json"
}

# ---------- Codex (AGENTS.md já copiado; MCP no ~/.codex/config.toml) ----------
if ($selCodex) {
  Info "Configurando Codex..."
  $codexCfg = Join-Path $env:USERPROFILE '.codex\config.toml'
  New-Item -ItemType Directory -Force -Path (Split-Path $codexCfg -Parent) | Out-Null
  $markBegin = "# >>> buildison ($projName) >>>"
  if ((Test-Path $codexCfg) -and (Select-String -SimpleMatch -Quiet -Path $codexCfg -Pattern $markBegin)) {
    Warn "Codex: bloco já existe em $codexCfg (pulando). Use -Force pra regravar."
  } else {
    $block = @"

$markBegin
[mcp_servers.spec-workflow]
command = "npx"
args = ["-y", "@pimzino/spec-workflow-mcp@latest", "."]

[mcp_servers.serena]
command = "serena"
args = ["start-mcp-server", "--context", "codex", "--project-from-cwd"]

[mcp_servers.qdrant-memory]
command = "uvx"
args = ["mcp-server-qdrant"]
$(if ($Memory -eq 'vps') { "env = { QDRANT_URL = `"$qUrl`", QDRANT_API_KEY = `"`${QDRANT_API_KEY}`", COLLECTION_NAME = `"$collection`", EMBEDDING_MODEL = `"$Embed`" }" } else { "env = { QDRANT_URL = `"$qUrl`", COLLECTION_NAME = `"$collection`", EMBEDDING_MODEL = `"$Embed`" }" })
# <<< buildison ($projName) <<<
"@
    Add-Content -Path $codexCfg -Value $block
    Ok "Codex: MCP adicionado em ~/.codex/config.toml"
  }
  Ok "Codex: AGENTS.md (lido nativamente da raiz do projeto)"
}

# ---------- OpenCode/Hermes ----------
if ($selOpencode) {
  Info "Configurando OpenCode/Hermes..."
  $ocCfg = Join-Path $Target 'opencode.json'
  $ocQEnv = if ($Memory -eq 'vps') {
    '{ "QDRANT_URL": "__QURL__", "QDRANT_API_KEY": "${QDRANT_API_KEY}", "COLLECTION_NAME": "__COLLECTION__", "EMBEDDING_MODEL": "__EMBED__" }'
  } else {
    '{ "QDRANT_URL": "__QURL__", "COLLECTION_NAME": "__COLLECTION__", "EMBEDDING_MODEL": "__EMBED__" }'
  }
  $oc = @"
{
  "`$schema": "https://opencode.ai/config.json",
  "mcp": {
    "spec-workflow": { "type": "local", "command": ["npx", "-y", "@pimzino/spec-workflow-mcp@latest", "."], "enabled": true },
    "serena": { "type": "local", "command": ["serena", "start-mcp-server", "--context", "ide", "--project-from-cwd"], "enabled": true },
    "qdrant-memory": {
      "type": "local",
      "command": ["uvx", "mcp-server-qdrant"],
      "environment": $ocQEnv,
      "enabled": true
    }
  }
}
"@
  $oc = $oc.Replace('__QURL__', $qUrl).Replace('__COLLECTION__', $collection).Replace('__EMBED__', $Embed)
  if ((Test-Path $ocCfg) -and -not $Force) {
    Set-Content -Path (Join-Path $Target 'opencode.buildison.json') -Value $oc -Encoding UTF8
    Warn "opencode.json já existe — gravei opencode.buildison.json; faça merge do bloco mcp manualmente."
  } else { Set-Content -Path $ocCfg -Value $oc -Encoding UTF8; Ok "opencode.json" }
  Ok "OpenCode: AGENTS.md (lido nativamente da raiz do projeto)"
}

# ---------- Antigravity (Google) — AGENTS.md nativo + .agents/ + MCP global ----------
# Config GLOBAL (nao por-projeto): usa caminho ABSOLUTO do projeto + a collection deste projeto.
# Windows: ~/.gemini/antigravity/mcp_config.json  (fallback ~/.gemini/config/mcp_config.json).
if ($selAntigravity) {
  Info "Configurando Antigravity..."
  $agentsSrc = Join-Path $src '.agents'
  if (Test-Path $agentsSrc) {
    $agentsDst = Join-Path $Target '.agents'
    New-Item -ItemType Directory -Force -Path $agentsDst | Out-Null
    Copy-Item -Recurse -Force (Join-Path $agentsSrc '*') $agentsDst
    Ok ".agents\ (roster + skills)"
  } else {
    Warn ".agents\ nao existe na fonte — rode 'node scripts/gen-antigravity.mjs' no repo buildison."
  }
  # localiza o mcp_config.json: primeiro candidato existente vence, senao o default (Windows: antigravity\)
  $agCands = @(
    (Join-Path $env:USERPROFILE '.gemini\antigravity\mcp_config.json'),
    (Join-Path $env:USERPROFILE '.gemini\config\mcp_config.json')
  )
  $agCfg = $agCands | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $agCfg) { $agCfg = $agCands[0] }
  New-Item -ItemType Directory -Force -Path (Split-Path $agCfg -Parent) | Out-Null
  if (Test-Path $agCfg) {
    $ts = [int][double]::Parse((Get-Date -UFormat %s)); Copy-Item $agCfg "$agCfg.bak.$ts" -Force
    $agObj = Get-Content $agCfg -Raw | ConvertFrom-Json
  } else { $agObj = [pscustomobject]@{} }
  if (-not $agObj.mcpServers) { $agObj | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) }
  $agEnv = [ordered]@{ QDRANT_URL = $qUrl }
  if ($Memory -eq 'vps') { $agEnv['QDRANT_API_KEY'] = '${QDRANT_API_KEY}' }
  $agEnv['COLLECTION_NAME'] = $collection
  $agEnv['EMBEDDING_MODEL'] = $Embed
  $agServers = [ordered]@{
    'spec-workflow' = [ordered]@{ command = 'npx';    args = @('-y', '@pimzino/spec-workflow-mcp@latest', $Target) }
    'serena'        = [ordered]@{ command = 'serena'; args = @('start-mcp-server', '--context', 'ide-assistant', '--project', $Target) }
    'qdrant-memory' = [ordered]@{ command = 'uvx';    args = @('mcp-server-qdrant'); env = $agEnv }
  }
  foreach ($k in $agServers.Keys) {
    $agObj.mcpServers | Add-Member -NotePropertyName $k -NotePropertyValue ([pscustomobject]$agServers[$k]) -Force
  }
  $agObj | ConvertTo-Json -Depth 16 | Set-Content -Path $agCfg -Encoding UTF8
  Ok "Antigravity: MCP em $agCfg (spec-workflow/serena/qdrant-memory)"
  Ok "Antigravity: AGENTS.md (lido nativamente da raiz) + .agents\"
}

# ---------- local-infra (opt-in) ----------
$infraPass = ""
if ($doInfra) {
  Info "Montando local-infra..."
  $infraDir = Join-Path $env:USERPROFILE 'local-infra'
  if ((Test-Path $infraDir) -and -not $Force) {
    Warn "local-infra já existe em $infraDir (pulando). Use -Force pra recriar."
  } else {
    New-Item -ItemType Directory -Force -Path (Join-Path $infraDir 'postgres-init') | Out-Null
    $infraPass = New-RandomPassword
    Set-Content -Path (Join-Path $infraDir '.env') -Encoding UTF8 -Value @"
# Gerado pelo buildison installer (dev only)
POSTGRES_PASSWORD=$infraPass
NGROK_AUTHTOKEN=
CLOUDFLARE_TUNNEL_TOKEN=
"@
    Set-Content -Path (Join-Path $infraDir 'postgres-init\01-extensions.sql') -Encoding UTF8 -Value @'
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
-- CREATE DATABASE projeto_x OWNER dev;
'@
    Set-Content -Path (Join-Path $infraDir 'docker-compose.yml') -Encoding UTF8 -Value @'
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
    Ok "local-infra criado em $infraDir (senha do Postgres aleatória)"
  }
}

# ---------- Serena (opt-in) ----------
if ($doSerena) {
  Info "Configurando Serena..."
  if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    Warn "uv não encontrado — instale (winget install astral-sh.uv) e rode: uv tool install -p 3.13 serena-agent; serena init"
  } elseif ((Get-Command serena -ErrorAction SilentlyContinue) -and -not $Force) {
    Ok "Serena já instalado"
  } else {
    uv tool install -p 3.13 serena-agent; serena init 2>$null
    Ok "Serena instalado"
  }
}

# ---------- resumo ----------
Write-Host ""
Ok "Instalação concluída em $Target"
if ($infraPass) {
  Write-Host "`nlocal-infra criado — guarde a credencial:" -ForegroundColor White
  Write-Host "  Postgres user: dev"
  Write-Host "  Postgres senha: $infraPass"
  Write-Host "  (em ~/local-infra/.env · conn: postgresql://dev:$infraPass@localhost:5432/<db>)"
}
if ($Memory -eq 'vps') {
  Write-Host "`nMemoria: VPS ($qUrl)" -ForegroundColor White
  Write-Host "  O .mcp.json usa `${QDRANT_API_KEY} (expandida do AMBIENTE do shell que abre o claude)."
  Write-Host "  Exporte a key UMA vez antes de rodar:"
  Write-Host "    `$env:QDRANT_API_KEY = '<sua-api-key>'     # por sessao (PowerShell)"
  Write-Host "    [Environment]::SetEnvironmentVariable('QDRANT_API_KEY','<sua-api-key>','User')  # persistente"
  Write-Host "  Doc: docs/infra/qdrant-vps-template.md (no buildison)"
}
Write-Host "`nPróximos passos:" -ForegroundColor White
if ($Memory -eq 'local') {
  if ($doInfra) { Write-Host "  1. Subir infra:  cd `$HOME\local-infra; docker compose up -d" }
  else          { Write-Host "  1. Infra (se for usar): rode de novo com -Infra" }
} else {
  Write-Host "  1. Garanta que a VPS Qdrant esta no ar (HTTPS) e QDRANT_API_KEY exportada"
}
if (-not $doSerena) { Write-Host "  2. Serena (se for usar): uv tool install -p 3.13 serena-agent; serena init" }
if ($selClaude)      { Write-Host "  3. Claude:      abra o projeto e rode /mcp pra aprovar os servidores" }
if ($selCodex)       { Write-Host "  3. Codex:       abra o projeto (lê AGENTS.md); MCP em ~/.codex/config.toml" }
if ($selOpencode)    { Write-Host "  3. OpenCode:    abra o projeto (lê AGENTS.md + opencode.json)" }
if ($selAntigravity) { Write-Host "  3. Antigravity: abra o projeto (lê AGENTS.md + .agents\); MCP global em ~/.gemini (Settings > Customizations > Open MCP Config)" }
Write-Host "  4. Preencha docs\agent\context.md com o stack real do projeto."
