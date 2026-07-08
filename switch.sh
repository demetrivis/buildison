#!/usr/bin/env bash
#
# buildison switch — troca o modo de memória (local | vps) do projeto atual,
# atualizando .mcp.json (Claude Code), opencode.json (OpenCode), o bloco Codex em
# ~/.codex/config.toml e o config global do Antigravity (~/.gemini/.../mcp_config.json).
# NÃO toca em .claude/, .agents/, AGENTS.md, CLAUDE.md, docs/agent/* nem skills —
# só nos configs de MCP. Só atualiza um agente se ele JÁ estiver configurado (não instala).
#
# Uso:
#   npx buildison switch                           # interativo
#   npx buildison switch --memory=local
#   npx buildison switch --memory=vps --qdrant-url=https://qdrant.<dom>
#   npx buildison switch --dir /caminho/projeto    # default: PWD
#
# Persiste a escolha em ~/.buildison/vps.env (como o install).
#
set -euo pipefail

c_reset='\033[0m'; c_bold='\033[1m'; c_grn='\033[32m'; c_ylw='\033[33m'; c_cyn='\033[36m'; c_red='\033[31m'
info() { printf "${c_cyn}›${c_reset} %s\n" "$*"; }
ok()   { printf "${c_grn}✓${c_reset} %s\n" "$*"; }
warn() { printf "${c_ylw}!${c_reset} %s\n" "$*"; }
die()  { printf "${c_red}✗${c_reset} %s\n" "$*" >&2; exit 1; }
HAVE_TTY=0; [ -r /dev/tty ] && HAVE_TTY=1
prompt_read() { if [ "$HAVE_TTY" -eq 1 ]; then read -r "$1" < /dev/tty || true; fi; }

TARGET_DIR=""
MEMORY_MODE=""
QDRANT_URL_OPT=""
ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)          TARGET_DIR="${2:-}"; shift 2;;
    --memory)       MEMORY_MODE="${2:-}"; shift 2;;
    --memory=*)     MEMORY_MODE="${1#*=}"; shift;;
    --qdrant-url)   QDRANT_URL_OPT="${2:-}"; shift 2;;
    --qdrant-url=*) QDRANT_URL_OPT="${1#*=}"; shift;;
    --yes|-y)       ASSUME_YES=1; shift;;
    -h|--help)      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) die "Argumento desconhecido: $1 (use --help)";;
  esac
done
case "$MEMORY_MODE" in ""|local|vps) ;; *) die "--memory deve ser 'local' ou 'vps'";; esac

TARGET_DIR="${TARGET_DIR:-$PWD}"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd || die "Diretório inválido: $TARGET_DIR")"
ok "Projeto: $TARGET_DIR"

BLD_CFG="$HOME/.buildison/vps.env"
if [ -z "$MEMORY_MODE" ] || { [ "$MEMORY_MODE" = "vps" ] && [ -z "$QDRANT_URL_OPT" ]; }; then
  if [ -f "$BLD_CFG" ]; then
    # shellcheck disable=SC1090
    . "$BLD_CFG"
    [ -z "$MEMORY_MODE"    ] && [ -n "${BUILDISON_MEMORY_MODE:-}" ] && MEMORY_MODE="$BUILDISON_MEMORY_MODE"
    [ -z "$QDRANT_URL_OPT" ] && [ -n "${BUILDISON_QDRANT_URL:-}"  ] && QDRANT_URL_OPT="$BUILDISON_QDRANT_URL"
  fi
fi
if [ -z "$MEMORY_MODE" ]; then
  if [ "$ASSUME_YES" -eq 1 ]; then die "--memory é obrigatório em --yes (use local|vps)."; fi
  printf "${c_bold}Trocar para qual modo?${c_reset}\n"
  printf "  1) local — http://localhost:6333\n  2) vps — HTTPS com api-key\n"
  printf "Escolha [1]: "; prompt_read mm
  case "$mm" in 2) MEMORY_MODE="vps";; *) MEMORY_MODE="local";; esac
fi
if [ "$MEMORY_MODE" = "vps" ] && [ -z "$QDRANT_URL_OPT" ]; then
  if [ "$ASSUME_YES" -eq 1 ]; then die "--memory=vps requer --qdrant-url em --yes."; fi
  printf "URL do Qdrant na VPS (ex: https://qdrant.seu-dominio.com): "; prompt_read u
  [ -z "$u" ] && die "URL vazia."
  QDRANT_URL_OPT="$u"
