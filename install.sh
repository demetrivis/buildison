#!/usr/bin/env bash
#
# buildison installer — instala a toolbox de agentes (single source -> glue nativo por agente)
#
# Uso:
#   ./install.sh                          # interativo, instala no diretório atual
#   ./install.sh --dir ~/code/meu-projeto # escolhe o destino
#   ./install.sh --agents claude,codex,opencode,antigravity --yes
#   ./install.sh --preset files           # SÓ arquivos (agents/skills/commands) — sem MCP, infra ou Qdrant
#   ./install.sh --preset lite            # arquivos + MCP spec-workflow
#   ./install.sh --preset full            # + serena + memória Qdrant + .claude/settings.json (default)
#   ./install.sh --list                   # presets, MCPs, agents, skills e commands disponíveis
#   ./install.sh --update                 # ATUALIZA repo que já tem buildison (ver abaixo)
#   curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --preset files
#
# Sob medida (partem do preset e sobrescrevem só o que você passar):
#   --mcp <lista|none>    spec-workflow, serena, memory
#   --parts <lista>       agents, commands, skills, settings (.claude/settings.json: permissões + plugins)
#   --skills <lista>      só estas skills      ─┐ default: todos, menos os que dependem de uma peça
#   --subagents <lista>   só estes agents       │ que não foi instalada (ex.: skill agent-memory
#   --commands <lista>    só estes commands    ─┘ só vem com --mcp memory). Pedir pelo nome força.
#   A escolha fica em .buildison na raiz do projeto e é reaproveitada nas próximas execuções.
#
# --update  atualiza SÓ o boilerplate e preserva o que é do projeto:
#             atualiza  AGENTS.md, .claude/, .agents/, .spec-workflow/templates/,
#                       .mcp.json (mantendo a COLLECTION_NAME já configurada)
#             preserva  CLAUDE.md, docs/agent/context.md e docs/agent/decisions.md
#           Faz .bak dos arquivos que mudarem e lista órfãos em .claude/.
#           NÃO use --force pra atualizar: ele apaga context.md e decisions.md.
#
# Agentes suportados: claude, codex, opencode, antigravity
# Flags: --dir <path> --agents <lista> --preset files|lite|full|custom --mcp --parts --skills
#        --subagents --commands --list --infra/--no-infra --serena/--no-serena
#        --memory local|vps --qdrant-url <url> --yes --force --update
#
set -euo pipefail

REPO_URL="https://github.com/demetrivis/buildison.git"

# ---------- helpers ----------
c_reset='\033[0m'; c_bold='\033[1m'; c_grn='\033[32m'; c_ylw='\033[33m'; c_cyn='\033[36m'; c_red='\033[31m'
info() { printf "${c_cyn}›${c_reset} %s\n" "$*"; }
ok()   { printf "${c_grn}✓${c_reset} %s\n" "$*"; }
warn() { printf "${c_ylw}!${c_reset} %s\n" "$*"; }
err()  { printf "${c_red}✗${c_reset} %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }

# read que funciona mesmo via pipe (curl | bash): lê do terminal de controle (/dev/tty),
# não do stdin — que, num pipe, é o próprio script. Sem tty (CI), retorna vazio (default).
HAVE_TTY=0; [ -r /dev/tty ] && HAVE_TTY=1
prompt_read() { if [ "$HAVE_TTY" -eq 1 ]; then read -r "$1" < /dev/tty || true; fi; }

TMP_SRC=""; WORK=""
cleanup() { [ -n "$TMP_SRC" ] && rm -rf "$TMP_SRC"; [ -n "$WORK" ] && rm -rf "$WORK"; return 0; }
trap cleanup EXIT

# listas "a,b,c"
csv_has() { case ",$1," in *",$2,"*) return 0;; esac; return 1; }

# senha aleatória forte (openssl se houver; senão /dev/urandom)
gen_password() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -hex 24
  else LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 40; echo; fi
}

# python que funciona de verdade (no Windows o "python3" pode ser o atalho da Store, que não roda nada)
find_python() {
  local p
  for p in python3 python; do
    if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import sys' >/dev/null 2>&1; then printf '%s' "$p"; return 0; fi
  done
  return 1
}

INFRA_PGPASS=""  # preenchido por setup_local_infra (usado no resumo)
# Monta o stack global ~/local-infra (Postgres + Redis + Qdrant + ngrok + cloudflared)
setup_local_infra() {
  local dir="$HOME/local-infra"
  if [ -d "$dir" ] && [ "$FORCE" -eq 0 ]; then
    warn "local-infra já existe em $dir (pulando). Use --force pra recriar."
    return 0
  fi
  mkdir -p "$dir/postgres-init"
  INFRA_PGPASS="$(gen_password)"
  cat > "$dir/.env" <<EOF
# Gerado pelo buildison installer — credenciais do stack local (dev only)
POSTGRES_PASSWORD=${INFRA_PGPASS}
# Tunnels (opcionais): preencha se for usar
NGROK_AUTHTOKEN=
CLOUDFLARE_TUNNEL_TOKEN=
EOF
  cat > "$dir/postgres-init/01-extensions.sql" <<'SQL'
-- Roda uma vez, quando o volume é criado do zero.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
-- Databases por projeto (além do 'dev' default):
-- CREATE DATABASE projeto_x OWNER dev;
SQL
  # compose: a senha vem do .env via ${POSTGRES_PASSWORD} (heredoc com aspas = sem expansão)
  cat > "$dir/docker-compose.yml" <<'YAML'
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
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./postgres-init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dev -d dev"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    networks: [local-infra]

  redis:
    image: redis:7-alpine
    container_name: local-redis
    restart: unless-stopped
    command: redis-server --appendonly yes --maxmemory 512mb --maxmemory-policy allkeys-lru
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
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
    ports:
      - "6333:6333"
      - "6334:6334"
    volumes:
      - qdrant-data:/qdrant/storage
    healthcheck:
      test: ["CMD-SHELL", "bash -c ':> /dev/tcp/127.0.0.1/6333' || exit 1"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 10s
    networks: [local-infra]

  ngrok:
    image: ngrok/ngrok:latest
    container_name: local-ngrok
    restart: unless-stopped
    environment:
      NGROK_AUTHTOKEN: ${NGROK_AUTHTOKEN}
    command: "http --log=stdout host.docker.internal:8000"
    ports:
      - "4040:4040"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks: [local-infra]
    depends_on: [postgres, redis]

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: local-cloudflared
    restart: unless-stopped
    command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks: [local-infra]

volumes:
  postgres-data: { name: local-postgres-data }
  redis-data:    { name: local-redis-data }
  qdrant-data:   { name: local-qdrant-data }

networks:
  local-infra: { name: local-infra, driver: bridge }
YAML
  ok "local-infra criado em $dir (senha do Postgres gerada aleatoriamente)"
}

# Instala o Serena no host (via uv) — é CLI, não container
setup_serena() {
  if ! command -v uv >/dev/null 2>&1; then
    warn "uv não encontrado — pulei o Serena. Instale uv (https://docs.astral.sh/uv) e rode:"
    warn "  uv tool install -p 3.13 serena-agent && serena init"
    return 0
  fi
  if command -v serena >/dev/null 2>&1 && [ "$FORCE" -eq 0 ]; then
    ok "Serena já instalado ($(command -v serena))"; return 0
  fi
  info "Instalando Serena (uv tool install serena-agent)..."
  if uv tool install -p 3.13 serena-agent >/dev/null 2>&1; then
    serena init >/dev/null 2>&1 || true
    ok "Serena instalado e inicializado"
  else
    warn "Falha ao instalar o Serena — rode manualmente: uv tool install -p 3.13 serena-agent"
  fi
}

# ---------- args ----------
TARGET_DIR=""
AGENTS_CSV=""
ASSUME_YES=0
FORCE=0
UPDATE=0          # atualiza SÓ o boilerplate; preserva o que é do projeto
LIST=0
SETUP_INFRA=""    # "" = perguntar; 1 = sim; 0 = não
SETUP_SERENA=""   # idem
MEMORY_MODE=""    # "" = perguntar (ou ler config per-máquina); "local" | "vps"
QDRANT_URL_OPT="" # URL custom (modo vps); default lê de ~/.buildison/vps.env ou pergunta
# o que instalar — *_SET=1 quando veio de flag (ou do .buildison do projeto)
PRESET="";        PRESET_SET=0; ASK_CUSTOM=0
MCP_CSV="";       MCP_SET=0
PARTS_CSV="";     PARTS_SET=0
SKILLS_CSV="";    SKILLS_SET=0
SUBAGENTS_CSV=""; SUBAGENTS_SET=0
COMMANDS_CSV="";  COMMANDS_SET=0
CODEX_FAILED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)          TARGET_DIR="${2:-}"; shift 2;;
    --agents)       AGENTS_CSV="${2:-}"; shift 2;;
    --preset)       PRESET="${2:-}"; PRESET_SET=1; shift 2;;
    --preset=*)     PRESET="${1#*=}"; PRESET_SET=1; shift;;
    --mcp)          MCP_CSV="${2:-}"; MCP_SET=1; shift 2;;
    --mcp=*)        MCP_CSV="${1#*=}"; MCP_SET=1; shift;;
    --parts)        PARTS_CSV="${2:-}"; PARTS_SET=1; shift 2;;
    --parts=*)      PARTS_CSV="${1#*=}"; PARTS_SET=1; shift;;
    --skills)       SKILLS_CSV="${2:-}"; SKILLS_SET=1; shift 2;;
    --skills=*)     SKILLS_CSV="${1#*=}"; SKILLS_SET=1; shift;;
    --subagents)    SUBAGENTS_CSV="${2:-}"; SUBAGENTS_SET=1; shift 2;;
    --subagents=*)  SUBAGENTS_CSV="${1#*=}"; SUBAGENTS_SET=1; shift;;
    --commands)     COMMANDS_CSV="${2:-}"; COMMANDS_SET=1; shift 2;;
    --commands=*)   COMMANDS_CSV="${1#*=}"; COMMANDS_SET=1; shift;;
    --list)         LIST=1; shift;;
    --infra)        SETUP_INFRA=1; shift;;
    --no-infra)     SETUP_INFRA=0; shift;;
    --serena)       SETUP_SERENA=1; shift;;
    --no-serena)    SETUP_SERENA=0; shift;;
    --memory)       MEMORY_MODE="${2:-}"; shift 2;;
    --memory=*)     MEMORY_MODE="${1#*=}"; shift;;
    --qdrant-url)   QDRANT_URL_OPT="${2:-}"; shift 2;;
    --qdrant-url=*) QDRANT_URL_OPT="${1#*=}"; shift;;
    --yes|-y)       ASSUME_YES=1; shift;;
    --force)        FORCE=1; shift;;
    --update)       UPDATE=1; shift;;
    -h|--help)      sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0;;
    *) die "Argumento desconhecido: $1 (use --help)";;
  esac
