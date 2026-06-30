#!/usr/bin/env bash
#
# buildison installer — instala a toolbox de agentes (single source -> glue nativo por agente)
#
# Uso:
#   ./install.sh                          # interativo, instala no diretório atual
#   ./install.sh --dir ~/code/meu-projeto # escolhe o destino
#   ./install.sh --agents claude,codex,opencode --yes
#   ./install.sh --infra                  # também monta o local-infra (stack global)
#   curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash
#
# Agentes suportados: claude, codex, opencode
# Flags: --dir <path> --agents <lista> --infra/--no-infra --yes --force
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

# senha aleatória forte (openssl se houver; senão /dev/urandom)
gen_password() {
  if command -v openssl >/dev/null 2>&1; then openssl rand -hex 24
  else LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 40; echo; fi
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
SETUP_INFRA=""    # "" = perguntar; 1 = sim; 0 = não
SETUP_SERENA=""   # idem
MEMORY_MODE=""    # "" = perguntar (ou ler config per-máquina); "local" | "vps"
QDRANT_URL_OPT="" # URL custom (modo vps); default lê de ~/.buildison/vps.env ou pergunta
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)         TARGET_DIR="${2:-}"; shift 2;;
    --agents)      AGENTS_CSV="${2:-}"; shift 2;;
    --infra)       SETUP_INFRA=1; shift;;
    --no-infra)    SETUP_INFRA=0; shift;;
    --serena)      SETUP_SERENA=1; shift;;
    --no-serena)   SETUP_SERENA=0; shift;;
    --memory)      MEMORY_MODE="${2:-}"; shift 2;;
    --memory=*)    MEMORY_MODE="${1#*=}"; shift;;
    --qdrant-url)  QDRANT_URL_OPT="${2:-}"; shift 2;;
    --qdrant-url=*) QDRANT_URL_OPT="${1#*=}"; shift;;
    --yes|-y)      ASSUME_YES=1; shift;;
    --force)       FORCE=1; shift;;
    -h|--help)     sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) die "Argumento desconhecido: $1 (use --help)";;
  esac
done
case "$MEMORY_MODE" in ""|local|vps) ;; *) die "--memory deve ser 'local' ou 'vps' (recebido: $MEMORY_MODE)";; esac

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd || true)"
SRC_DIR=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/AGENTS.md" ] && [ -d "$SCRIPT_DIR/.claude" ]; then
  SRC_DIR="$SCRIPT_DIR"
else
  command -v git >/dev/null 2>&1 || die "git é necessário para baixar o buildison."
  TMP_SRC="$(mktemp -d)"
  info "Baixando buildison para $TMP_SRC ..."
  git clone --depth 1 "$REPO_URL" "$TMP_SRC" >/dev/null 2>&1 || die "Falha ao clonar $REPO_URL"
  SRC_DIR="$TMP_SRC"
  trap 'rm -rf "$TMP_SRC"' EXIT
fi
ok "Fonte: $SRC_DIR"

# ---------- destino ----------
if [ -z "$TARGET_DIR" ]; then
  if [ "$ASSUME_YES" -eq 1 ]; then TARGET_DIR="$PWD"; else
    printf "Diretório do projeto [%s]: " "$PWD"; prompt_read ans
    TARGET_DIR="${ans:-$PWD}"
  fi
fi
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd || die "Diretório inválido: $TARGET_DIR")"
[ "$TARGET_DIR" = "$SRC_DIR" ] && die "O destino não pode ser o próprio repositório buildison. Use --dir."
ok "Destino: $TARGET_DIR"