fi

PROJ_NAME="$(basename "$TARGET_DIR" | tr '[:upper:] -' '[:lower:]__' | tr -cd 'a-z0-9_')"
COLLECTION="agent_${PROJ_NAME:-project_main}"
EMBED="sentence-transformers/all-MiniLM-L6-v2"
QDRANT_URL="http://localhost:6333"; [ "$MEMORY_MODE" = "vps" ] && QDRANT_URL="$QDRANT_URL_OPT"
info "Modo: $MEMORY_MODE · URL: $QDRANT_URL · collection: $COLLECTION"

# persiste a escolha per-máquina
mkdir -p "$(dirname "$BLD_CFG")"
cat > "$BLD_CFG" <<EOF
BUILDISON_MEMORY_MODE=$MEMORY_MODE
BUILDISON_QDRANT_URL=${QDRANT_URL_OPT}
EOF

# ----- Claude Code (.mcp.json) -----
MCP="$TARGET_DIR/.mcp.json"
if [ -f "$MCP" ]; then
  cp "$MCP" "$MCP.bak.$(date +%s 2>/dev/null || echo bak)" 2>/dev/null || true
  if [ "$MEMORY_MODE" = "vps" ]; then
    QENV="{ \"QDRANT_URL\": \"${QDRANT_URL}\", \"QDRANT_API_KEY\": \"\${QDRANT_API_KEY}\", \"COLLECTION_NAME\": \"${COLLECTION}\", \"EMBEDDING_MODEL\": \"${EMBED}\" }"
  else
    QENV="{ \"QDRANT_URL\": \"${QDRANT_URL}\", \"COLLECTION_NAME\": \"${COLLECTION}\", \"EMBEDDING_MODEL\": \"${EMBED}\" }"
  fi
  # substitui o bloco env do qdrant-memory usando python (parse JSON real, sem regex frágil)
  python3 - "$MCP" "$QENV" <<'PY'