done
case "$MEMORY_MODE" in ""|local|vps) ;; *) die "--memory deve ser 'local' ou 'vps' (recebido: $MEMORY_MODE)";; esac
case "$PRESET" in ""|files|lite|full|custom) ;; *) die "--preset deve ser files, lite, full ou custom (recebido: $PRESET)";; esac
[ "$PRESET" = "custom" ] && ASK_CUSTOM=1

# config per-máquina (~/.buildison/vps.env): escolha uma vez, vale pra todos os projetos
BLD_CFG_DIR="$HOME/.buildison"
BLD_CFG="$BLD_CFG_DIR/vps.env"
load_machine_cfg() {
  if [ -f "$BLD_CFG" ]; then
    # shellcheck disable=SC1090
    . "$BLD_CFG"
    [ -z "$MEMORY_MODE"    ] && [ -n "${BUILDISON_MEMORY_MODE:-}" ] && MEMORY_MODE="$BUILDISON_MEMORY_MODE"
    [ -z "$QDRANT_URL_OPT" ] && [ -n "${BUILDISON_QDRANT_URL:-}"  ] && QDRANT_URL_OPT="$BUILDISON_QDRANT_URL"
  fi
  return 0
}
save_machine_cfg() {
  mkdir -p "$BLD_CFG_DIR"
  cat > "$BLD_CFG" <<EOF
# Config per-máquina do buildison — escolha uma vez, vale pra novos projetos desta máquina.
# (Apague esse arquivo pra ser perguntado de novo.)
BUILDISON_MEMORY_MODE=$MEMORY_MODE
BUILDISON_QDRANT_URL=${QDRANT_URL_OPT}
EOF
  ok "Config per-máquina salva em $BLD_CFG"
}
load_machine_cfg

# ---------- localizar a fonte (repo clonado ou clonar em temp p/ curl|bash) ----------
# Marcadores ÚNICOS do repo fonte (install.sh + bin/buildison.mjs) — NÃO usar AGENTS.md/.claude
# porque todo projeto que já usou o buildison tem esses, o que faria o script confundir a pasta
# atual (via curl|bash, $0 vira a CWD) com o próprio repo.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd || true)"
SRC_DIR=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/install.sh" ] && [ -f "$SCRIPT_DIR/bin/buildison.mjs" ]; then
  SRC_DIR="$SCRIPT_DIR"
else
  command -v git >/dev/null 2>&1 || die "git é necessário para baixar o buildison."
  TMP_SRC="$(mktemp -d)"
  info "Baixando buildison para $TMP_SRC ..."
  git clone --depth 1 "$REPO_URL" "$TMP_SRC" >/dev/null 2>&1 || die "Falha ao clonar $REPO_URL"
  SRC_DIR="$TMP_SRC"
fi
WORK="$(mktemp -d)"

