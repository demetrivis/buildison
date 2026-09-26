#!/usr/bin/env bash
#
# buildison installer — instala a toolbox de agentes (single source -> glue nativo por agente)
#
# Uso:
#   ./install.sh                          # interativo, instala no diretório atual
#   ./install.sh --dir ~/code/meu-projeto # escolhe o destino
#   ./install.sh --agents claude,codex,opencode,antigravity --yes
#   ./install.sh --preset files           # SÓ arquivos (agents/skills/commands) — sem MCP e sem infra
#   ./install.sh --preset lite            # arquivos + MCP spec-workflow
#   ./install.sh --preset full            # + serena + .claude/settings.json (default)
#   ./install.sh --preset context         # SÓ o contexto do projeto (AGENTS.md, CLAUDE.md, docs/agent/, MCP):
#                                         # agents, commands e skills vêm do --global, sem duplicar
#   ./install.sh --list                   # presets, MCPs, agents, skills e commands disponíveis
#   ./install.sh --update                 # ATUALIZA repo que já tem buildison (ver abaixo)
#   ./install.sh --global                 # instala no GLOBAL (~/.claude, ~/.agents/skills) — ver abaixo
#   curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --preset files
#
# Sob medida (partem do preset e sobrescrevem só o que você passar):
#   --mcp <lista|none>    spec-workflow, serena, chrome-devtools (sempre com --isolated)
#   --parts <lista>       agents, commands, skills, settings (.claude/settings.json: permissões + plugins)
#   --skills <lista>      só estas skills      ─┐ default: todos, menos os que dependem de uma peça
#   --subagents <lista>   só estes agents       │ que não foi instalada (ex.: skill spec-workflow
#   --commands <lista>    só estes commands    ─┘ só vem com --mcp spec-workflow). Pedir pelo nome força.
#   A escolha fica em .buildison na raiz do projeto e é reaproveitada nas próximas execuções.
#
# --update  atualiza SÓ o boilerplate e preserva o que é do projeto:
#             atualiza  AGENTS.md, .claude/, .agents/, .spec-workflow/templates/,
#                       .mcp.json
#             preserva  CLAUDE.md, docs/agent/context.md e docs/agent/decisions.md
#           Faz .bak dos arquivos que mudarem e lista órfãos em .claude/.
#           NÃO use --force pra atualizar: ele apaga context.md e decisions.md.
#
# --global  instala agents, commands e skills pra TODOS os projetos da máquina, em vez de um:
#             Claude Code → ~/.claude/{agents,commands,skills}   Codex → ~/.agents/skills
#             Antigravity → ~/.gemini/config/{skills,agents} (+ ~/.gemini/antigravity-cli/skills, se o agy existir)
#           Duas versões: --preset files (sem spec-workflow, default) ou --preset lite (com: skill
#           + MCP spec-workflow no escopo user do Claude e no ~/.codex/config.toml).
#           AGENTS.md, CLAUDE.md e docs/agent/ ficam de fora — descrevem UM projeto.
#           Rodar de novo atualiza (relê ~/.buildison/global.env). Item que o buildison não pôs lá
#           é seu e não é sobrescrito; item que ele pôs e saiu da seleção vai pra ~/.buildison/removidos-*.
#   --orca / --no-orca    contexto pra quem usa o Orca (onorca.dev): regras de worktree no AGENTS.md,
#           .worktreeinclude pros arquivos do buildison que ficam fora do git, e checagem das skills
#           do Orca (que o próprio Orca instala — o buildison não copia). Fica salvo em .buildison.
#   --plugin-skills <lista|none>  (só com --global) leva pro Codex as skills de plugins do Claude Code
#           instalados NESTA máquina (ex.: eng-arq). O Codex não roda plugin; o Claude segue usando o
#           plugin. O conteúdo vem do seu disco, nunca do repo buildison.
#
# Agentes suportados: claude, codex, opencode, antigravity. Padrão: claude,codex,antigravity
# (no --global: claude, codex e antigravity)
# Flags: --dir <path> --agents <lista> --preset files|lite|full|context|custom --mcp --parts --skills
#        --subagents --commands --list --infra/--no-infra --serena/--no-serena
#        --yes --force --update --global --plugin-skills --orca/--no-orca
#
# Memória vetorial (Qdrant) NÃO é mais instalada aqui: virou a skill 'qdrant-setup'
# (+ command /qdrant). Peça ao agente "configura a memória" depois de instalar.
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
GLOBAL=0          # instala em ~/.claude e ~/.agents/skills em vez de num projeto
ORCA=""           # "" = pergunta (se o Orca estiver instalado) ou relê o salvo; 1 = com; 0 = sem
PLUGIN_SKILLS_CSV=""; PLUGIN_SKILLS_SET=0   # --global: skills de plugins do Claude que vão pro Codex
LIST=0
SETUP_INFRA=""    # "" = perguntar; 1 = sim; 0 = não
SETUP_SERENA=""   # idem
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
    --memory|--memory=*|--qdrant-url|--qdrant-url=*)
      die "--memory/--qdrant-url saíram do instalador. A memória Qdrant virou a skill 'qdrant-setup' (command /qdrant): instale normalmente e depois peça ao agente pra configurar.";;
    --yes|-y)       ASSUME_YES=1; shift;;
    --force)        FORCE=1; shift;;
    --update)       UPDATE=1; shift;;
    --global)       GLOBAL=1; shift;;
    --orca)         ORCA=1; shift;;
    --no-orca)      ORCA=0; shift;;
    --plugin-skills)   PLUGIN_SKILLS_CSV="${2:-}"; PLUGIN_SKILLS_SET=1; shift 2;;
    --plugin-skills=*) PLUGIN_SKILLS_CSV="${1#*=}"; PLUGIN_SKILLS_SET=1; shift;;
    -h|--help)      sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0;;
    *) die "Argumento desconhecido: $1 (use --help)";;
  esac
done
case "$PRESET" in ""|files|lite|full|context|custom) ;; *) die "--preset deve ser files, lite, full, context ou custom (recebido: $PRESET)";; esac
[ "$PRESET" = "custom" ] && ASK_CUSTOM=1

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
    skills/spec-workflow) echo spec;;
    skills/local-infra)   echo infra;;
    agents/suporte)       echo mcp;;
    *)                    echo "";;
  esac
}

if [ "$LIST" -eq 1 ]; then
  printf "${c_bold}Presets${c_reset} (--preset)\n"
  echo "  files   só arquivos — AGENTS.md, docs/agent/, agents, commands, skills. Sem MCP e sem infra."
  echo "  lite    files + MCP spec-workflow (planejamento). Nada pra instalar na máquina."
  echo "  full    lite + serena + .claude/settings.json  (default)"
  echo "  context só o contexto do projeto (AGENTS.md, CLAUDE.md, docs/agent/, MCP) — agents/skills vêm do --global"
  echo "  custom  pergunta MCPs, partes e quais itens"
  echo ""
  printf "${c_bold}MCPs${c_reset} (--mcp, ou none)\n"
  echo "  spec-workflow  planejamento requirements → design → tasks (npx, nada a instalar)"
  echo "  serena         navegação semântica do código (precisa de uv + serena)"
  echo "  chrome-devtools  browser pro agente (npx; sempre --isolated: um Chrome por sessão)"
  echo ""
  printf "${c_bold}Partes${c_reset} (--parts): agents commands skills settings\n\n"
  printf "${c_bold}Agents${c_reset} (--subagents):  %s\n" "$(item_names agents)"
  printf "${c_bold}Skills${c_reset} (--skills):     %s\n" "$(item_names skills)"
  printf "${c_bold}Commands${c_reset} (--commands): %s\n" "$(item_names commands)"
  echo ""
  echo "Dependências (saem sozinhas se a peça não for instalada, a menos que você peça pelo nome):"
  echo "  skill spec-workflow → spec-workflow · skill local-infra → infra · agent suporte → algum MCP"
  exit 0