import json, sys
path, qenv = sys.argv[1], sys.argv[2]
d = json.load(open(path))
servers = d.setdefault("mcpServers", {})
qm = servers.setdefault("qdrant-memory", {"command":"uvx","args":["mcp-server-qdrant"]})
qm["env"] = json.loads(qenv)
with open(path, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
  ok ".mcp.json atualizado (backup em .mcp.json.bak.*)"
else
  warn ".mcp.json não existe neste projeto — rode 'npx buildison install' primeiro."
fi

# ----- OpenCode (opencode.json) -----
OC="$TARGET_DIR/opencode.json"
if [ -f "$OC" ]; then
  cp "$OC" "$OC.bak.$(date +%s 2>/dev/null || echo bak)" 2>/dev/null || true
  if [ "$MEMORY_MODE" = "vps" ]; then
    QENV="{ \"QDRANT_URL\": \"${QDRANT_URL}\", \"QDRANT_API_KEY\": \"\${QDRANT_API_KEY}\", \"COLLECTION_NAME\": \"${COLLECTION}\", \"EMBEDDING_MODEL\": \"${EMBED}\" }"
  else
    QENV="{ \"QDRANT_URL\": \"${QDRANT_URL}\", \"COLLECTION_NAME\": \"${COLLECTION}\", \"EMBEDDING_MODEL\": \"${EMBED}\" }"
  fi
  python3 - "$OC" "$QENV" <<'PY'
import json, sys
path, qenv = sys.argv[1], sys.argv[2]
d = json.load(open(path))
mcp = d.setdefault("mcp", {})
qm = mcp.setdefault("qdrant-memory", {"type":"local","command":["uvx","mcp-server-qdrant"],"enabled":True})
qm["environment"] = json.loads(qenv)
with open(path, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
  ok "opencode.json atualizado"
fi

# ----- Codex (bloco no ~/.codex/config.toml) -----
CODEX="$HOME/.codex/config.toml"
if [ -f "$CODEX" ] && grep -qE "^# >>> buildison \(${PROJ_NAME}\) >>>" "$CODEX"; then
  cp "$CODEX" "$CODEX.bak.$(date +%s 2>/dev/null || echo bak)" 2>/dev/null || true
  if [ "$MEMORY_MODE" = "vps" ]; then
    QLINE="env = { QDRANT_URL = \"${QDRANT_URL}\", QDRANT_API_KEY = \"\${QDRANT_API_KEY}\", COLLECTION_NAME = \"${COLLECTION}\", EMBEDDING_MODEL = \"${EMBED}\" }"
  else
    QLINE="env = { QDRANT_URL = \"${QDRANT_URL}\", COLLECTION_NAME = \"${COLLECTION}\", EMBEDDING_MODEL = \"${EMBED}\" }"
  fi
  # reescreve apenas a linha env do bloco buildison(<proj>) entre os marcadores >>> e <<<
  python3 - "$CODEX" "$PROJ_NAME" "$QLINE" <<'PY'
import sys, re
path, proj, qline = sys.argv[1], sys.argv[2], sys.argv[3]
txt = open(path).read()
begin = f"# >>> buildison ({proj}) >>>"
end   = f"# <<< buildison ({proj}) <<<"
m = re.search(re.escape(begin) + r".*?" + re.escape(end), txt, re.S)
if not m:
    sys.exit(0)
block = m.group(0)
# Substitui APENAS a env line dentro do sub-bloco [mcp_servers.qdrant-memory]
def repl_section(b):
    out, in_q = [], False
    for line in b.splitlines():
        if line.strip() == "[mcp_servers.qdrant-memory]":
            in_q = True; out.append(line); continue
        if in_q and line.startswith("[") and "qdrant-memory" not in line:
            in_q = False
        if in_q and line.startswith("env"):
            out.append(qline); continue
        out.append(line)
    return "\n".join(out)
new_block = repl_section(block)
open(path, "w").write(txt.replace(block, new_block))
PY
  ok "Codex (bloco $PROJ_NAME) atualizado"
fi

# ----- Antigravity (config global ~/.gemini/.../mcp_config.json) -----
# Só atualiza se JÁ houver as chaves do buildison (não instala aqui). Config global e sem CWD:
# re-aponta as 3 chaves pra ESTE projeto (caminho absoluto + collection) e aplica o modo.
AG_CFG=""
for c in "$HOME/.gemini/config/mcp_config.json" "$HOME/.gemini/antigravity/mcp_config.json"; do
  [ -f "$c" ] && { AG_CFG="$c"; break; }
done
if [ -n "$AG_CFG" ] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d,dict) and 'qdrant-memory' in d.get('mcpServers',{}) else 1)" "$AG_CFG" 2>/dev/null; then
  cp "$AG_CFG" "$AG_CFG.bak.$(date +%s 2>/dev/null || echo bak)" 2>/dev/null || true
  python3 - "$AG_CFG" "$TARGET_DIR" "$QDRANT_URL" "$COLLECTION" "$EMBED" "$MEMORY_MODE" <<'PY'
import json, sys
path, proj, qurl, coll, embed, mode = sys.argv[1:7]
d = json.load(open(path))
servers = d.setdefault("mcpServers", {})
env = {"QDRANT_URL": qurl}
if mode == "vps":
    env["QDRANT_API_KEY"] = "${QDRANT_API_KEY}"
env["COLLECTION_NAME"] = coll
env["EMBEDDING_MODEL"] = embed
servers["spec-workflow"] = {"command": "npx", "args": ["-y", "@pimzino/spec-workflow-mcp@latest", proj]}
servers["serena"] = {"command": "serena", "args": ["start-mcp-server", "--context", "ide-assistant", "--project", proj]}
servers["qdrant-memory"] = {"command": "uvx", "args": ["mcp-server-qdrant"], "env": env}
with open(path, "w") as f:
    json.dump(d, f, indent=2); f.write("\n")
PY
  ok "Antigravity ($AG_CFG) atualizado"
fi

echo ""
ok "Switch concluído: modo $MEMORY_MODE"
if [ "$MEMORY_MODE" = "vps" ]; then
  echo ""
  printf "${c_bold}Importante:${c_reset} o .mcp.json usa \${QDRANT_API_KEY} (lido do AMBIENTE do shell)."
  echo ""
  echo "  Exporte a key (uma vez) antes de abrir o Claude:"
  echo "    export QDRANT_API_KEY=<sua-key>           # por sessão"
  echo "    echo 'export QDRANT_API_KEY=<sua-key>' >> ~/.zshrc   # persistente"
fi
echo ""
echo "Reinicie o Claude Code pra ele reler o .mcp.json (no Codex/OpenCode também)."