# ---------- catálogo (agents / skills / commands da fonte) ----------
item_names() { # part → nomes disponíveis na fonte, separados por espaço
  local i n
  for i in "$SRC_DIR/.claude/$1"/*; do
    [ -e "$i" ] || continue
    n="$(basename "$i")"; printf '%s ' "${n%.md}"
  done
}
# Itens que só fazem sentido com uma peça instalada. Saem sozinhos quando ela falta —
# a menos que você peça o item pelo nome (--skills agent-memory força).
item_dep() {
  case "$1/$2" in
    skills/agent-memory)  echo memory;;
    skills/spec-workflow) echo spec;;
    skills/local-infra)   echo infra;;
    agents/suporte)       echo mcp;;
    *)                    echo "";;
  esac
}

if [ "$LIST" -eq 1 ]; then
  printf "${c_bold}Presets${c_reset} (--preset)\n"
  echo "  files   só arquivos — AGENTS.md, docs/agent/, agents, commands, skills. Sem MCP, sem infra, sem Qdrant."
  echo "  lite    files + MCP spec-workflow (planejamento). Nada pra instalar na máquina."
  echo "  full    lite + serena + memória Qdrant + .claude/settings.json  (default)"
  echo "  custom  pergunta MCPs, partes e quais itens"
  echo ""
  printf "${c_bold}MCPs${c_reset} (--mcp, ou none)\n"
  echo "  spec-workflow  planejamento requirements → design → tasks (npx, nada a instalar)"
  echo "  serena         navegação semântica do código (precisa de uv + serena)"
  echo "  memory         memória vetorial Qdrant (precisa de Qdrant local ou VPS)"
  echo ""
  printf "${c_bold}Partes${c_reset} (--parts): agents commands skills settings\n\n"
  printf "${c_bold}Agents${c_reset} (--subagents):  %s\n" "$(item_names agents)"
  printf "${c_bold}Skills${c_reset} (--skills):     %s\n" "$(item_names skills)"
  printf "${c_bold}Commands${c_reset} (--commands): %s\n" "$(item_names commands)"
  echo ""
  echo "Dependências (saem sozinhas se a peça não for instalada, a menos que você peça pelo nome):"
  echo "  skill agent-memory → memory · skill spec-workflow → spec-workflow · skill local-infra → infra · agent suporte → algum MCP"
  exit 0
fi
ok "Fonte: $SRC_DIR"

# ---------- destino ----------
if [ -z "$TARGET_DIR" ]; then
  if [ "$ASSUME_YES" -eq 1 ]; then TARGET_DIR="$PWD"; else
    ans=""; printf "Diretório do projeto [%s]: " "$PWD"; prompt_read ans
    TARGET_DIR="${ans:-$PWD}"
  fi
fi
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd || die "Diretório inválido: $TARGET_DIR")"
[ "$TARGET_DIR" = "$SRC_DIR" ] && die "O destino não pode ser o próprio repositório buildison. Use --dir."
ok "Destino: $TARGET_DIR"

# ---------- o que já está instalado no projeto (.buildison) ----------
# Um --preset na linha de comando é uma escolha nova: aí o arquivo é ignorado.
PROJ_CFG="$TARGET_DIR/.buildison"
if [ -f "$PROJ_CFG" ] && [ "$PRESET_SET" -eq 0 ]; then
  while IFS='=' read -r k v || [ -n "$k" ]; do
    v="${v%$'\r'}"
    case "$k" in
      BUILDISON_PRESET)    PRESET="$v"; PRESET_SET=1;;
      BUILDISON_MCP)       if [ "$MCP_SET" -eq 0 ];       then MCP_CSV="$v";       MCP_SET=1;       fi;;
      BUILDISON_PARTS)     if [ "$PARTS_SET" -eq 0 ];     then PARTS_CSV="$v";     PARTS_SET=1;     fi;;
      BUILDISON_SKILLS)    if [ "$SKILLS_SET" -eq 0 ];    then SKILLS_CSV="$v";    SKILLS_SET=1;    fi;;
      BUILDISON_SUBAGENTS) if [ "$SUBAGENTS_SET" -eq 0 ]; then SUBAGENTS_CSV="$v"; SUBAGENTS_SET=1; fi;;
      BUILDISON_COMMANDS)  if [ "$COMMANDS_SET" -eq 0 ];  then COMMANDS_CSV="$v";  COMMANDS_SET=1;  fi;;
    esac
  done < "$PROJ_CFG"
  info "Usando a escolha salva em .buildison (preset ${PRESET:-custom}) — passe --preset pra mudar"
fi

# ---------- seleção de agentes ----------
SEL_CLAUDE=0; SEL_CODEX=0; SEL_OPENCODE=0; SEL_ANTIGRAVITY=0
if [ -z "$AGENTS_CSV" ] && [ "$ASSUME_YES" -eq 0 ]; then
  echo ""
  printf "${c_bold}Quais agentes configurar?${c_reset}\n"
  printf "  1) Claude Code\n  2) Codex\n  3) OpenCode/Hermes\n  4) Antigravity (Google)\n  5) Todos\n"
  sel=""; printf "Escolha (ex: 1,2 ou 5): "; prompt_read sel
  case ",${sel}," in *5*) AGENTS_CSV="claude,codex,opencode,antigravity";; esac
  [ -z "$AGENTS_CSV" ] && {
    case ",${sel}," in *,1,*) AGENTS_CSV="${AGENTS_CSV}claude,";; esac
    case ",${sel}," in *,2,*) AGENTS_CSV="${AGENTS_CSV}codex,";; esac
    case ",${sel}," in *,3,*) AGENTS_CSV="${AGENTS_CSV}opencode,";; esac
    case ",${sel}," in *,4,*) AGENTS_CSV="${AGENTS_CSV}antigravity,";; esac
  }
fi
[ -z "$AGENTS_CSV" ] && AGENTS_CSV="claude"
case ",$AGENTS_CSV," in *,claude,*|*claude*) SEL_CLAUDE=1;; esac
case ",$AGENTS_CSV," in *codex*) SEL_CODEX=1;; esac
case ",$AGENTS_CSV," in *opencode*) SEL_OPENCODE=1;; esac
case ",$AGENTS_CSV," in *antigravity*) SEL_ANTIGRAVITY=1;; esac

# ---------- preset: o que instalar ----------
if [ "$PRESET_SET" -eq 0 ] && [ "$MCP_SET" -eq 0 ] && [ "$PARTS_SET" -eq 0 ]; then
  if [ "$ASSUME_YES" -eq 1 ] || [ "$HAVE_TTY" -eq 0 ]; then PRESET="full"; else
    echo ""
    printf "${c_bold}O que instalar?${c_reset}\n"
    printf "  1) Só arquivos — agents, skills, commands e AGENTS.md. Sem MCP, sem infra, sem Qdrant.\n"
    printf "  2) Leve        — arquivos + spec-workflow (planejamento). Nada pra instalar na máquina.\n"
    printf "  3) Completo    — leve + Serena + memória Qdrant + settings.json do Claude\n"
    printf "  4) Sob medida  — escolho os MCPs e quais agents/skills/commands\n"
    pr=""; printf "Escolha [3]: "; prompt_read pr
    case "$pr" in 1) PRESET=files;; 2) PRESET=lite;; 4) PRESET=custom; ASK_CUSTOM=1;; *) PRESET=full;; esac
  fi
fi
[ -z "$PRESET" ] && PRESET="custom"   # veio só --mcp/--parts: parte dos defaults do full

case "$PRESET" in
  files) DEF_MCP="";                            DEF_PARTS="agents,commands,skills";;
  lite)  DEF_MCP="spec-workflow";               DEF_PARTS="agents,commands,skills";;
  *)     DEF_MCP="spec-workflow,serena,memory"; DEF_PARTS="agents,commands,skills,settings";;
esac

if [ "$ASK_CUSTOM" -eq 1 ]; then
  if [ "$HAVE_TTY" -eq 0 ] || [ "$ASSUME_YES" -eq 1 ]; then
    die "--preset custom é interativo. Sem perguntas, use --mcp/--parts/--skills/--subagents/--commands."
  fi
  r=""
  if [ "$MCP_SET" -eq 0 ]; then
    echo ""
    printf "${c_bold}Quais MCPs?${c_reset} (vírgula; enter = nenhum)\n"
    printf "  1) spec-workflow — planejamento (npx, nada a instalar)\n"
    printf "  2) serena        — navegação semântica do código (precisa de uv)\n"
    printf "  3) memory        — memória vetorial Qdrant (precisa de Qdrant local ou VPS)\n> "
    r=""; prompt_read r
    MCP_CSV="$(printf '%s' "$r" | sed 's/1/spec-workflow/g; s/2/serena/g; s/3/memory/g')"; MCP_SET=1
  fi
  if [ "$PARTS_SET" -eq 0 ]; then
    echo ""
    printf "${c_bold}Quais partes do .claude/?${c_reset} (enter = agents,commands,skills)\n"
    printf "  settings = .claude/settings.json (permissões amplas + plugins) — só entra se pedir\n> "
    r=""; prompt_read r
    PARTS_CSV="${r:-agents,commands,skills}"; PARTS_SET=1
  fi
  for part in skills agents commands; do
    case ",$(printf '%s' "$PARTS_CSV" | tr -d ' ')," in *",$part,"*) ;; *) continue;; esac
    echo ""
    printf "${c_bold}Quais %s?${c_reset} (vírgula; enter = todos)\n  %s\n> " "$part" "$(item_names "$part")"
    r=""; prompt_read r
    case "$part" in
      skills)   if [ "$SKILLS_SET" -eq 0 ];    then SKILLS_CSV="$r";    fi;;
      agents)   if [ "$SUBAGENTS_SET" -eq 0 ]; then SUBAGENTS_CSV="$r"; fi;;
      commands) if [ "$COMMANDS_SET" -eq 0 ];  then COMMANDS_CSV="$r";  fi;;
    esac
  done
fi

[ "$MCP_SET" -eq 1 ]   || MCP_CSV="$DEF_MCP"
[ "$PARTS_SET" -eq 1 ] || PARTS_CSV="$DEF_PARTS"

norm_mcp() {
  local out="" x
  for x in $(printf '%s' "$1" | tr ',' ' '); do
    case "$x" in
      spec|spec-workflow|specworkflow)            x=spec-workflow;;
      serena)                                     ;;
      memory|memoria|memória|qdrant|qdrant-memory) x=memory;;
      none|nenhum)                                continue;;
      *) die "--mcp: '$x' desconhecido (use spec-workflow, serena, memory ou none)";;
    esac
    csv_has "$out" "$x" || out="${out:+$out,}$x"
  done
  printf '%s' "$out"
}
norm_parts() {
  local out="" x
  for x in $(printf '%s' "$1" | tr ',' ' '); do
    case "$x" in
      agents|subagents)          x=agents;;
      commands|skills|settings)  ;;
      all|tudo)                  out="agents,commands,skills,settings"; continue;;
      *) die "--parts: '$x' desconhecido (use agents, commands, skills, settings)";;
    esac
    csv_has "$out" "$x" || out="${out:+$out,}$x"
  done
  printf '%s' "$out"
}
norm_items() { printf '%s' "$1" | tr -d ' ' | sed 's/\.md//g; s#/##g; s/,,*/,/g; s/^,//; s/,$//'; }

MCP_CSV="$(norm_mcp "$MCP_CSV")"
PARTS_CSV="$(norm_parts "$PARTS_CSV")"
SKILLS_CSV="$(norm_items "$SKILLS_CSV")"
SUBAGENTS_CSV="$(norm_items "$SUBAGENTS_CSV")"
COMMANDS_CSV="$(norm_items "$COMMANDS_CSV")"

check_names() { # part csv
  local n
  [ -n "$2" ] || return 0
  for n in $(printf '%s' "$2" | tr ',' ' '); do
    if [ ! -e "$SRC_DIR/.claude/$1/$n" ] && [ ! -e "$SRC_DIR/.claude/$1/$n.md" ]; then
      warn "$1: '$n' não existe no buildison (ignorado) — veja --list"
    fi
  done
  return 0
}
check_names skills   "$SKILLS_CSV"
check_names agents   "$SUBAGENTS_CSV"
check_names commands "$COMMANDS_CSV"

HAS_SPEC=0; HAS_SERENA=0; HAS_MEMORY=0
if csv_has "$MCP_CSV" spec-workflow; then HAS_SPEC=1; fi
if csv_has "$MCP_CSV" serena;        then HAS_SERENA=1; fi
if csv_has "$MCP_CSV" memory;        then HAS_MEMORY=1; fi

# ---------- pré-requisitos da máquina (uma vez por máquina, opt-in) ----------
# Só pergunta o que faz sentido pro que foi escolhido: sem memória não tem infra, sem serena não instala serena.
if [ -z "$SETUP_INFRA" ]; then
  if [ "$HAS_MEMORY" -eq 0 ] || [ "$ASSUME_YES" -eq 1 ]; then SETUP_INFRA=0; else
    echo ""
    printf "${c_bold}Montar o local-infra (stack global da máquina)?${c_reset}\n"
    printf "  Um stack Docker único (Postgres + Redis + Qdrant + tunnels) que sobe UMA vez e\n"
    printf "  serve TODOS os seus projetos — o Qdrant guarda a memória dos agentes. Senhas aleatórias.\n"
    r=""; printf "  (pule se já tem, se usa Qdrant na VPS, ou se não usa Docker) [s/N]: "; prompt_read r
    case "$r" in [sSyY]*) SETUP_INFRA=1;; *) SETUP_INFRA=0;; esac
  fi