fi
ok "Fonte: $SRC_DIR"

# ---------- destino ----------
GLOBAL_DIR="$HOME/.buildison"
GLOBAL_CFG="$GLOBAL_DIR/global.env"       # a escolha do --global (preset, filtros, agentes)
GLOBAL_MAN="$GLOBAL_DIR/global.manifest"  # o que o --global pôs no disco — só isso ele mexe depois
if [ "$GLOBAL" -eq 1 ]; then
  [ -n "$TARGET_DIR" ] && die "--global não combina com --dir: ele instala em ~/.claude (e ~/.agents/skills no Codex)."
  ok "Destino: global — ~/.claude (Claude Code) · ~/.agents/skills (Codex) · ~/.gemini (Antigravity)"
  CFG_FILE="$GLOBAL_CFG"
else
  if [ -z "$TARGET_DIR" ]; then
    if [ "$ASSUME_YES" -eq 1 ]; then TARGET_DIR="$PWD"; else
      ans=""; printf "Diretório do projeto [%s]: " "$PWD"; prompt_read ans
      TARGET_DIR="${ans:-$PWD}"
    fi
  fi
  TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd || die "Diretório inválido: $TARGET_DIR")"
  [ "$TARGET_DIR" = "$SRC_DIR" ] && die "O destino não pode ser o próprio repositório buildison. Use --dir."
  ok "Destino: $TARGET_DIR"
  PROJ_CFG="$TARGET_DIR/.buildison"
  CFG_FILE="$PROJ_CFG"
fi

# ---------- o que já está instalado (.buildison do projeto, ou ~/.buildison/global.env) ----------
# Um --preset na linha de comando é uma escolha nova: aí o arquivo é ignorado.
if [ -f "$CFG_FILE" ] && [ "$PRESET_SET" -eq 0 ]; then
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
  done < "$CFG_FILE"
  info "Usando a escolha salva em ${CFG_FILE/#$HOME/~} (preset ${PRESET:-custom}) — passe --preset pra mudar"
fi
# Os agentes ficam salvos (no .buildison do projeto e no global.env) e valem mesmo quando você troca
# de --preset. Sem isso, um --update sem --agents cairia no padrão e poria agente onde não havia — ou,
# no global, tiraria as skills de um agente que estava lá.
if [ -z "$AGENTS_CSV" ] && [ -f "$CFG_FILE" ]; then
  AGENTS_CSV="$(sed -n 's/^BUILDISON_AGENTS=//p' "$CFG_FILE" | tr -d '\r')"
  # .buildison de versão antiga não guardava os agentes: deduz do que já está instalado, em vez de
  # impor o padrão novo (o trio) num projeto que não tinha Codex nem Antigravity.
  if [ -z "$AGENTS_CSV" ] && [ "$GLOBAL" -eq 0 ]; then
    if [ -d "$TARGET_DIR/.claude" ]; then AGENTS_CSV="claude"; fi
    if grep -rqs "por gen-antigravity.mjs" "$TARGET_DIR/.agents"; then AGENTS_CSV="${AGENTS_CSV:+$AGENTS_CSV,}antigravity"; fi
    if [ -f "$TARGET_DIR/opencode.json" ]; then AGENTS_CSV="${AGENTS_CSV:+$AGENTS_CSV,}opencode"; fi
    if [ -n "$AGENTS_CSV" ]; then info "Agentes deduzidos do que já está instalado: $AGENTS_CSV (passe --agents pra mudar)"; fi
  fi
fi
# idem pras skills de plugin: são escolha sua, não da versão
if [ "$PLUGIN_SKILLS_SET" -eq 1 ] && [ "$GLOBAL" -eq 0 ]; then
  die "--plugin-skills só existe com --global (leva skill de plugin do Claude pro ~/.agents/skills do Codex)."
fi
if [ "$GLOBAL" -eq 1 ] && [ "$PLUGIN_SKILLS_SET" -eq 0 ] && [ -f "$GLOBAL_CFG" ]; then
  PLUGIN_SKILLS_CSV="$(sed -n 's/^BUILDISON_PLUGIN_SKILLS=//p' "$GLOBAL_CFG" | tr -d '\r')"
fi
case ",$PLUGIN_SKILLS_CSV," in *,none,*) PLUGIN_SKILLS_CSV="";; esac
if [ -z "$ORCA" ] && [ -f "$CFG_FILE" ]; then ORCA="$(sed -n 's/^BUILDISON_ORCA=//p' "$CFG_FILE" | tr -d '\r')"; fi
PLUGIN_SKILLS_CSV="$(printf '%s' "$PLUGIN_SKILLS_CSV" | tr -d ' ')"

# ---------- seleção de agentes ----------
SEL_CLAUDE=0; SEL_CODEX=0; SEL_OPENCODE=0; SEL_ANTIGRAVITY=0
if [ -z "$AGENTS_CSV" ] && [ "$ASSUME_YES" -eq 0 ]; then
  echo ""
  printf "${c_bold}Quais agentes configurar?${c_reset}\n"
  printf "  1) Claude Code\n  2) Codex\n  3) OpenCode/Hermes\n  4) Antigravity (Google)\n  5) Todos\n"
  sel=""; printf "Escolha [enter = 1,2,4 — Claude Code, Codex e Antigravity]: "; prompt_read sel
  case ",${sel}," in *5*) AGENTS_CSV="claude,codex,opencode,antigravity";; esac
  [ -z "$AGENTS_CSV" ] && {
    case ",${sel}," in *,1,*) AGENTS_CSV="${AGENTS_CSV}claude,";; esac
    case ",${sel}," in *,2,*) AGENTS_CSV="${AGENTS_CSV}codex,";; esac
    case ",${sel}," in *,3,*) AGENTS_CSV="${AGENTS_CSV}opencode,";; esac
    case ",${sel}," in *,4,*) AGENTS_CSV="${AGENTS_CSV}antigravity,";; esac
  }
fi
# padrão: o trio Claude Code + Codex + Antigravity
[ -z "$AGENTS_CSV" ] && AGENTS_CSV="claude,codex,antigravity"
case ",$AGENTS_CSV," in *,claude,*|*claude*) SEL_CLAUDE=1;; esac
case ",$AGENTS_CSV," in *codex*) SEL_CODEX=1;; esac
case ",$AGENTS_CSV," in *opencode*) SEL_OPENCODE=1;; esac
case ",$AGENTS_CSV," in *antigravity*) SEL_ANTIGRAVITY=1;; esac
if [ "$GLOBAL" -eq 1 ]; then
  [ "$SEL_OPENCODE" -eq 1 ] && warn "--global: OpenCode ainda não tem instalação global — ignorado"
  SEL_OPENCODE=0
  [ "$SEL_CLAUDE" -eq 0 ] && [ "$SEL_CODEX" -eq 0 ] && [ "$SEL_ANTIGRAVITY" -eq 0 ] && \
    die "--global funciona com --agents claude, codex e/ou antigravity."
fi
# o que fica salvo (projeto e global): a escolha, não o que acabou pulado por outro motivo
AGENTS_SAVED=""
for a in claude codex opencode antigravity; do
  case "$a" in claude) v=$SEL_CLAUDE;; codex) v=$SEL_CODEX;; opencode) v=$SEL_OPENCODE;; *) v=$SEL_ANTIGRAVITY;; esac
  if [ "$v" -eq 1 ]; then AGENTS_SAVED="${AGENTS_SAVED:+$AGENTS_SAVED,}$a"; fi