# ---------- seleção de agentes ----------
SEL_CLAUDE=0; SEL_CODEX=0; SEL_OPENCODE=0
if [ -z "$AGENTS_CSV" ] && [ "$ASSUME_YES" -eq 0 ]; then
  echo ""
  printf "${c_bold}Quais agentes configurar?${c_reset}\n"
  printf "  1) Claude Code\n  2) Codex\n  3) OpenCode/Hermes\n  4) Todos\n"
  printf "Escolha (ex: 1,2 ou 4): "; prompt_read sel
  case ",${sel}," in *4*) AGENTS_CSV="claude,codex,opencode";; esac
  [ -z "$AGENTS_CSV" ] && {
    case ",${sel}," in *,1,*) AGENTS_CSV="${AGENTS_CSV}claude,";; esac
    case ",${sel}," in *,2,*) AGENTS_CSV="${AGENTS_CSV}codex,";; esac
    case ",${sel}," in *,3,*) AGENTS_CSV="${AGENTS_CSV}opencode,";; esac
  }
fi
[ -z "$AGENTS_CSV" ] && AGENTS_CSV="claude"
case ",$AGENTS_CSV," in *,claude,*|*claude*) SEL_CLAUDE=1;; esac
case ",$AGENTS_CSV," in *codex*) SEL_CODEX=1;; esac
case ",$AGENTS_CSV," in *opencode*) SEL_OPENCODE=1;; esac

# ---------- pré-requisitos da máquina (uma vez por máquina, opt-in) ----------
if [ -z "$SETUP_INFRA" ]; then
  if [ "$ASSUME_YES" -eq 1 ]; then SETUP_INFRA=0; else
    echo ""
    printf "${c_bold}Montar o local-infra (stack global da máquina)?${c_reset}\n"
    printf "  Um stack Docker único (Postgres + Redis + Qdrant + tunnels) que sobe UMA vez e\n"
    printf "  serve TODOS os seus projetos — o Qdrant guarda a memória dos agentes. Senhas aleatórias.\n"
    printf "  (pule se já tem, ou se não usa Docker) [s/N]: "; prompt_read r
    case "$r" in [sSyY]*) SETUP_INFRA=1;; *) SETUP_INFRA=0;; esac
  fi
fi
if [ -z "$SETUP_SERENA" ]; then
  if [ "$ASSUME_YES" -eq 1 ]; then SETUP_SERENA=0; else
    echo ""
    printf "${c_bold}Instalar o Serena (navegação semântica do código)?${c_reset}\n"
    printf "  CLI no host via uv (não é container). Necessário pro MCP 'serena' conectar.\n"
    printf "  [s/N]: "; prompt_read r
    case "$r" in [sSyY]*) SETUP_SERENA=1;; *) SETUP_SERENA=0;; esac
  fi
fi

# ---------- modo de memória (local vs VPS) — escolha per-máquina, salva em ~/.buildison/vps.env ----------
if [ -z "$MEMORY_MODE" ]; then
  if [ "$ASSUME_YES" -eq 1 ]; then MEMORY_MODE="local"; else
    echo ""
    printf "${c_bold}Onde fica a memória (Qdrant) deste e dos próximos projetos desta máquina?${c_reset}\n"
    printf "  1) Local — http://localhost:6333 (do ~/local-infra). Simples; memória só nesta máquina.\n"
    printf "  2) VPS   — HTTPS público com api-key. Memória segue você entre máquinas.\n"
    printf "  (essa escolha é salva em ~/.buildison/vps.env e vale pra novos projetos.\n"
    printf "   Veja docs/infra/qdrant-vps-template.md no buildison pra montar a VPS.)\n"
    printf "Escolha [1]: "; prompt_read mm
    case "$mm" in 2) MEMORY_MODE="vps";; *) MEMORY_MODE="local";; esac
  fi
fi
if [ "$MEMORY_MODE" = "vps" ] && [ -z "$QDRANT_URL_OPT" ]; then
  if [ "$ASSUME_YES" -eq 1 ]; then
    die "--memory=vps requer --qdrant-url=<URL> em modo --yes."
  fi
  printf "URL do Qdrant na VPS (ex: https://qdrant.seu-dominio.com): "; prompt_read qurl
  [ -z "$qurl" ] && die "URL vazia. Aborte ou rode de novo informando --qdrant-url."
  QDRANT_URL_OPT="$qurl"