fi
if [ -z "$SETUP_SERENA" ]; then
  if [ "$HAS_SERENA" -eq 0 ] || [ "$ASSUME_YES" -eq 1 ]; then SETUP_SERENA=0; else
    echo ""
    printf "${c_bold}Instalar o Serena (navegação semântica do código)?${c_reset}\n"
    printf "  CLI no host via uv (não é container). Necessário pro MCP 'serena' conectar.\n"
    r=""; printf "  [s/N]: "; prompt_read r
    case "$r" in [sSyY]*) SETUP_SERENA=1;; *) SETUP_SERENA=0;; esac
  fi
fi

# ---------- modo de memória (local vs VPS) — só se a memória foi escolhida ----------
if [ "$HAS_MEMORY" -eq 1 ]; then
  if [ -z "$MEMORY_MODE" ]; then
    if [ "$ASSUME_YES" -eq 1 ]; then MEMORY_MODE="local"; else
      echo ""
      printf "${c_bold}Onde fica a memória (Qdrant) deste e dos próximos projetos desta máquina?${c_reset}\n"
      printf "  1) Local — http://localhost:6333 (do ~/local-infra). Simples; memória só nesta máquina.\n"
      printf "  2) VPS   — HTTPS público com api-key. Memória segue você entre máquinas.\n"
      printf "  (essa escolha é salva em ~/.buildison/vps.env e vale pra novos projetos.\n"
      printf "   Veja docs/infra/qdrant-vps-template.md no buildison pra montar a VPS.)\n"
      mm=""; printf "Escolha [1]: "; prompt_read mm
      case "$mm" in 2) MEMORY_MODE="vps";; *) MEMORY_MODE="local";; esac
    fi
  fi
  if [ "$MEMORY_MODE" = "vps" ] && [ -z "$QDRANT_URL_OPT" ]; then
    if [ "$ASSUME_YES" -eq 1 ]; then
      die "--memory=vps requer --qdrant-url=<URL> em modo --yes."
    fi
    qurl=""; printf "URL do Qdrant na VPS (ex: https://qdrant.seu-dominio.com): "; prompt_read qurl
    [ -z "$qurl" ] && die "URL vazia. Aborte ou rode de novo informando --qdrant-url."
    QDRANT_URL_OPT="$qurl"
  fi
  [ "$MEMORY_MODE" = "vps" ] && save_machine_cfg
  [ "$MEMORY_MODE" = "local" ] && [ -f "$BLD_CFG" ] && save_machine_cfg
fi
[ -z "$MEMORY_MODE" ] && MEMORY_MODE="local"

# nome da collection do Qdrant derivado do projeto
PROJ_NAME="$(basename "$TARGET_DIR" | tr '[:upper:] -' '[:lower:]__' | tr -cd 'a-z0-9_')"
COLLECTION="agent_${PROJ_NAME:-project_main}"
EMBED="sentence-transformers/all-MiniLM-L6-v2"
if [ "$MEMORY_MODE" = "vps" ]; then QDRANT_URL="$QDRANT_URL_OPT"; else QDRANT_URL="http://localhost:6333"; fi

# Num --update, respeita a collection que já está no .mcp.json: ela pode ter sido
# ajustada à mão e não bater com o nome derivado do diretório (COLLECTION).
if [ "$HAS_MEMORY" -eq 1 ] && [ "$UPDATE" -eq 1 ] && [ -f "$TARGET_DIR/.mcp.json" ]; then
  PY="$(find_python || true)"
  if [ -n "$PY" ]; then
    PREV_COLL="$("$PY" -c "
import json,sys
try:
    print(json.load(open(sys.argv[1]))['mcpServers']['qdrant-memory']['env'].get('COLLECTION_NAME',''))