done

# ---------- preset: o que instalar ----------
# No --global só existem duas versões: sem e com spec-workflow. Serena, settings.json, CLAUDE.md e
# docs/agent/ são por projeto por natureza (o Serena precisa do --project; o settings.json daria
# permissões amplas em todo projeto da máquina).
if [ "$GLOBAL" -eq 1 ]; then
  if [ "$PRESET_SET" -eq 0 ] && [ "$MCP_SET" -eq 0 ] && [ "$PARTS_SET" -eq 0 ]; then
    if [ "$ASSUME_YES" -eq 1 ] || [ "$HAVE_TTY" -eq 0 ]; then PRESET="files"; else
      echo ""
      printf "${c_bold}Qual versão instalar no global?${c_reset}\n"
      printf "  1) Sem spec-workflow — agents, commands e skills. Só arquivos.\n"
      printf "  2) Com spec-workflow — o mesmo + skill e MCP spec-workflow, valendo em todo projeto.\n"
      pr=""; printf "Escolha [1]: "; prompt_read pr
      case "$pr" in 2) PRESET=lite;; *) PRESET=files;; esac
    fi
    PRESET_SET=1
  fi
  [ -z "$PRESET" ] && PRESET="files"
  case "$PRESET" in
    files|lite) ;;
    *) die "--global tem duas versões: --preset files (sem spec-workflow) ou --preset lite (com). Serena e settings.json são por projeto.";;
  esac
fi
if [ "$PRESET_SET" -eq 0 ] && [ "$MCP_SET" -eq 0 ] && [ "$PARTS_SET" -eq 0 ]; then
  if [ "$ASSUME_YES" -eq 1 ] || [ "$HAVE_TTY" -eq 0 ]; then PRESET="full"; else
    echo ""
    printf "${c_bold}O que instalar?${c_reset}\n"
    printf "  1) Só arquivos — agents, skills, commands e AGENTS.md. Sem MCP e sem infra.\n"
    printf "  2) Leve        — arquivos + spec-workflow (planejamento). Nada pra instalar na máquina.\n"
    printf "  3) Completo    — leve + Serena + settings.json do Claude\n"
    printf "  4) Sob medida  — escolho os MCPs e quais agents/skills/commands\n"
    printf "  5) Só contexto — AGENTS.md, CLAUDE.md e docs/agent/; agents e skills vêm do --global\n"
    pr=""; printf "Escolha [3]: "; prompt_read pr
    case "$pr" in 1) PRESET=files;; 2) PRESET=lite;; 4) PRESET=custom; ASK_CUSTOM=1;; 5) PRESET=context;; *) PRESET=full;; esac
  fi
fi
[ -z "$PRESET" ] && PRESET="custom"   # veio só --mcp/--parts: parte dos defaults do full

case "$PRESET" in
  files) DEF_MCP="";                            DEF_PARTS="agents,commands,skills";;
  # só o que é do projeto: agents/commands/skills ficam com o --global (instalar aqui também duplicaria)
  context) DEF_MCP="";                          DEF_PARTS="";;
  lite)  DEF_MCP="spec-workflow";               DEF_PARTS="agents,commands,skills";;
  *)     DEF_MCP="spec-workflow,serena";        DEF_PARTS="agents,commands,skills,settings";;
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
    printf "  3) chrome-devtools — browser pro agente (npx, isolado: um Chrome por sessão)\n> "
    r=""; prompt_read r
    MCP_CSV="$(printf '%s' "$r" | sed 's/1/spec-workflow/g; s/2/serena/g; s/3/chrome-devtools/g')"; MCP_SET=1
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
      chrome-devtools|devtools|chrome)            x=chrome-devtools;;
      none|nenhum)                                continue;;
      memory|memoria|memória|qdrant|qdrant-memory)
        die "--mcp memory saiu do instalador: a memória Qdrant virou a skill 'qdrant-setup' (command /qdrant).";;
      *) die "--mcp: '$x' desconhecido (use spec-workflow, serena, chrome-devtools ou none)";;
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
      none|nenhum)               continue;;
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
if [ "$GLOBAL" -eq 1 ]; then
  csv_has "$MCP_CSV" serena && die "--global: o Serena é por projeto (precisa do --project). Instale-o no projeto."
  if csv_has "$PARTS_CSV" settings; then
    warn "--global: settings.json fica de fora (daria permissões amplas em todo projeto da máquina)"
    PARTS_CSV="$(printf ',%s,' "$PARTS_CSV" | sed 's/,settings,/,/; s/^,//; s/,$//')"
  fi
fi
check_names skills   "$SKILLS_CSV"
check_names agents   "$SUBAGENTS_CSV"
check_names commands "$COMMANDS_CSV"

HAS_SPEC=0; HAS_SERENA=0; HAS_DEVTOOLS=0
if csv_has "$MCP_CSV" spec-workflow;   then HAS_SPEC=1; fi
if csv_has "$MCP_CSV" serena;          then HAS_SERENA=1; fi
if csv_has "$MCP_CSV" chrome-devtools; then HAS_DEVTOOLS=1; fi

# ---------- pré-requisitos da máquina (uma vez por máquina, opt-in) ----------
# Só pergunta o que faz sentido pro que foi escolhido: sem serena não instala serena.
# O local-infra não é mais oferecido sozinho — ele só aparecia porque o Qdrant guardava a
# memória, e a memória saiu daqui. Continua disponível via --infra e pela skill 'local-infra'.
[ -z "$SETUP_INFRA" ] && SETUP_INFRA=0
if [ -z "$SETUP_SERENA" ]; then
  if [ "$HAS_SERENA" -eq 0 ] || [ "$ASSUME_YES" -eq 1 ]; then SETUP_SERENA=0; else
    echo ""
    printf "${c_bold}Instalar o Serena (navegação semântica do código)?${c_reset}\n"
    printf "  CLI no host via uv (não é container). Necessário pro MCP 'serena' conectar.\n"
    r=""; printf "  [s/N]: "; prompt_read r
    case "$r" in [sSyY]*) SETUP_SERENA=1;; *) SETUP_SERENA=0;; esac
  fi
fi

# ---------- Orca: com ou sem o contexto de worktrees ----------
# Só pergunta se o Orca está instalado aqui — pra quem não usa, a pergunta é ruído.
if [ -z "$ORCA" ]; then
  if [ "$ASSUME_YES" -eq 0 ] && [ "$HAVE_TTY" -eq 1 ] && command -v orca >/dev/null 2>&1; then
    echo ""
    printf "${c_bold}Você usa o Orca (onorca.dev)?${c_reset}\n"
    printf "  Adiciona as regras de worktree ao AGENTS.md e o .worktreeinclude pros arquivos fora do git.\n"
    r=""; printf "  [s/N]: "; prompt_read r
    case "$r" in [sSyY]*) ORCA=1;; *) ORCA=0;; esac
  else
    ORCA=0
  fi
fi

# ---------- tags: o que existe neste projeto (filtra AGENTS.md, templates e itens) ----------
TAGS=""
if [ "$HAS_SPEC" -eq 1 ];   then TAGS="$TAGS spec"; fi
if [ "$HAS_SERENA" -eq 1 ]; then TAGS="$TAGS serena"; fi
if [ -n "$MCP_CSV" ];       then TAGS="$TAGS mcp"; fi
if [ "$ORCA" = "1" ];       then TAGS="$TAGS orca"; fi
if [ "$PRESET" = "full" ] || [ "$SETUP_INFRA" = "1" ] || [ "$GLOBAL" -eq 1 ]; then
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