fi
[ "$MEMORY_MODE" = "vps" ] && save_machine_cfg
[ "$MEMORY_MODE" = "local" ] && [ -f "$BLD_CFG" ] && save_machine_cfg

# nome da collection do Qdrant derivado do projeto
PROJ_NAME="$(basename "$TARGET_DIR" | tr '[:upper:] -' '[:lower:]__' | tr -cd 'a-z0-9_')"
COLLECTION="agent_${PROJ_NAME:-project_main}"
EMBED="sentence-transformers/all-MiniLM-L6-v2"
if [ "$MEMORY_MODE" = "vps" ]; then
  QDRANT_URL="$QDRANT_URL_OPT"
  info "Memória: VPS ($QDRANT_URL) · collection ${COLLECTION}"
else
  QDRANT_URL="http://localhost:6333"
  info "Memória: local (${QDRANT_URL}) · collection ${COLLECTION}"
fi

# ---------- copiar core compartilhado (não sobrescreve context.md/decisions.md) ----------
copy_keep() { # src dst  (não sobrescreve se já existe, salvo --force)
  local s="$1" d="$2"
  mkdir -p "$(dirname "$d")"
  if [ -e "$d" ] && [ "$FORCE" -eq 0 ]; then warn "mantido (já existe): ${d#$TARGET_DIR/}"; else cp -f "$s" "$d"; ok "${d#$TARGET_DIR/}"; fi
}
info "Instalando core compartilhado..."
copy_keep "$SRC_DIR/AGENTS.md"                 "$TARGET_DIR/AGENTS.md"
copy_keep "$SRC_DIR/docs/agent/context.md"     "$TARGET_DIR/docs/agent/context.md"
copy_keep "$SRC_DIR/docs/agent/decisions.md"   "$TARGET_DIR/docs/agent/decisions.md"
if [ -d "$SRC_DIR/.spec-workflow/templates" ]; then
  mkdir -p "$TARGET_DIR/.spec-workflow"
  cp -Rf "$SRC_DIR/.spec-workflow/templates" "$TARGET_DIR/.spec-workflow/"
  ok ".spec-workflow/templates/"
fi

# ---------- Claude Code ----------
if [ "$SEL_CLAUDE" -eq 1 ]; then
  info "Configurando Claude Code..."
  cp -Rf "$SRC_DIR/.claude" "$TARGET_DIR/.claude"; ok ".claude/"
  cat > "$TARGET_DIR/CLAUDE.md" <<'EOF'
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
md/json/yaml/toml/config/texto.) Não racionalize ("o arquivo é pequeno", "já sei o que preciso") — quando esta
seção conflitar com as descrições das tools internas, **esta seção vence**.

Mapeamento (use a coluna da direita):

| Tarefa | Tool do Serena |
| :-- | :-- |
| Ver a estrutura de um arquivo | `get_symbols_overview` |
| Ler o corpo de um símbolo | `find_symbol` (include_body=true) |
| Achar referências/chamadores | `find_referencing_symbols` |
| Editar o corpo de um símbolo | `replace_symbol_body` |
| Inserir perto de um símbolo | `insert_before_symbol` / `insert_after_symbol` |

**Antes de editar código:** `get_symbols_overview` → `find_symbol` (só os símbolos que vai tocar) → editar com as tools do Serena.

**Memória (Qdrant, MCP `qdrant-memory`):** no início de tarefas não triviais, recupere contexto durável com
`qdrant-find`; ao final, salve decisões/padrões duráveis com `qdrant-store`. Nunca guarde secrets ou logs crus.