except Exception: print('')
" "$TARGET_DIR/.mcp.json" 2>/dev/null || true)"
    if [ -n "$PREV_COLL" ] && [ "$PREV_COLL" != "$COLLECTION" ]; then
      warn "mantendo collection existente: $PREV_COLL (derivada seria $COLLECTION)"
      COLLECTION="$PREV_COLL"
    fi
  fi
fi
if [ "$HAS_MEMORY" -eq 1 ]; then info "Memória: $MEMORY_MODE ($QDRANT_URL) · collection ${COLLECTION}"; fi
if [ "$MEMORY_MODE" = "vps" ]; then
  QDRANT_ENV_JSON="{ \"QDRANT_URL\": \"${QDRANT_URL}\", \"QDRANT_API_KEY\": \"\${QDRANT_API_KEY}\", \"COLLECTION_NAME\": \"${COLLECTION}\", \"EMBEDDING_MODEL\": \"${EMBED}\" }"
else
  QDRANT_ENV_JSON="{ \"QDRANT_URL\": \"${QDRANT_URL}\", \"COLLECTION_NAME\": \"${COLLECTION}\", \"EMBEDDING_MODEL\": \"${EMBED}\" }"
fi

# ---------- tags: o que existe neste projeto (filtra AGENTS.md, templates e itens) ----------
TAGS=""
if [ "$HAS_SPEC" -eq 1 ];   then TAGS="$TAGS spec"; fi
if [ "$HAS_SERENA" -eq 1 ]; then TAGS="$TAGS serena"; fi
if [ "$HAS_MEMORY" -eq 1 ]; then TAGS="$TAGS memory"; fi
if [ -n "$MCP_CSV" ];       then TAGS="$TAGS mcp"; fi
if [ "$PRESET" = "full" ] || [ "$SETUP_INFRA" = "1" ] || { [ "$HAS_MEMORY" -eq 1 ] && [ "$MEMORY_MODE" = "local" ]; }; then
  TAGS="$TAGS infra"
fi
has_tag() { case " $TAGS " in *" $1 "*) return 0;; esac; return 1; }

item_selected() { # part name → instala este item?
  local part="$1" name="$2" list="" dep
  csv_has "$PARTS_CSV" "$part" || return 1
  case "$part" in
    skills)   list="$SKILLS_CSV";;
    agents)   list="$SUBAGENTS_CSV";;
    commands) list="$COMMANDS_CSV";;
  esac
  if [ -n "$list" ]; then csv_has "$list" "$name"; return; fi
  dep="$(item_dep "$part" "$name")"
  [ -z "$dep" ] || has_tag "$dep"
}

# Copia um arquivo com blocos <!-- bld:if TAG --> … <!-- bld:end --> resolvidos pelas TAGS
# (aceita !TAG e aninhamento). Os marcadores somem; linhas em branco repetidas viram uma.
render_tagged() { # src dst
  awk -v tags=" $TAGS " '
    { sub(/\r$/, "") }
    /^[[:space:]]*<!--[[:space:]]*bld:if[[:space:]]+!?[a-z0-9-]+[[:space:]]*-->[[:space:]]*$/ {
      t = $0
      sub(/^[[:space:]]*<!--[[:space:]]*bld:if[[:space:]]+/, "", t); sub(/[[:space:]]*-->.*$/, "", t)
      neg = (substr(t, 1, 1) == "!"); if (neg) t = substr(t, 2)
      on = (index(tags, " " t " ") > 0); if (neg) on = !on
      st[++d] = on ? 0 : 1; off += st[d]; next
    }
    /^[[:space:]]*<!--[[:space:]]*bld:end[[:space:]]*-->[[:space:]]*$/ { if (d > 0) { off -= st[d]; d-- }; next }
    off > 0 { next }
    /^[[:space:]]*$/ { if (!nb) { nb = 1; if (printed) print "" }; next }
    { nb = 0; printed = 1; print }
  ' "$1" > "$2"
}

info "Instalando: preset $PRESET · MCP: ${MCP_CSV:-nenhum} · partes: $PARTS_CSV"