info "Instalando: preset $PRESET · MCP: ${MCP_CSV:-nenhum} · partes: ${PARTS_CSV:-nenhuma (vêm do --global)}"

# ---------- Codex: helpers do ~/.codex/config.toml (usados no install por projeto e no --global) ----------
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
    chrome-devtools)
      printf '[mcp_servers.chrome-devtools]\ncommand = "npx"\nargs = [%s]\n' '"-y", "chrome-devtools-mcp@latest", "--isolated"';;
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
  if [ "$HAS_DEVTOOLS" -eq 1 ]; then want="$want chrome-devtools"; fi
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

# ---------- --global: instala pra todos os projetos da máquina ----------
# O manifest (~/.buildison/global.manifest) lista o que ESTE modo pôs no disco. É o que separa
# item do buildison de item seu: só o que está nele é sobrescrito ou retirado. Sem isso, rodar
# de novo apagaria skills suas com o mesmo nome, ou deixaria órfã pra sempre uma skill que saiu.
claude_user_mcp_has() { # nome → o MCP existe no escopo USER do Claude Code?
  # Lê o ~/.claude.json direto: o `claude mcp get` também enxerga o .mcp.json da pasta atual,
  # e aí um servidor de projeto passaria por global.
  local py; py="$(find_python || true)"
  [ -n "$py" ] && [ -f "$HOME/.claude.json" ] || return 1
  "$py" - "$HOME/.claude.json" "$1" <<'PYHAS'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if sys.argv[2] in (d.get("mcpServers") or {}) else 1)