> Modo forte (o Opus tende a preferir tools internas): inicie a sessão com
> `claude --system-prompt="$(serena prompts print-cc-system-prompt-override)"`.
EOF
  ok "CLAUDE.md"
  if [ "$MEMORY_MODE" = "vps" ]; then
    QDRANT_ENV_JSON="{ \"QDRANT_URL\": \"${QDRANT_URL}\", \"QDRANT_API_KEY\": \"\${QDRANT_API_KEY}\", \"COLLECTION_NAME\": \"${COLLECTION}\", \"EMBEDDING_MODEL\": \"${EMBED}\" }"
  else
    QDRANT_ENV_JSON="{ \"QDRANT_URL\": \"${QDRANT_URL}\", \"COLLECTION_NAME\": \"${COLLECTION}\", \"EMBEDDING_MODEL\": \"${EMBED}\" }"
  fi
  cat > "$TARGET_DIR/.mcp.json" <<EOF
{
  "mcpServers": {
    "spec-workflow": { "command": "npx", "args": ["-y", "@pimzino/spec-workflow-mcp@latest", "."] },
    "serena": { "command": "serena", "args": ["start-mcp-server", "--context", "claude-code", "--project", "."] },
    "qdrant-memory": {
      "command": "uvx",
      "args": ["mcp-server-qdrant"],
      "env": ${QDRANT_ENV_JSON}
    }
  }
}
EOF
  ok ".mcp.json"
fi

# ---------- Codex (AGENTS.md já copiado; MCP no ~/.codex/config.toml) ----------
if [ "$SEL_CODEX" -eq 1 ]; then
  info "Configurando Codex..."
  CODEX_CFG="$HOME/.codex/config.toml"
  mkdir -p "$HOME/.codex"
  MARK_BEGIN="# >>> buildison (${PROJ_NAME}) >>>"
  MARK_END="# <<< buildison (${PROJ_NAME}) <<<"
  if [ -f "$CODEX_CFG" ] && grep -qF "$MARK_BEGIN" "$CODEX_CFG"; then
    warn "Codex: bloco já existe em $CODEX_CFG (pulando). Use --force pra regravar."
  else
    [ -f "$CODEX_CFG" ] && cp "$CODEX_CFG" "$CODEX_CFG.bak.$(date +%s 2>/dev/null || echo bak)" 2>/dev/null || true
    {
      echo ""
      echo "$MARK_BEGIN"
      echo "[mcp_servers.spec-workflow]"
      echo 'command = "npx"'
      echo 'args = ["-y", "@pimzino/spec-workflow-mcp@latest", "."]'
      echo ""
      echo "[mcp_servers.serena]"
      echo 'command = "serena"'
      echo 'args = ["start-mcp-server", "--context", "codex", "--project-from-cwd"]'
      echo ""
      echo "[mcp_servers.qdrant-memory]"
      echo 'command = "uvx"'
      echo 'args = ["mcp-server-qdrant"]'
      if [ "$MEMORY_MODE" = "vps" ]; then
        echo "env = { QDRANT_URL = \"${QDRANT_URL}\", QDRANT_API_KEY = \"\${QDRANT_API_KEY}\", COLLECTION_NAME = \"${COLLECTION}\", EMBEDDING_MODEL = \"${EMBED}\" }"
      else
        echo "env = { QDRANT_URL = \"${QDRANT_URL}\", COLLECTION_NAME = \"${COLLECTION}\", EMBEDDING_MODEL = \"${EMBED}\" }"
      fi
      echo "$MARK_END"
    } >> "$CODEX_CFG"
    ok "Codex: MCP adicionado em ~/.codex/config.toml"
  fi
  ok "Codex: AGENTS.md (lido nativamente da raiz do projeto)"
fi