# ---------- copiar core compartilhado ----------
# Duas naturezas de arquivo, e elas se comportam DIFERENTE num update:
#
#   boilerplate  (AGENTS.md)  — permanente, vem do buildison, não muda por projeto.
#                               Num --update TEM que ser atualizado, senão o repo antigo
#                               nunca recebe regra nova (era o bug: copy_keep o congelava).
#   do projeto   (context.md, decisions.md) — conhecimento que o agente acumulou.
#                               NUNCA sobrescrever num --update; só --force faz isso.
copy_keep() { # src dst  (não sobrescreve se já existe, salvo --force)
  local s="$1" d="$2"
  mkdir -p "$(dirname "$d")"
  if [ -e "$d" ] && [ "$FORCE" -eq 0 ]; then warn "mantido (já existe): ${d#$TARGET_DIR/}"; else cp -f "$s" "$d"; ok "${d#$TARGET_DIR/}"; fi
}
copy_boiler() { # src dst  (boilerplate: atualiza no --update e no --force; faz .bak)
  local s="$1" d="$2"
  mkdir -p "$(dirname "$d")"
  if [ -e "$d" ] && [ "$UPDATE" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
    warn "mantido (já existe): ${d#$TARGET_DIR/}"
  else
    [ -e "$d" ] && ! cmp -s "$s" "$d" && cp "$d" "$d.bak" 2>/dev/null || true
    cp -f "$s" "$d"; ok "${d#$TARGET_DIR/}"
  fi
}
info "Instalando core compartilhado..."
render_tagged "$SRC_DIR/AGENTS.md" "$WORK/AGENTS.md"
copy_boiler "$WORK/AGENTS.md" "$TARGET_DIR/AGENTS.md"
# Copia dos TEMPLATES, não do context.md/decisions.md do próprio buildison — aqueles
# descrevem o buildison e vazariam pra todo projeto herdado. (Fallback pros arquivos
# antigos mantém compatibilidade com clones anteriores à separação.)
CTX_SRC="$SRC_DIR/docs/agent/templates/context.md";   [ -f "$CTX_SRC" ] || CTX_SRC="$SRC_DIR/docs/agent/context.md"
DEC_SRC="$SRC_DIR/docs/agent/templates/decisions.md"; [ -f "$DEC_SRC" ] || DEC_SRC="$SRC_DIR/docs/agent/decisions.md"
render_tagged "$CTX_SRC" "$WORK/context.md"
render_tagged "$DEC_SRC" "$WORK/decisions.md"
copy_keep "$WORK/context.md"   "$TARGET_DIR/docs/agent/context.md"
copy_keep "$WORK/decisions.md" "$TARGET_DIR/docs/agent/decisions.md"
if [ "$HAS_SPEC" -eq 1 ] && [ -d "$SRC_DIR/.spec-workflow/templates" ]; then
  mkdir -p "$TARGET_DIR/.spec-workflow"
  cp -Rf "$SRC_DIR/.spec-workflow/templates" "$TARGET_DIR/.spec-workflow/"
  ok ".spec-workflow/templates/"
fi

# entradas de JSON separadas por vírgula (.mcp.json / opencode.json)
ENTRIES=""
add_entry() { if [ -n "$ENTRIES" ]; then ENTRIES="$ENTRIES,"$'\n'; fi; ENTRIES="$ENTRIES$1"; }

# ---------- Claude Code ----------
if [ "$SEL_CLAUDE" -eq 1 ]; then
  info "Configurando Claude Code..."
  # Item a item (não a pasta inteira) pra respeitar preset/filtros. O destino de cada cp é
  # a pasta PAI (.claude/skills/), então skill que já existe é mesclada, não aninhada.
  for part in agents commands skills; do
    [ -d "$SRC_DIR/.claude/$part" ] || continue
    n=0
    for item in "$SRC_DIR/.claude/$part"/*; do
      [ -e "$item" ] || continue
      name="$(basename "$item")"; name="${name%.md}"
      if item_selected "$part" "$name"; then
        mkdir -p "$TARGET_DIR/.claude/$part"
        cp -Rf "$item" "$TARGET_DIR/.claude/$part/"
        n=$((n+1))
      fi
    done
    if [ "$n" -gt 0 ]; then ok ".claude/$part/ ($n)"; fi
  done
  if csv_has "$PARTS_CSV" settings && [ -f "$SRC_DIR/.claude/settings.json" ]; then
    copy_boiler "$SRC_DIR/.claude/settings.json" "$TARGET_DIR/.claude/settings.json"
  fi
  # cp -Rf MESCLA (não sincroniza): agent/skill renomeado ou removido do buildison fica
  # órfão aqui pra sempre, e o Claude Code carrega os dois. Não deletamos — o .claude/ do
  # projeto pode ter customização sua (settings.local.json, agents próprios, worktrees) —
  # mas listamos pra você decidir.
  if [ "$UPDATE" -eq 1 ]; then
    ORPHANS=""
    for sub in agents commands skills; do
      [ -d "$TARGET_DIR/.claude/$sub" ] || continue
      for f in "$TARGET_DIR/.claude/$sub"/*; do
        [ -e "$f" ] || continue
        case "$f" in *.bak) continue;; esac
        [ -e "$SRC_DIR/.claude/$sub/$(basename "$f")" ] || ORPHANS="$ORPHANS  .claude/$sub/$(basename "$f")\n"
      done
    done
    if [ -n "$ORPHANS" ]; then
      warn "Arquivos em .claude/ que não existem mais no buildison (seus, ou resquício de versão antiga):"
      printf "$ORPHANS"
      warn "Revise e remova os que forem resquício."
    fi
  fi
  # ⚠️ O CLAUDE.md tem natureza DUPLA: os @imports são boilerplate, mas o resto é
  # documentação do projeto que o time escreveu. Regravar cego destrói isso — já
  # aconteceu: dois repos perderam 485 e 325 linhas de doc (acesso a VPS, banco,
  # arquitetura) numa execução do installer. Se já existe, NÃO tocamos.
  if [ -e "$TARGET_DIR/CLAUDE.md" ] && [ "$FORCE" -eq 0 ]; then
    warn "mantido (já existe): CLAUDE.md — confira se tem os @imports de AGENTS.md e docs/agent/context.md"
  else
    # template único (bash e PowerShell): as seções de Serena/memória saem pelas tags
    render_tagged "$SRC_DIR/docs/agent/templates/claude-md.md" "$TARGET_DIR/CLAUDE.md"
    ok "CLAUDE.md"
  fi
  if [ -n "$MCP_CSV" ]; then
    ENTRIES=""
    if [ "$HAS_SPEC" -eq 1 ]; then
      add_entry '    "spec-workflow": { "command": "npx", "args": ["-y", "@pimzino/spec-workflow-mcp@latest", "."] }'
    fi
    if [ "$HAS_SERENA" -eq 1 ]; then
      add_entry '    "serena": { "command": "serena", "args": ["start-mcp-server", "--context", "claude-code", "--project", ".", "--enable-web-dashboard", "false", "--open-web-dashboard", "false", "--enable-gui-log-window", "false"] }'
    fi
    if [ "$HAS_MEMORY" -eq 1 ]; then
      add_entry "    \"qdrant-memory\": {
      \"command\": \"uvx\",
      \"args\": [\"mcp-server-qdrant\"],
      \"env\": ${QDRANT_ENV_JSON}
    }"
    fi
    printf '{\n  "mcpServers": {\n%s\n  }\n}\n' "$ENTRIES" > "$TARGET_DIR/.mcp.json"
    ok ".mcp.json (${MCP_CSV})"
  else
    ok "Claude: sem MCP neste preset — .mcp.json não gerado"
  fi
fi

# ---------- Codex (AGENTS.md já copiado; MCP no ~/.codex/config.toml) ----------
# O config.toml é GLOBAL e os nomes de tabela ([mcp_servers.serena] etc) são fixos. Em TOML
# uma tabela declarada duas vezes invalida o arquivo INTEIRO, e aí o Codex descarta a config
# toda (inclusive [windows] — o ChatGPT/Codex Desktop entra em loop ou abre várias instâncias).
# Por isso: bloco único (os legados por-projeto são removidos), nunca redeclara tabela que já
# existe fora do bloco, e valida o resultado ANTES de gravar.
codex_table() {
  case "$1" in
    spec-workflow)
      printf '[mcp_servers.spec-workflow]\ncommand = "npx"\nargs = ["-y", "@pimzino/spec-workflow-mcp@latest", "."]\n';;
    serena)
      printf '[mcp_servers.serena]\ncommand = "serena"\nargs = ["start-mcp-server", "--context", "codex", "--project-from-cwd", "--enable-web-dashboard", "false", "--open-web-dashboard", "false", "--enable-gui-log-window", "false"]\n';;
    qdrant-memory)
      printf '[mcp_servers.qdrant-memory]\ncommand = "uvx"\nargs = ["mcp-server-qdrant"]\n'
      if [ "$MEMORY_MODE" = "vps" ]; then
        printf 'env = { QDRANT_URL = "%s", QDRANT_API_KEY = "${QDRANT_API_KEY}", COLLECTION_NAME = "%s", EMBEDDING_MODEL = "%s" }\n' "$QDRANT_URL" "$COLLECTION" "$EMBED"
      else
        printf 'env = { QDRANT_URL = "%s", COLLECTION_NAME = "%s", EMBEDDING_MODEL = "%s" }\n' "$QDRANT_URL" "$COLLECTION" "$EMBED"
      fi;;
  esac
}
# tabelas ([a.b], não [[array]]) declaradas mais de uma vez
toml_dup_tables() {
  grep -E '^[[:space:]]*\[[^],[][^],[]*\][[:space:]]*(#.*)?$' "$1" 2>/dev/null \
    | sed -E 's/#.*$//; s/[][[:space:]"]//g' | sort | uniq -d || true
}
# 0 = válido · 1 = inválido · 2 = sem python 3.11+ (só deu pra checar duplicatas)
toml_is_valid() {
  local f="$1" py
  if [ -n "$(toml_dup_tables "$f")" ]; then return 1; fi
  py="$(find_python)" || return 2
  "$py" -c 'import tomllib' >/dev/null 2>&1 || return 2
  if "$py" -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$f" >/dev/null 2>&1; then return 0; fi
  return 1
}
# tabela como estava no bloco anterior do buildison (inclui subtabelas [mcp_servers.X.env])
codex_old_names() { # nomes de [mcp_servers.X] achados no bloco antigo (só tabela raiz, sem sub-tabela)
  [ -s "$WORK/codex-oldblock.toml" ] || return 0
  awk '
    /^[[:space:]]*\[[[:space:]]*mcp_servers[[:space:]]*\./ {
      line = $0; sub(/[[:space:]]*#.*$/, "", line); gsub(/[[:space:]"]/, "", line)
      if (line !~ /^\[mcp_servers\.[^.]+\]$/) next
      n = line; sub(/^\[mcp_servers\./, "", n); sub(/\]$/, "", n)
      if (!(n in seen)) { seen[n] = 1; print n }
    }
  ' "$WORK/codex-oldblock.toml"
}

codex_old_table() {
  [ -s "$WORK/codex-oldblock.toml" ] || return 0
  awk -v h="[mcp_servers.$1]" '
    /^[[:space:]]*\[/ {
      cur = $0; sub(/[[:space:]]*#.*$/, "", cur); gsub(/[[:space:]"]/, "", cur)
      on = (cur == h || index(cur, substr(h, 1, length(h) - 1) ".") == 1)
    }
    on && !/^[[:space:]]*$/ && !/^[[:space:]]*#/ { print }
  ' "$WORK/codex-oldblock.toml"
}
codex_write_mcp() {
  local cfg="$HOME/.codex/config.toml" tmp="$WORK/codex-config.toml" old="$WORK/codex-oldblock.toml"
  local want="" keep="" pending="" name rc bak="" dups first=1
  mkdir -p "$HOME/.codex"
  : > "$old"
  if [ -f "$cfg" ]; then
    # tira QUALQUER bloco do buildison (o atual e os legados "# >>> buildison (projeto) >>>"),
    # guardando o conteúdo dele à parte
    awk -v old="$old" '
      { sub(/\r$/, "") }
      /^[[:space:]]*# >>> buildison.*>>>/ { skip = 1; next }
      /^[[:space:]]*# <<< buildison.*<<</ { skip = 0; next }
      skip { print > old; next }
      /^[[:space:]]*$/ { nb++; next }
      { while (nb > 0) { print ""; nb-- }; print }
    ' "$cfg" > "$tmp"
  else
    : > "$tmp"
  fi
  if [ "$HAS_SPEC" -eq 1 ];   then want="$want spec-workflow"; fi
  if [ "$HAS_SERENA" -eq 1 ]; then want="$want serena"; fi
  if [ "$HAS_MEMORY" -eq 1 ]; then want="$want qdrant-memory"; fi
  # O config é de TODOS os projetos: o que um install anterior pôs no bloco e este não pediu
  # continua lá (um projeto "lite" não desliga a memória que outro projeto usa).
  # Varre o bloco INTEIRO, não só o trio do buildison: quem edita o ~/.codex/config.toml à mão
  # acaba pondo MCP próprio dentro dos marcadores, e regravar cego apagava isso em silêncio.
  for name in $(codex_old_names); do
    case " $want " in *" $name "*) continue;; esac
    keep="$keep $name"
  done
  for name in $want $keep; do
    if grep -qE "^[[:space:]]*\[[[:space:]]*mcp_servers[[:space:]]*\.[[:space:]]*\"?${name}\"?[[:space:]]*\][[:space:]]*(#.*)?$" "$tmp"; then
      warn "Codex: [mcp_servers.$name] já existe fora do bloco do buildison — mantido como está (não duplico)"
    else
      pending="$pending $name"
    fi
  done
  if [ -n "$keep" ]; then info "Codex: mantido do bloco anterior (outro projeto, ou MCP seu):$keep"; fi
  if [ -n "$pending" ]; then
    {
      if [ -s "$tmp" ]; then echo ""; fi
      echo "# >>> buildison >>>"
      echo "# Bloco único e global, regravado a cada install. Tabela que já existir fora dele NÃO é"
      echo "# repetida aqui (tabela duplicada = TOML inválido = o Codex descarta a config inteira)."
      for name in $pending; do
        if [ "$first" -eq 0 ]; then echo ""; fi
        first=0
        case " $want " in
          *" $name "*) codex_table "$name";;
          *)           codex_old_table "$name";;
        esac
      done
      echo "# <<< buildison <<<"
    } >> "$tmp"
  fi
  rc=0; toml_is_valid "$tmp" || rc=$?
  if [ "$rc" -eq 1 ]; then
    err "Codex: o ~/.codex/config.toml ficaria INVÁLIDO — não gravei nada (seu arquivo continua como estava)."
    dups="$(toml_dup_tables "$tmp")"
    if [ -n "$dups" ]; then
      err "Tabelas declaradas mais de uma vez (apague as repetidas e rode de novo):"
      printf '    [%s]\n' $dups >&2
    fi
    CODEX_FAILED=1
    return 0
  fi
  if [ "$rc" -eq 2 ]; then warn "Codex: sem python 3.11+ (tomllib) — validei só tabelas duplicadas"; fi
  if [ -f "$cfg" ] && cmp -s "$tmp" "$cfg"; then ok "Codex: ~/.codex/config.toml já estava em dia"; return 0; fi
  if [ -f "$cfg" ]; then bak="$cfg.bak.$(date +%s 2>/dev/null || echo bak)"; cp "$cfg" "$bak"; fi
  cp -f "$tmp" "$cfg"
  ok "Codex: MCP em ~/.codex/config.toml (bloco único, validado)${bak:+ · backup ${bak##*/}}"
}
if [ "$SEL_CODEX" -eq 1 ]; then
  info "Configurando Codex..."
  if [ -n "$MCP_CSV" ]; then
    codex_write_mcp
  else
    ok "Codex: sem MCP neste preset — ~/.codex/config.toml não foi tocado"
  fi
  ok "Codex: AGENTS.md (lido nativamente da raiz do projeto)"
