#!/usr/bin/env bash
#
# buildison installer — instala a toolbox de agentes (single source -> glue nativo por agente)
#
# Uso:
#   ./install.sh                          # interativo, instala no diretório atual
#   ./install.sh --dir ~/code/meu-projeto # escolhe o destino
#   ./install.sh --agents claude,codex,opencode --yes
#   curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash
#
# Agentes suportados: claude, codex, opencode
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

# ---------- args ----------
TARGET_DIR=""
AGENTS_CSV=""
ASSUME_YES=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)    TARGET_DIR="${2:-}"; shift 2;;
    --agents) AGENTS_CSV="${2:-}"; shift 2;;
    --yes|-y) ASSUME_YES=1; shift;;
    --force)  FORCE=1; shift;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) die "Argumento desconhecido: $1 (use --help)";;
  esac
done

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
    printf "Diretório do projeto [%s]: " "$PWD"; read -r ans || true
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
  printf "Escolha (ex: 1,2 ou 4): "; read -r sel || true
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

# nome da collection do Qdrant derivado do projeto
PROJ_NAME="$(basename "$TARGET_DIR" | tr '[:upper:] -' '[:lower:]__' | tr -cd 'a-z0-9_')"
COLLECTION="agent_${PROJ_NAME:-project_main}"
EMBED="sentence-transformers/all-MiniLM-L6-v2"
info "Collection Qdrant: ${COLLECTION}"

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
EOF
  ok "CLAUDE.md"
  cat > "$TARGET_DIR/.mcp.json" <<EOF
{
  "mcpServers": {
    "spec-workflow": { "command": "npx", "args": ["-y", "@pimzino/spec-workflow-mcp@latest", "."] },
    "serena": { "command": "serena", "args": ["start-mcp-server", "--context", "claude-code", "--project", "."] },
    "qdrant-memory": {
      "command": "uvx",
      "args": ["mcp-server-qdrant"],
      "env": { "QDRANT_URL": "http://localhost:6333", "COLLECTION_NAME": "${COLLECTION}", "EMBEDDING_MODEL": "${EMBED}" }
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
      echo "env = { QDRANT_URL = \"http://localhost:6333\", COLLECTION_NAME = \"${COLLECTION}\", EMBEDDING_MODEL = \"${EMBED}\" }"
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
  read -r -d '' OC_JSON <<EOF || true
{
  "\$schema": "https://opencode.ai/config.json",
  "mcp": {
    "spec-workflow": { "type": "local", "command": ["npx", "-y", "@pimzino/spec-workflow-mcp@latest", "."], "enabled": true },
    "serena": { "type": "local", "command": ["serena", "start-mcp-server", "--context", "ide", "--project-from-cwd"], "enabled": true },
    "qdrant-memory": {
      "type": "local",
      "command": ["uvx", "mcp-server-qdrant"],
      "environment": { "QDRANT_URL": "http://localhost:6333", "COLLECTION_NAME": "${COLLECTION}", "EMBEDDING_MODEL": "${EMBED}" },
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

# ---------- resumo ----------
echo ""
ok "Instalação concluída em $TARGET_DIR"
echo ""
printf "${c_bold}Próximos passos:${c_reset}\n"
echo "  1. Infra:   cd ~/local-infra && docker compose up -d   (Qdrant precisa estar no ar)"
echo "  2. Serena:  uv tool install -p 3.13 serena-agent && serena init"
[ "$SEL_CLAUDE" -eq 1 ]   && echo "  3. Claude:  abra o projeto e rode /mcp para aprovar os servidores"
[ "$SEL_CODEX" -eq 1 ]    && echo "  3. Codex:   abra o projeto (lê AGENTS.md); MCP já está em ~/.codex/config.toml"
[ "$SEL_OPENCODE" -eq 1 ] && echo "  3. OpenCode: abra o projeto (lê AGENTS.md + opencode.json)"
echo "  4. Preencha docs/agent/context.md com o stack real do projeto."