PYHAS
}
plugin_root() { # nome → pasta do plugin do Claude Code instalado nesta máquina (vazio se não achar)
  # Marketplace fica em installed_plugins.json (com installPath); plugin sincronizado da conta do
  # claude.ai ("My Uploads" etc.) fica em ~/.claude/plugins/synced/<id>/<nome>/.
  local py p; py="$(find_python || true)"
  if [ -n "$py" ]; then
    "$py" - "$1" <<'PYPLUG' || true
import glob, json, os, sys
name, home = sys.argv[1], os.path.expanduser("~")
try:
    d = json.load(open(os.path.join(home, ".claude/plugins/installed_plugins.json")))
    for key, installs in (d.get("plugins") or {}).items():
        if key.split("@")[0] != name:
            continue
        for i in sorted(installs, key=lambda i: i.get("scope") != "user"):
            if i.get("installPath") and os.path.isdir(i["installPath"]):
                print(i["installPath"]); sys.exit(0)
except Exception:
    pass
for p in sorted(glob.glob(os.path.join(home, ".claude/plugins/synced/*", name))):
    if os.path.isfile(os.path.join(p, ".claude-plugin/plugin.json")):
        print(p); sys.exit(0)
PYPLUG
    return 0
  fi
  for p in "$HOME"/.claude/plugins/synced/*/"$1"; do
    [ -f "$p/.claude-plugin/plugin.json" ] && { echo "$p"; return 0; }
  done
  return 0
}
global_put() { # origem  pasta-destino → 0 instalou · 1 pulou (item seu). Usa old/new/bak do install_global.
  local src="$1" base="$2" dst
  dst="$base/$(basename "$src")"
  if [ -e "$dst" ] && ! grep -qxF "$dst" "$old"; then
    if [ "$FORCE" -eq 0 ]; then
      warn "${dst/#$HOME/~} já existe e não foi o buildison que pôs lá — mantido (--force sobrescreve)"
      return 1
    fi
    [ -z "$bak" ] && { bak="$GLOBAL_DIR/removidos-$(date +%s)"; mkdir -p "$bak"; }
    mkdir -p "$bak/$(dirname "${dst#$HOME/}")"; mv "$dst" "$bak/${dst#$HOME/}"
  fi
  mkdir -p "$base"
  # rm antes do cp: cp -R mescla, e arquivo removido de dentro de uma skill ficaria órfão
  rm -rf "$dst"
  cp -R "$src" "$base/"
  echo "$dst" >> "$new"
  return 0
}
# ---------- Orca ----------
# No Orca cada tarefa vira uma git worktree: um checkout LIMPO. O que está no .gitignore não vai
# junto — se o .claude/ do projeto é ignorado (há projetos assim), o agente da worktree nova roda sem a
# toolbox. O .worktreeinclude da raiz lista caminhos ignorados que o Orca COPIA pra cada worktree.
strip_bld_block() { # arquivo → conteúdo sem o bloco # >>> buildison >>> e sem linhas em branco no fim
  awk '/^# >>> buildison >>>/{s=1;next} /^# <<< buildison <<</{s=0;next} !s{a[++n]=$0; if (NF) last=n}
       END{for (i=1; i<=last; i++) print a[i]}' "$1"
}
orca_worktreeinclude() {
  local f="$TARGET_DIR/.worktreeinclude" tmp="$WORK/worktreeinclude" p list=""
  if ! git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    warn "Orca: $TARGET_DIR não é repositório git — o Orca trabalha com worktrees, então .worktreeinclude não se aplica"
    return 0
  fi
  for p in .claude .agents AGENTS.md CLAUDE.md docs/agent .mcp.json opencode.json .buildison .spec-workflow; do
    [ -e "$TARGET_DIR/$p" ] || continue
    if git -C "$TARGET_DIR" check-ignore -q "$p" 2>/dev/null; then list="$list$p"$'\n'; fi
  done
  # regrava só o bloco do buildison; o resto do arquivo (o .env do projeto etc.) é seu
  if [ -f "$f" ]; then
    strip_bld_block "$f" > "$tmp"
  else
    : > "$tmp"
  fi
  if [ -n "$list" ]; then
    {
      cat "$tmp"
      if [ -s "$tmp" ]; then echo ""; fi
      echo "# >>> buildison >>>"
      echo "# Fora do git neste repo: o Orca copia pra cada worktree nova, senão o agente lá roda sem a toolbox."
      printf '%s' "$list"
      echo "# <<< buildison <<<"
    } > "$f"
    ok "Orca: .worktreeinclude — $(printf '%s' "$list" | tr '\n' ' ')"
  else
    if [ -s "$tmp" ]; then cp "$tmp" "$f"; elif [ -f "$f" ]; then rm -f "$f"; fi
    ok "Orca: nada do buildison está no .gitignore — depois de commitar, toda worktree nova recebe (nada a pôr no .worktreeinclude)"
  fi
}
orca_skills_check() { # as skills do Orca são DELE: instaladas e atualizadas pelo próprio Orca
  local miss="" s cmd=""
  for s in orca-cli orchestration; do
    [ -e "$HOME/.claude/skills/$s" ] || [ -e "$HOME/.agents/skills/$s" ] || miss="$miss $s"
  done
  if [ -z "$miss" ]; then ok "Orca: skills orca-cli e orchestration instaladas"; return 0; fi
  for s in $miss; do cmd="$cmd --skill $s"; done
  warn "Orca: faltam skills do Orca:$miss. O buildison não copia — são do Orca, e ele as mantém atualizadas."
  if command -v orca >/dev/null 2>&1; then warn "  Instale com: orca skills install$cmd"
  else warn "  Instale com: npx skills add https://github.com/stablyai/orca$cmd --global"; fi
}
devtools_unisolated() { # [projeto] → onde o chrome-devtools-mcp roda SEM isolamento (1 por linha)
  # Sem --isolated, todo chrome-devtools-mcp usa o MESMO perfil (~/.cache/chrome-devtools-mcp/
  # chrome-profile). Duas sessões ao mesmo tempo — dois Claudes, Claude + Antigravity — e a segunda
  # falha com "browser is already running". --browserUrl/--wsEndpoint/--autoConnect também escapam:
  # conectam num Chrome que já existe em vez de abrir outro.
  local py; py="$(find_python || true)"; [ -n "$py" ] || return 0
  "$py" - "$HOME" "${1:-}" <<'PYDT' || true
import json, os, re, sys
home, proj = sys.argv[1], sys.argv[2]
SAFE = ("--isolated", "--browserUrl", "--browser-url", "-u", "--wsEndpoint", "--ws-endpoint", "-w",
        "--autoConnect", "--auto-connect")
def unsafe(words):
    words = [w for w in words if isinstance(w, str)]
    if not any("chrome-devtools-mcp" in w for w in words):
        return False
    return not any(w == f or w.startswith(f + "=") for w in words for f in SAFE)
def load(p):
    try:
        return json.load(open(p))
    except Exception:
        return None
def scan(label, servers):
    for name, sv in (servers or {}).items():
        if not isinstance(sv, dict):
            continue
        cmd = sv.get("command")
        words = (cmd if isinstance(cmd, list) else [cmd]) + list(sv.get("args") or [])
        if unsafe(words):
            print(f"{label} → {name}")
cj = load(os.path.join(home, ".claude.json")) or {}
scan("~/.claude.json (escopo user do Claude)", cj.get("mcpServers"))
if proj:
    scan(f"~/.claude.json (escopo local de {proj})", ((cj.get("projects") or {}).get(proj) or {}).get("mcpServers"))
    scan(f"{proj}/.mcp.json", (load(os.path.join(proj, ".mcp.json")) or {}).get("mcpServers"))
    scan(f"{proj}/.agents/mcp_config.json", (load(os.path.join(proj, ".agents/mcp_config.json")) or {}).get("mcpServers"))
    scan(f"{proj}/opencode.json", (load(os.path.join(proj, "opencode.json")) or {}).get("mcp"))
for c in (".gemini/config/mcp_config.json", ".gemini/antigravity/mcp_config.json"):
    scan(f"~/{c} (global do Antigravity)", (load(os.path.join(home, c)) or {}).get("mcpServers"))
toml = os.path.join(home, ".codex/config.toml")
if os.path.exists(toml):
    # sem tomllib no python 3.9: separa por tabela e procura nos args de cada uma
    for m in re.finditer(r"^\[mcp_servers\.([^\]\s.]+)\]\s*$(.*?)(?=^\[|\Z)", open(toml).read(), re.M | re.S):
        if unsafe(re.findall(r'"([^"]*)"', m.group(2))):
            print(f"~/.codex/config.toml → {m.group(1)}")
PYDT
}
devtools_warn() { # [projeto]
  local hits; hits="$(devtools_unisolated "${1:-}")"
  [ -n "$hits" ] || return 0
  echo ""
  warn "chrome-devtools-mcp SEM --isolated — duas sessões ao mesmo tempo disputam o mesmo perfil do Chrome e a segunda falha:"
  printf '%s\n' "$hits" | sed 's/^/    /'
  warn "Acrescente \"--isolated\" nos args (ou reinstale com --mcp chrome-devtools, que já vem isolado)."
}
global_claude_mcp() { # nome  quer(0|1)  comando... → põe/tira o MCP no escopo USER do Claude Code
  # Usa old/new do install_global. Só tira o que o --global pôs (manifest): um MCP que você
  # registrou à mão fica.
  local name="$1" want_it="$2"; shift 2
  if [ "$want_it" -eq 1 ]; then
    if claude_user_mcp_has "$name"; then
      ok "Claude: MCP $name já está no escopo user — mantido"
      if grep -qxF "mcp:claude:$name" "$old"; then echo "mcp:claude:$name" >> "$new"; fi
    elif ! command -v claude >/dev/null 2>&1; then
      warn "Claude: CLI 'claude' não está no PATH — MCP não registrado. Rode: claude mcp add -s user $name -- $*"
    elif (cd "$HOME" && claude mcp add -s user "$name" -- "$@") >/dev/null 2>&1; then
      ok "Claude: MCP $name no escopo user (vale em todo projeto)"
      echo "mcp:claude:$name" >> "$new"
    else
      warn "Claude: falhou registrar o MCP. Rode: claude mcp add -s user $name -- $*"
    fi
  elif grep -qxF "mcp:claude:$name" "$old"; then
    if command -v claude >/dev/null 2>&1 && (cd "$HOME" && claude mcp remove -s user "$name") >/dev/null 2>&1; then
      ok "Claude: MCP $name removido do escopo user (saiu da seleção)"
    else
      warn "Claude: não consegui remover o MCP. Rode: claude mcp remove -s user $name"
      echo "mcp:claude:$name" >> "$new"
    fi
  fi
}
install_global() {
  local old="$WORK/global.old" new="$WORK/global.new" root part item name dst base n moved=0 bak="" agents=""
  local plug proot left py plugs_ok=""
  local want_it
  mkdir -p "$GLOBAL_DIR"
  : > "$new"
  if [ -f "$GLOBAL_MAN" ]; then cp "$GLOBAL_MAN" "$old"; else : > "$old"; fi

  if [ "$SEL_CLAUDE" -eq 1 ]; then agents="claude"; fi
  if [ "$SEL_CODEX" -eq 1 ];  then agents="${agents:+$agents,}codex"; fi
  if [ "$SEL_ANTIGRAVITY" -eq 1 ]; then agents="${agents:+$agents,}antigravity"; fi
  if [ "$HAS_SPEC" -eq 1 ]; then info "Instalando no global — versão COM spec-workflow"
  else info "Instalando no global — versão SEM spec-workflow"; fi

  # Claude Code lê agents/commands/skills de ~/.claude; o Codex só tem skills, em ~/.agents/skills
  for root in $(printf '%s' "$agents" | tr ',' ' '); do
    for part in agents commands skills; do
      case "$root" in
        claude) base="$HOME/.claude/$part";;
        codex)  [ "$part" = skills ] || continue; base="$HOME/.agents/skills";;
        *)      continue;;   # antigravity: logo abaixo, a partir do .agents/ da fonte
      esac
      n=0
      for item in "$SRC_DIR/.claude/$part"/*; do
        [ -e "$item" ] || continue
        name="$(basename "$item")"
        item_selected "$part" "${name%.md}" || continue
        if global_put "$item" "$base"; then n=$((n+1)); fi
      done
      if [ "$n" -gt 0 ]; then ok "${base/#$HOME/~}/ ($n)"; fi
    done
  done

  # ---- Antigravity: skills em pasta (commands já convertidos em skill) e agents, do .agents/ da fonte ----
  # O 2.0 e a IDE leem ~/.gemini/config/{skills,agents}; o CLI (agy) lê skills de ~/.gemini/antigravity-cli.
  # MCP não vai pro global do Antigravity: ele valeria em todo projeto (ver o .agents/mcp_config.json).
  if [ "$SEL_ANTIGRAVITY" -eq 1 ]; then
    for base in "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity-cli/skills"; do
      case "$base" in *antigravity-cli*) [ -d "$HOME/.gemini/antigravity-cli" ] || continue;; esac
      n=0
      for item in "$SRC_DIR/.agents/skills"/*; do
        [ -d "$item" ] || continue
        name="$(basename "$item")"
        if [ -e "$SRC_DIR/.claude/commands/$name.md" ]; then part=commands; else part=skills; fi
        item_selected "$part" "$name" || continue
        if global_put "$item" "$base"; then n=$((n+1)); fi
      done
      if [ "$n" -gt 0 ]; then ok "${base/#$HOME/~}/ ($n)"; fi
    done
    n=0
    for item in "$SRC_DIR/.agents/agents"/*.md; do
      [ -f "$item" ] || continue
      item_selected agents "$(basename "$item" .md)" || continue
      if global_put "$item" "$HOME/.gemini/config/agents"; then n=$((n+1)); fi
    done
    if [ "$n" -gt 0 ]; then ok "~/.gemini/config/agents/ ($n)"; fi
    if [ -n "$MCP_CSV" ]; then
      info "Antigravity: o MCP ($MCP_CSV) não vai pro global dele — valeria em todo projeto. Instale no projeto pra ter .agents/mcp_config.json."
    fi
  fi

  # ---- skills de plugins do Claude → Codex (--plugin-skills) ----
  # O Codex não roda plugin do Claude, mas lê a skill dele se ela estiver em ~/.agents/skills. O
  # conteúdo vem do plugin instalado NESTA máquina — o repo buildison não carrega nada de terceiro.
  for plug in $(printf '%s' "$PLUGIN_SKILLS_CSV" | tr ',' ' '); do
    if [ "$SEL_CODEX" -eq 0 ]; then
      info "plugin $plug: sem --agents codex não há o que copiar (no Claude ele já vem do próprio plugin)"
      continue
    fi
    proot="$(plugin_root "$plug")"
    if [ -z "$proot" ] || [ ! -d "$proot/skills" ]; then
      warn "plugin '$plug' não está instalado no Claude Code desta máquina (ou não tem skills) — pulado"
      continue
    fi
    n=0
    for item in "$proot/skills"/*; do
      [ -f "$item/SKILL.md" ] || continue
      global_put "$item" "$HOME/.agents/skills" || continue
      n=$((n+1))
      # ${CLAUDE_PLUGIN_ROOT} só existe dentro do Claude Code: aponta pra pasta da cópia
      dst="$HOME/.agents/skills/$(basename "$item")"
      py="$(find_python || true)"
      if [ -z "$py" ]; then
        warn "plugin $plug: sem python, não reescrevi \${CLAUDE_PLUGIN_ROOT} em ${dst/#$HOME/~} — as referências da skill podem não abrir no Codex"
        continue
      fi
      left="$("$py" - "$dst" "$(basename "$item")" <<'PYREW'
import os, sys
root, name = sys.argv[1], sys.argv[2]
left = 0
for dp, _, files in os.walk(root):
    for f in files:
        if not f.endswith(".md"):
            continue
        p = os.path.join(dp, f)
        s = open(p, encoding="utf-8").read()
        t = s
        for var in ("${CLAUDE_PLUGIN_ROOT}", "$CLAUDE_PLUGIN_ROOT"):
            t = t.replace(var + "/skills/" + name, root)
        left += t.count("CLAUDE_PLUGIN_ROOT")
        if t != s:
            open(p, "w", encoding="utf-8").write(t)
print(left)
PYREW
)"
      if [ "${left:-0}" -gt 0 ]; then
        warn "plugin $plug: ${dst/#$HOME/~} ainda cita \${CLAUDE_PLUGIN_ROOT} fora da própria skill ($left vez(es)) — isso não resolve no Codex"
      fi
    done
    if [ "$n" -gt 0 ]; then ok "~/.agents/skills/ (+$n do plugin $plug · no Claude segue o plugin)"; plugs_ok="${plugs_ok:+$plugs_ok,}$plug"; fi
  done

  # o que o buildison pôs antes e não entra mais (trocou de versão, filtrou, tirou um agente):
  # vai pra ~/.buildison/removidos-*, não pro lixo — pode ter edição sua dentro
  while IFS= read -r dst; do
    case "$dst" in ""|mcp:*) continue;; esac
    grep -qxF "$dst" "$new" && continue
    [ -e "$dst" ] || continue
    [ -z "$bak" ] && { bak="$GLOBAL_DIR/removidos-$(date +%s)"; mkdir -p "$bak"; }
    mkdir -p "$bak/$(dirname "${dst#$HOME/}")"
    mv "$dst" "$bak/${dst#$HOME/}"
    moved=$((moved+1))
  done < "$old"
  if [ "$moved" -gt 0 ]; then warn "$moved item(ns) que o buildison tinha posto no global saíram da seleção — movidos pra ${bak/#$HOME/~}"; fi

  # ---- MCP no escopo user do Claude: spec-workflow (versão "com") e chrome-devtools (se pedido) ----
  if [ "$SEL_CLAUDE" -eq 1 ]; then
    global_claude_mcp spec-workflow "$HAS_SPEC" npx -y @pimzino/spec-workflow-mcp@latest .
    global_claude_mcp chrome-devtools "$HAS_DEVTOOLS" npx -y chrome-devtools-mcp@latest --isolated
  fi
  if [ "$SEL_CODEX" -eq 1 ]; then
    if [ "$HAS_SPEC" -eq 1 ] || [ "$HAS_DEVTOOLS" -eq 1 ]; then codex_write_mcp; fi
    for plug in spec-workflow chrome-devtools; do
      case "$plug" in spec-workflow) want_it="$HAS_SPEC";; *) want_it="$HAS_DEVTOOLS";; esac
      if [ "$want_it" -eq 1 ]; then echo "mcp:codex:$plug" >> "$new"
      elif grep -qxF "mcp:codex:$plug" "$old"; then
        # o ~/.codex/config.toml é o mesmo que os installs por projeto usam: tirar daqui quebraria
        # projeto que conta com ele. Fica, e você decide.
        info "Codex: o $plug continua no ~/.codex/config.toml (config compartilhada com projetos) — tire à mão se quiser"
      fi
    done
  fi

  cp "$new" "$GLOBAL_MAN"
  cat > "$GLOBAL_CFG" <<EOFCFG
# buildison — o que está instalado no GLOBAL (~/.claude e ~/.agents/skills). Rodar
# "install.sh --global" de novo relê este arquivo; passe --preset files|lite pra trocar de versão.
BUILDISON_PRESET=$PRESET
BUILDISON_MCP=$MCP_CSV
BUILDISON_PARTS=$PARTS_CSV
BUILDISON_SKILLS=$SKILLS_CSV
BUILDISON_SUBAGENTS=$SUBAGENTS_CSV
BUILDISON_COMMANDS=$COMMANDS_CSV
BUILDISON_AGENTS=$AGENTS_SAVED
BUILDISON_PLUGIN_SKILLS=$PLUGIN_SKILLS_CSV
BUILDISON_ORCA=$ORCA
EOFCFG
  if [ "$ORCA" = "1" ]; then orca_skills_check; fi

  [ "$SETUP_INFRA" = "1" ]  && { echo ""; info "Montando local-infra..."; setup_local_infra; }
  [ "$SETUP_SERENA" = "1" ] && { echo ""; info "Configurando Serena..."; setup_serena; }

  echo ""
  if [ "$CODEX_FAILED" -eq 1 ]; then warn "Codex NÃO foi configurado: conserte as tabelas repetidas no ~/.codex/config.toml e rode de novo."; fi
  devtools_warn
  ok "Global instalado (${agents}) — versão $( [ "$HAS_SPEC" -eq 1 ] && echo com || echo sem ) spec-workflow${plugs_ok:+ · + skills de plugin no Codex: $plugs_ok}"
  echo ""
  printf "${c_bold}Próximos passos:${c_reset}\n"
  echo "  1. Abra qualquer projeto: agents, commands e skills já aparecem (reinicie o agente se estiver aberto)."
  if [ "$HAS_SPEC" -eq 1 ] && [ "$SEL_CLAUDE" -eq 1 ]; then
    echo "  2. Os templates próprios do buildison (.spec-workflow/templates/) só vêm no install por projeto;"
    echo "     no global o spec-workflow usa os templates padrão dele."
  fi
  echo "  · Atualizar: rode o mesmo comando de novo. Trocar de versão: --global --preset files|lite."
  echo "  · Não instale o buildison também por projeto: os itens aparecem duplicados."
}
if [ "$GLOBAL" -eq 1 ]; then install_global; exit 0; fi

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

# Regrava um JSON de MCP preservando servidores que o instalador NÃO gerencia.
# O arquivo é reescrito do zero a cada run; sem isso, um MCP que você (ou a skill
# qdrant-setup) adicionou sumia em silêncio no próximo --update — o mesmo modo de falha
# que o bloco do Codex já tinha com tabelas desconhecidas.
merge_mcp_json() { # arquivo  chave-raiz  json-novo  managed-csv
  local f="$1" root="$2" fresh="$3" managed="$4" py
  py="$(find_python || true)"
  if [ -z "$py" ] || [ ! -f "$f" ]; then
    printf '%s\n' "$fresh" > "$f"; return 0
  fi
  printf '%s' "$fresh" > "$WORK/mcp-fresh.json"
  "$py" - "$f" "$root" "$WORK/mcp-fresh.json" "$managed" <<'PYMERGE' || printf '%s\n' "$fresh" > "$f"
import json, sys
path, root, freshpath, managed = sys.argv[1:5]
managed = {m for m in managed.split(",") if m}
fresh = json.load(open(freshpath))
try:
    old = json.load(open(path))
    if not isinstance(old, dict): old = {}
except Exception:
    old = {}
out = dict(old)
out.update({k: v for k, v in fresh.items() if k != root})
servers = dict(old.get(root) or {})
# tira só o que ESTE instalador gerencia e não foi pedido agora; o resto fica
for k in list(servers):
    if k in managed and k not in (fresh.get(root) or {}):
        del servers[k]
servers.update(fresh.get(root) or {})
out[root] = servers
with open(path, "w") as f:
    json.dump(out, f, indent=2); f.write("\n")
PYMERGE
  return 0
}

# entradas de JSON separadas por vírgula (.mcp.json / opencode.json)
ENTRIES=""
add_entry() { if [ -n "$ENTRIES" ]; then ENTRIES="$ENTRIES,"$'\n'; fi; ENTRIES="$ENTRIES$1"; }

# ---------- Claude Code ----------
if [ "$SEL_CLAUDE" -eq 1 ]; then
  info "Configurando Claude Code..."
  if [ -s "$GLOBAL_MAN" ] && { csv_has "$PARTS_CSV" agents || csv_has "$PARTS_CSV" commands || csv_has "$PARTS_CSV" skills; }; then
    warn "o buildison também está no global (~/.claude): neste projeto os agents, commands e skills vão aparecer duplicados — use --preset context"
  fi
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
    if [ "$HAS_DEVTOOLS" -eq 1 ]; then
      add_entry '    "chrome-devtools": { "command": "npx", "args": ["-y", "chrome-devtools-mcp@latest", "--isolated"] }'
    fi
    merge_mcp_json "$TARGET_DIR/.mcp.json" mcpServers \
      "$(printf '{\n  "mcpServers": {\n%s\n  }\n}\n' "$ENTRIES")" "spec-workflow,serena"
    ok ".mcp.json (${MCP_CSV})"
  else
    ok "Claude: sem MCP neste preset — .mcp.json não gerado"
  fi
fi

# ---------- Codex (AGENTS.md já copiado; MCP no ~/.codex/config.toml) ----------
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
    if [ "$HAS_DEVTOOLS" -eq 1 ]; then
      add_entry '    "chrome-devtools": { "type": "local", "command": ["npx", "-y", "chrome-devtools-mcp@latest", "--isolated"], "enabled": true }'
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

antigravity_global_pinned() { # servidores de projeto presos no config GLOBAL do Antigravity (1 por linha)
  local py c; py="$(find_python || true)"; [ -n "$py" ] || return 0
  for c in "$HOME/.gemini/config/mcp_config.json" "$HOME/.gemini/antigravity/mcp_config.json"; do
    [ -f "$c" ] || continue
    "$py" - "$c" <<'PYPIN' || true
import json, sys
path = sys.argv[1]
try:
    servers = json.load(open(path)).get("mcpServers") or {}
except Exception:
    sys.exit(0)
for name in ("spec-workflow", "serena", "qdrant-memory"):
    s = servers.get(name)
    if not isinstance(s, dict):
        continue
    # caminho absoluto nos args (projeto fixo) ou coleção fixa do Qdrant = preso a um projeto
    fixed = [a for a in (s.get("args") or []) if isinstance(a, str) and (a.startswith("/") or a[1:3] == ":\\")]
    coll = (s.get("env") or {}).get("COLLECTION_NAME")
    if fixed or coll:
        print(f"{name} → {fixed[0] if fixed else 'COLLECTION_NAME=' + coll}  ({path})")
PYPIN
  done
}
# ---------- Antigravity (Google) — AGENTS.md nativo + .agents/ + MCP por projeto ----------
# O Antigravity lê AGENTS.md da raiz (já copiado no core). Aqui espelhamos skills (pastas no padrão
# Agent Skills; commands entram como skill e viram /<nome>) e agents (.agents/agents/<nome>.md) com os
# mesmos filtros do .claude/, e registramos a toolbox MCP no config DO PROJETO: .agents/mcp_config.json.
# Projeto que gera o próprio .agents/ (ex.: vibedesign, com `pnpm sync:agents` e um CI que confere a
# sincronia) marca a pasta com GERADO.md. Escrever por cima quebraria esse check — o padrão com o
# Antigravity incluído não pode fazer isso sozinho.
if [ "$SEL_ANTIGRAVITY" -eq 1 ] && [ -f "$TARGET_DIR/.agents/GERADO.md" ] && ! grep -qs "gen-antigravity" "$TARGET_DIR/.agents/GERADO.md"; then
  warn "Antigravity: o .agents/ deste projeto é gerado por um script dele (.agents/GERADO.md) — não mexo; rode o gerador do projeto."
  SEL_ANTIGRAVITY=0
fi
if [ "$SEL_ANTIGRAVITY" -eq 1 ]; then
  info "Configurando Antigravity..."
  if [ -d "$SRC_DIR/.agents/skills" ]; then
    # Formato antigo deste instalador: skill como .agents/skills/<nome>.md solto, e commands/agentes
    # como .agents/workflows/<nome>.md. Workflows saem do Antigravity em 2026-11-01, arquivo solto não
    # é skill no padrão atual, e os dois duplicariam os /comandos novos. Só sai o que tem a marca do
    # gerador — o que você escreveu à mão fica.
    legacy=0
    for f in "$TARGET_DIR/.agents/skills"/*.md "$TARGET_DIR/.agents/workflows"/*.md; do
      [ -f "$f" ] || continue
      grep -q "por gen-antigravity.mjs" "$f" || continue
      rm -f "$f"; legacy=$((legacy+1))
    done
    rmdir "$TARGET_DIR/.agents/workflows" 2>/dev/null || true
    if [ "$legacy" -gt 0 ]; then info "Antigravity: $legacy arquivo(s) do formato antigo (skill solta / workflow) removidos"; fi
    n=0; c=0; a=0
    for f in "$SRC_DIR/.agents/skills"/*; do
      [ -d "$f" ] || continue
      name="$(basename "$f")"
      # command convertido em skill segue o filtro de commands; o resto, o de skills
      if [ -e "$SRC_DIR/.claude/commands/$name.md" ]; then part=commands; else part=skills; fi
      item_selected "$part" "$name" || continue
      mkdir -p "$TARGET_DIR/.agents/skills"
      rm -rf "$TARGET_DIR/.agents/skills/$name"   # cp -R mescla: arquivo que saiu da skill ficaria órfão
      cp -R "$f" "$TARGET_DIR/.agents/skills/"
      if [ "$part" = commands ]; then c=$((c+1)); else n=$((n+1)); fi
    done
    for f in "$SRC_DIR/.agents/agents"/*.md; do
      [ -f "$f" ] || continue
      item_selected agents "$(basename "$f" .md)" || continue
      mkdir -p "$TARGET_DIR/.agents/agents"; cp -f "$f" "$TARGET_DIR/.agents/agents/"; a=$((a+1))
    done
    if [ $((n + c + a)) -eq 0 ] && [ "$PRESET" = "context" ]; then
      ok "Antigravity: skills e agents vêm do global (preset context)"
    else
      ok ".agents/ ($n skills + $c commands como skill, $a agents)"
    fi
  else
    warn ".agents/skills não existe na fonte — rode 'node scripts/gen-antigravity.mjs' no repo buildison."
  fi
  # MCP de projeto vai no config DO PROJETO (.agents/mcp_config.json), nunca no global. O global
  # (~/.gemini/config/mcp_config.json) vale pra todo projeto aberto no Antigravity: gravar ali
  # prendia serena, spec-workflow e qdrant-memory a UM projeto em todos os outros, e a memória de
  # um projeto ia parar na coleção de outro. Caminhos relativos, igual ao .mcp.json do Claude.
  if [ -z "$MCP_CSV" ]; then
    ok "Antigravity: sem MCP neste preset — .agents/mcp_config.json não gerado"
  else
    ENTRIES=""
    if [ "$HAS_SPEC" -eq 1 ]; then
      add_entry '    "spec-workflow": { "command": "npx", "args": ["-y", "@pimzino/spec-workflow-mcp@latest", "."] }'
    fi
    if [ "$HAS_SERENA" -eq 1 ]; then
      add_entry '    "serena": { "command": "serena", "args": ["start-mcp-server", "--context", "ide-assistant", "--project", ".", "--enable-web-dashboard", "false", "--open-web-dashboard", "false", "--enable-gui-log-window", "false"] }'
    fi
    if [ "$HAS_DEVTOOLS" -eq 1 ]; then
      add_entry '    "chrome-devtools": { "command": "npx", "args": ["-y", "chrome-devtools-mcp@latest", "--isolated"] }'
    fi
    mkdir -p "$TARGET_DIR/.agents"
    merge_mcp_json "$TARGET_DIR/.agents/mcp_config.json" mcpServers \
      "$(printf '{\n  "mcpServers": {\n%s\n  }\n}\n' "$ENTRIES")" "spec-workflow,serena"
    ok "Antigravity: MCP em .agents/mcp_config.json (${MCP_CSV}) — só neste projeto"
  fi
  AG_PINNED="$(antigravity_global_pinned)"
  if [ -n "$AG_PINNED" ]; then
    warn "O config GLOBAL do Antigravity prende MCP a um projeto — vale em TODO projeto que você abrir:"
    printf '%s\n' "$AG_PINNED" | sed 's/^/    /'
    warn "Tire essas chaves de lá (backup antes). Instalações antigas do buildison gravavam no global; esta não grava mais."
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
BUILDISON_AGENTS=$AGENTS_SAVED
BUILDISON_ORCA=$ORCA
EOF
ok ".buildison"

if [ "$ORCA" = "1" ]; then
  info "Configurando o contexto do Orca..."
  orca_worktreeinclude
  orca_skills_check
elif [ -f "$TARGET_DIR/.worktreeinclude" ] && grep -q '^# >>> buildison >>>' "$TARGET_DIR/.worktreeinclude"; then
  # saiu do Orca: tira só o bloco que o buildison pôs; o resto do arquivo é do projeto
  strip_bld_block "$TARGET_DIR/.worktreeinclude" > "$WORK/wti-off"
  if grep -q '[^[:space:]]' "$WORK/wti-off"; then cp "$WORK/wti-off" "$TARGET_DIR/.worktreeinclude"; else rm -f "$TARGET_DIR/.worktreeinclude"; fi
  ok "Orca desligado: bloco do buildison tirado do .worktreeinclude"
fi

# ---------- pré-requisitos da máquina (execução) ----------
[ "$SETUP_INFRA" = "1" ]  && { echo ""; info "Montando local-infra..."; setup_local_infra; }
[ "$SETUP_SERENA" = "1" ] && { echo ""; info "Configurando Serena..."; setup_serena; }

# ---------- resumo ----------
echo ""
ok "Instalação concluída em $TARGET_DIR (preset $PRESET · MCP: ${MCP_CSV:-nenhum})"
if [ "$CODEX_FAILED" -eq 1 ]; then
  warn "Codex NÃO foi configurado: conserte as tabelas repetidas no ~/.codex/config.toml e rode de novo."
fi
devtools_warn "$TARGET_DIR"
if [ "$PRESET" = "context" ]; then
  # troca de um preset completo pra context: o que o buildison pôs antes no .claude/ continua lá e duplica
  # com o global. Não apagamos — pode ter sido customizado —, só listamos.
  LEFT=""
  for part in agents commands skills; do
    for item in "$SRC_DIR/.claude/$part"/*; do
      [ -e "$item" ] || continue
      [ -e "$TARGET_DIR/.claude/$part/$(basename "$item")" ] && LEFT="$LEFT .claude/$part/$(basename "$item")"
    done
  done
  if [ -n "$LEFT" ]; then
    echo ""
    warn "preset context: estes itens do buildison continuam no .claude/ do projeto e vão duplicar com o global:"
    printf '%s\n' $LEFT | sed 's/^/    /' | head -40
    warn "Apague os que você não customizou (o global já tem a versão atual)."
  fi
  if [ ! -s "$GLOBAL_MAN" ]; then
    echo ""
    warn "preset context: agents, commands e skills vêm do --global, e ele ainda não está instalado nesta máquina."
    warn "  Rode: install.sh --global --agents claude,codex,antigravity --yes"
  fi
fi

if [ -n "$INFRA_PGPASS" ]; then
  echo ""
  printf "${c_bold}local-infra criado — guarde a credencial:${c_reset}\n"
  echo "  Postgres user: dev"
  echo "  Postgres senha: ${INFRA_PGPASS}"
  echo "  (salva em ~/local-infra/.env · connection: postgresql://dev:${INFRA_PGPASS}@localhost:5432/<db>)"
fi

echo ""
printf "${c_bold}Próximos passos:${c_reset}\n"
STEP=1
step() { echo "  $STEP. $*"; STEP=$((STEP+1)); }
if [ "$SETUP_INFRA" = "1" ]; then step "Subir a infra:  cd ~/local-infra && docker compose up -d"; fi
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
if [ "$ORCA" = "1" ]; then
  step "Orca: worktree nova só leva o que está no git ou no .worktreeinclude — ponha lá o .env e afins do projeto."
fi
step "Preencha docs/agent/context.md com o stack real do projeto."