fi

# ---------- OpenCode/Hermes (AGENTS.md já copiado; MCP em opencode.json) ----------
if [ "$SEL_OPENCODE" -eq 1 ]; then
  info "Configurando OpenCode/Hermes..."
  if [ -z "$MCP_CSV" ]; then
    ok "OpenCode: sem MCP neste preset — opencode.json não gerado"
  else
    OC_CFG="$TARGET_DIR/opencode.json"
    ENTRIES=""
    if [ "$HAS_SPEC" -eq 1 ]; then
      add_entry '    "spec-workflow": { "type": "local", "command": ["npx", "-y", "@pimzino/spec-workflow-mcp@latest", "."], "enabled": true }'
    fi
    if [ "$HAS_SERENA" -eq 1 ]; then
      add_entry '    "serena": { "type": "local", "command": ["serena", "start-mcp-server", "--context", "ide", "--project-from-cwd", "--enable-web-dashboard", "false", "--open-web-dashboard", "false", "--enable-gui-log-window", "false"], "enabled": true }'
    fi
    if [ "$HAS_MEMORY" -eq 1 ]; then
      add_entry "    \"qdrant-memory\": {
      \"type\": \"local\",
      \"command\": [\"uvx\", \"mcp-server-qdrant\"],
      \"environment\": ${QDRANT_ENV_JSON},
      \"enabled\": true
    }"
    fi
    OC_JSON="$(printf '{\n  "$schema": "https://opencode.ai/config.json",\n  "mcp": {\n%s\n  }\n}' "$ENTRIES")"
    if [ -e "$OC_CFG" ] && [ "$FORCE" -eq 0 ]; then
      printf '%s\n' "$OC_JSON" > "$TARGET_DIR/opencode.buildison.json"
      warn "opencode.json já existe — gravei opencode.buildison.json; faça merge do bloco \"mcp\" manualmente."
    else
      printf '%s\n' "$OC_JSON" > "$OC_CFG"; ok "opencode.json"
    fi
  fi
  ok "OpenCode: AGENTS.md (lido nativamente da raiz do projeto)"
fi