# ---------- OpenCode/Hermes (AGENTS.md já copiado; MCP em opencode.json) ----------
if [ "$SEL_OPENCODE" -eq 1 ]; then
  info "Configurando OpenCode/Hermes..."
  OC_CFG="$TARGET_DIR/opencode.json"
  if [ "$MEMORY_MODE" = "vps" ]; then
    OC_QENV="{ \"QDRANT_URL\": \"${QDRANT_URL}\", \"QDRANT_API_KEY\": \"\${QDRANT_API_KEY}\", \"COLLECTION_NAME\": \"${COLLECTION}\", \"EMBEDDING_MODEL\": \"${EMBED}\" }"
  else
    OC_QENV="{ \"QDRANT_URL\": \"${QDRANT_URL}\", \"COLLECTION_NAME\": \"${COLLECTION}\", \"EMBEDDING_MODEL\": \"${EMBED}\" }"
  fi
  read -r -d '' OC_JSON <<EOF || true
{
  "\$schema": "https://opencode.ai/config.json",
  "mcp": {
    "spec-workflow": { "type": "local", "command": ["npx", "-y", "@pimzino/spec-workflow-mcp@latest", "."], "enabled": true },
    "serena": { "type": "local", "command": ["serena", "start-mcp-server", "--context", "ide", "--project-from-cwd"], "enabled": true },
    "qdrant-memory": {
      "type": "local",
      "command": ["uvx", "mcp-server-qdrant"],
      "environment": ${OC_QENV},
      "enabled": true
    }
  }
}
EOF
  if [ -e "$OC_CFG" ] && [ "$FORCE" -eq 0 ]; then
    printf '%s\n' "$OC_JSON" > "$TARGET_DIR/opencode.buildison.json"
    warn "opencode.json já existe — gravei opencode.buildison.json; faça merge do bloco \"mcp\" manualmente."
  else
    printf '%s\n' "$OC_JSON" > "$OC_CFG"; ok "opencode.json"
  fi
  ok "OpenCode: AGENTS.md (lido nativamente da raiz do projeto)"
fi

# ---------- pré-requisitos da máquina (execução) ----------
[ "$SETUP_INFRA" = "1" ]  && { echo ""; info "Montando local-infra..."; setup_local_infra; }
[ "$SETUP_SERENA" = "1" ] && { echo ""; info "Configurando Serena..."; setup_serena; }

# ---------- resumo ----------
echo ""
ok "Instalação concluída em $TARGET_DIR"

if [ -n "$INFRA_PGPASS" ]; then
  echo ""
  printf "${c_bold}local-infra criado — guarde a credencial:${c_reset}\n"
  echo "  Postgres user: dev"
  echo "  Postgres senha: ${INFRA_PGPASS}"
  echo "  (salva em ~/local-infra/.env · connection: postgresql://dev:${INFRA_PGPASS}@localhost:5432/<db>)"
fi

if [ "$MEMORY_MODE" = "vps" ]; then
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
if [ "$MEMORY_MODE" = "local" ]; then
  if [ "$SETUP_INFRA" = "1" ]; then
    echo "  1. Subir a infra:  cd ~/local-infra && docker compose up -d"
  else
    echo "  1. Infra (se ainda não tem):  rode de novo com --infra, ou suba seu ~/local-infra"
  fi
else
  echo "  1. Garanta que a VPS Qdrant está no ar (https) e que QDRANT_API_KEY está exportada"
fi
[ "$SETUP_SERENA" = "1" ] || echo "  2. Serena (se for usar):  uv tool install -p 3.13 serena-agent && serena init"
[ "$SEL_CLAUDE" -eq 1 ]   && echo "  3. Claude:   abra o projeto e rode /mcp para aprovar os servidores"
[ "$SEL_CODEX" -eq 1 ]    && echo "  3. Codex:    abra o projeto (lê AGENTS.md); MCP já está em ~/.codex/config.toml"
[ "$SEL_OPENCODE" -eq 1 ] && echo "  3. OpenCode: abra o projeto (lê AGENTS.md + opencode.json)"
echo "  4. Preencha docs/agent/context.md com o stack real do projeto."