# ---------- Antigravity (Google) — AGENTS.md nativo + .agents/ + MCP global ----------
# O Antigravity lê AGENTS.md da raiz (já copiado no core). Aqui espelhamos skills/workflows
# em .agents/ (com os mesmos filtros do .claude/) e registramos a toolbox MCP no config GLOBAL
# do Antigravity (não é por-projeto): ~/.gemini/config/mcp_config.json (fallback
# ~/.gemini/antigravity/mcp_config.json). Global e sem CWD confiável → caminhos ABSOLUTOS.
if [ "$SEL_ANTIGRAVITY" -eq 1 ]; then
  info "Configurando Antigravity..."
  if [ -d "$SRC_DIR/.agents" ]; then
    n=0; w=0
    for f in "$SRC_DIR/.agents/skills"/*; do
      [ -e "$f" ] || continue
      name="$(basename "$f")"; name="${name%.md}"
      if item_selected skills "$name"; then
        mkdir -p "$TARGET_DIR/.agents/skills"; cp -Rf "$f" "$TARGET_DIR/.agents/skills/"; n=$((n+1))
      fi
    done
    for f in "$SRC_DIR/.agents/workflows"/*; do
      [ -e "$f" ] || continue
      name="$(basename "$f")"; name="${name%.md}"
      part=""
      if [ -e "$SRC_DIR/.claude/commands/$name.md" ]; then part=commands
      elif [ -e "$SRC_DIR/.claude/agents/$name.md" ]; then part=agents; fi
      if [ -z "$part" ] || item_selected "$part" "$name"; then
        mkdir -p "$TARGET_DIR/.agents/workflows"; cp -Rf "$f" "$TARGET_DIR/.agents/workflows/"; w=$((w+1))
      fi
    done
    ok ".agents/ ($n skills, $w workflows)"
  else
    warn ".agents/ não existe na fonte — rode 'node scripts/gen-antigravity.mjs' no repo buildison."
  fi
  if [ -z "$MCP_CSV" ]; then
    ok "Antigravity: sem MCP neste preset — config global do Gemini não foi tocado"
  elif ! PY="$(find_python)"; then
    warn "Antigravity: python não encontrado — MCP não registrado. Adicione à mão em ~/.gemini/.../mcp_config.json"
  else
    # localiza o mcp_config.json: primeiro candidato existente vence, senão o default
    AG_CFG=""
    for c in "$HOME/.gemini/config/mcp_config.json" "$HOME/.gemini/antigravity/mcp_config.json"; do
      [ -f "$c" ] && { AG_CFG="$c"; break; }
    done
    [ -z "$AG_CFG" ] && AG_CFG="$HOME/.gemini/config/mcp_config.json"
    mkdir -p "$(dirname "$AG_CFG")"
    [ -f "$AG_CFG" ] && cp "$AG_CFG" "$AG_CFG.bak.$(date +%s 2>/dev/null || echo bak)" 2>/dev/null || true
    # merge: mexe SÓ nas chaves escolhidas, preserva o resto do config global
    "$PY" - "$AG_CFG" "$TARGET_DIR" "$QDRANT_URL" "$COLLECTION" "$EMBED" "$MEMORY_MODE" "$MCP_CSV" <<'PY'
import json, os, sys
path, proj, qurl, coll, embed, mode, wanted = sys.argv[1:8]
wanted = wanted.split(",")
try:
    d = json.load(open(path))
    if not isinstance(d, dict): d = {}
except Exception:
    d = {}
servers = d.setdefault("mcpServers", {})
if "spec-workflow" in wanted:
    servers["spec-workflow"] = {"command": "npx", "args": ["-y", "@pimzino/spec-workflow-mcp@latest", proj]}
if "serena" in wanted:
    servers["serena"] = {"command": "serena", "args": ["start-mcp-server", "--context", "ide-assistant", "--project", proj, "--enable-web-dashboard", "false", "--open-web-dashboard", "false", "--enable-gui-log-window", "false"]}
if "memory" in wanted:
    env = {"QDRANT_URL": qurl}
    if mode == "vps":
        env["QDRANT_API_KEY"] = "${QDRANT_API_KEY}"
    env["COLLECTION_NAME"] = coll
    env["EMBEDDING_MODEL"] = embed
    servers["qdrant-memory"] = {"command": "uvx", "args": ["mcp-server-qdrant"], "env": env}
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(d, f, indent=2); f.write("\n")
PY
    ok "Antigravity: MCP em $AG_CFG (${MCP_CSV})"
  fi
  ok "Antigravity: AGENTS.md (lido nativamente da raiz)"
fi

# ---------- registra a escolha no projeto ----------
cat > "$PROJ_CFG" <<EOF
# buildison — o que está instalado neste projeto. As próximas execuções (e o --update) releem
# este arquivo. Pra mudar: rode o instalador com outro --preset, ou edite aqui.
BUILDISON_PRESET=$PRESET
BUILDISON_MCP=$MCP_CSV
BUILDISON_PARTS=$PARTS_CSV
BUILDISON_SKILLS=$SKILLS_CSV
BUILDISON_SUBAGENTS=$SUBAGENTS_CSV
BUILDISON_COMMANDS=$COMMANDS_CSV
EOF
ok ".buildison"

# ---------- pré-requisitos da máquina (execução) ----------
[ "$SETUP_INFRA" = "1" ]  && { echo ""; info "Montando local-infra..."; setup_local_infra; }
[ "$SETUP_SERENA" = "1" ] && { echo ""; info "Configurando Serena..."; setup_serena; }

# ---------- resumo ----------
echo ""
ok "Instalação concluída em $TARGET_DIR (preset $PRESET · MCP: ${MCP_CSV:-nenhum})"
if [ "$CODEX_FAILED" -eq 1 ]; then
  warn "Codex NÃO foi configurado: conserte as tabelas repetidas no ~/.codex/config.toml e rode de novo."
fi

if [ -n "$INFRA_PGPASS" ]; then
  echo ""
  printf "${c_bold}local-infra criado — guarde a credencial:${c_reset}\n"
  echo "  Postgres user: dev"
  echo "  Postgres senha: ${INFRA_PGPASS}"
  echo "  (salva em ~/local-infra/.env · connection: postgresql://dev:${INFRA_PGPASS}@localhost:5432/<db>)"
fi

if [ "$HAS_MEMORY" -eq 1 ] && [ "$MEMORY_MODE" = "vps" ]; then
  echo ""
  printf "${c_bold}Memória: VPS (${QDRANT_URL})${c_reset}\n"
  echo "  O .mcp.json gerado usa \${QDRANT_API_KEY} (expandida do AMBIENTE do shell que abre o claude)."
  echo "  Antes de rodar o claude, exporte a key UMA vez:"
  echo "    export QDRANT_API_KEY=<sua-api-key>      # por sessão"
  echo "    echo 'export QDRANT_API_KEY=...' >> ~/.zshrc   # persistente"
  echo "  Doc: docs/infra/qdrant-vps-template.md (no buildison)"
fi

echo ""
printf "${c_bold}Próximos passos:${c_reset}\n"
STEP=1
step() { echo "  $STEP. $*"; STEP=$((STEP+1)); }
if [ "$HAS_MEMORY" -eq 1 ]; then
  if [ "$MEMORY_MODE" = "local" ]; then
    if [ "$SETUP_INFRA" = "1" ]; then step "Subir a infra:  cd ~/local-infra && docker compose up -d"
    else step "Infra (se ainda não tem):  rode de novo com --infra, ou suba seu ~/local-infra"; fi
  else
    step "Garanta que a VPS Qdrant está no ar (https) e que QDRANT_API_KEY está exportada"
  fi
fi
if [ "$HAS_SERENA" -eq 1 ] && [ "$SETUP_SERENA" != "1" ]; then
  step "Serena:  uv tool install -p 3.13 serena-agent && serena init"
fi
if [ "$SEL_CLAUDE" -eq 1 ]; then
  if [ -n "$MCP_CSV" ]; then step "Claude:      abra o projeto e rode /mcp para aprovar os servidores"
  else step "Claude:      abra o projeto — agents, skills e commands já estão em .claude/"; fi
fi
if [ "$SEL_CODEX" -eq 1 ]; then
  if [ -n "$MCP_CSV" ]; then step "Codex:       abra o projeto (lê AGENTS.md); MCP em ~/.codex/config.toml"
  else step "Codex:       abra o projeto (lê AGENTS.md)"; fi
fi
if [ "$SEL_OPENCODE" -eq 1 ]; then step "OpenCode:    abra o projeto (lê AGENTS.md${MCP_CSV:+ + opencode.json})"; fi
if [ "$SEL_ANTIGRAVITY" -eq 1 ]; then step "Antigravity: abra o projeto (lê AGENTS.md + .agents/)"; fi
step "Preencha docs/agent/context.md com o stack real do projeto."
