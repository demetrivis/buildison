#!/usr/bin/env python3
"""Registra, troca de modo ou remove o MCP `qdrant-memory` nos configs dos agentes.

Absorve o antigo `switch.sh` do buildison: ele existia só pra alternar local<->vps e
foi removido quando o Qdrant saiu do instalador.

  python3 qdrant-mcp.py --mode local              # aponta pro ~/local-infra
  python3 qdrant-mcp.py --mode vps --url https://qdrant.exemplo.com
  python3 qdrant-mcp.py --remove
  python3 qdrant-mcp.py --mode local --agents claude,codex --dir /caminho/projeto

Faz backup .bak.<epoch> de todo arquivo que altera. Só mexe em config que JÁ existe,
exceto o .mcp.json do Claude, que é criado se faltar.
"""
import argparse, json, os, re, sys, time

EMBED = "sentence-transformers/all-MiniLM-L6-v2"


def die(msg):
    print(f"erro: {msg}", file=sys.stderr)
    sys.exit(1)


def backup(path):
    if os.path.exists(path):
        dst = f"{path}.bak.{int(time.time())}"
        with open(path, "rb") as a, open(dst, "wb") as b:
            b.write(a.read())
        return os.path.basename(dst)
    return None


def load_json(path):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def save_json(path, d):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")


def env_map(url, mode, collection):
    e = {"QDRANT_URL": url}
    if mode == "vps":
        # a key NUNCA vai em texto plano: expande do ambiente do shell que abre o agente
        e["QDRANT_API_KEY"] = "${QDRANT_API_KEY}"
    e["COLLECTION_NAME"] = collection
    e["EMBEDDING_MODEL"] = EMBED
    return e


def do_claude(target, env, remove):
    path = os.path.join(target, ".mcp.json")
    if remove and not os.path.exists(path):
        return None
    b = backup(path)
    d = load_json(path)
    servers = d.setdefault("mcpServers", {})
    if remove:
        servers.pop("qdrant-memory", None)
    else:
        servers["qdrant-memory"] = {"command": "uvx", "args": ["mcp-server-qdrant"], "env": env}
    save_json(path, d)
    return f".mcp.json{f' (backup {b})' if b else ' (criado)'}"


def do_opencode(target, env, remove):
    path = os.path.join(target, "opencode.json")
    if not os.path.exists(path):
        return None
    b = backup(path)
    d = load_json(path)
    mcp = d.setdefault("mcp", {})
    if remove:
        mcp.pop("qdrant-memory", None)
    else:
        mcp["qdrant-memory"] = {
            "type": "local",
            "command": ["uvx", "mcp-server-qdrant"],
            "environment": env,
            "enabled": True,
        }
    save_json(path, d)
    return f"opencode.json (backup {b})"


def do_antigravity(target, env, remove):
    """MCP de projeto vai no .agents/mcp_config.json DO PROJETO, nunca no global do Antigravity
    (~/.gemini/config/mcp_config.json): o global vale pra todo projeto aberto nele, e a coleção
    deste projeto passaria a receber a memória dos outros. Só entra se o projeto usa Antigravity."""
    agents = os.path.join(target, ".agents")
    if not os.path.isdir(agents):
        return None
    if os.path.exists(os.path.join(agents, "GERADO.md")):
        # .agents/ gerado por script do próprio projeto (ex.: pnpm sync:agents, com CI checando a
        # sincronia): escrever aqui quebraria o check. A fonte é o .mcp.json — rode o gerador.
        print("antigravity: PULADO — o .agents/ é gerado pelo projeto; rode o gerador dele (ex.: pnpm sync:agents)")
        return None
    path = os.path.join(agents, "mcp_config.json")
    if remove and not os.path.exists(path):
        return None
    b = backup(path)
    d = load_json(path)
    servers = d.setdefault("mcpServers", {})
    if remove:
        servers.pop("qdrant-memory", None)
    else:
        servers["qdrant-memory"] = {"command": "uvx", "args": ["mcp-server-qdrant"], "env": env}
    save_json(path, d)
    return f".agents/mcp_config.json{f' (backup {b})' if b else ' (criado)'}"


def antigravity_global_pinned():
    """qdrant-memory preso no config GLOBAL do Antigravity (resto de instalação antiga)."""
    for c in ("~/.gemini/config/mcp_config.json", "~/.gemini/antigravity/mcp_config.json"):
        p = os.path.expanduser(c)
        if "qdrant-memory" in (load_json(p).get("mcpServers") or {}):
            return c
    return None


def toml_env_line(env):
    parts = ", ".join(f'{k} = "{v}"' for k, v in env.items())
    return "env = { " + parts + " }"


def do_codex(env, remove):
    """O ~/.codex/config.toml é GLOBAL e as tabelas têm nome fixo: existe UM
    [mcp_servers.qdrant-memory] pra máquina toda, não um por projeto. Trocar a
    collection aqui troca pra todos os projetos — por isso o aviso na SKILL.md."""
    path = os.path.expanduser("~/.codex/config.toml")
    if not os.path.exists(path):
        return None
    src = open(path).read()
    hdr = re.compile(r'^[ \t]*\[[ \t]*mcp_servers[ \t]*\.[ \t]*"?qdrant-memory"?[ \t]*\]', re.M)
    if not hdr.search(src):
        if remove:
            return None
        # entra no bloco do buildison se ele existir (o instalador preserva o que acha lá);
        # senão vai pro fim do arquivo
        table = '[mcp_servers.qdrant-memory]\ncommand = "uvx"\nargs = ["mcp-server-qdrant"]\n' + toml_env_line(env) + "\n"
        b = backup(path)
        end = "# <<< buildison <<<"
        if end in src:
            out = src.replace(end, "\n" + table + end, 1)
        else:
            out = src.rstrip("\n") + "\n\n" + table
        open(path, "w").write(out)
        return f"~/.codex/config.toml (backup {b})"
    # já existe: reescreve (ou remove) só essa tabela
    lines = src.split("\n")
    start = next(i for i, l in enumerate(lines) if hdr.match(l))
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if re.match(r"^[ \t]*\[", lines[i]):
            end = i
            break
    new = [] if remove else [
        "[mcp_servers.qdrant-memory]",
        'command = "uvx"',
        'args = ["mcp-server-qdrant"]',
        toml_env_line(env),
    ]
    b = backup(path)
    open(path, "w").write("\n".join(lines[:start] + new + lines[end:]))
    return f"~/.codex/config.toml (backup {b})"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["local", "vps"])
    ap.add_argument("--url", default="")
    ap.add_argument("--dir", default=os.getcwd())
    ap.add_argument("--collection", default="")
    ap.add_argument("--agents", default="claude,codex,opencode,antigravity")
    ap.add_argument("--remove", action="store_true")
    a = ap.parse_args()

    if not a.remove and not a.mode:
        die("--mode local|vps é obrigatório (ou use --remove)")
    target = os.path.abspath(a.dir)
    if not os.path.isdir(target):
        die(f"diretório inválido: {target}")

    coll = a.collection or "agent_" + (
        re.sub(r"[^a-z0-9_]", "", os.path.basename(target).lower().replace("-", "_").replace(" ", "_"))
        or "project_main"
    )
    url = a.url or ("http://localhost:6333" if a.mode == "local" else "")
    if a.mode == "vps":
        if not url:
            die("--mode vps exige --url https://qdrant.<seu-dominio>")
        if not url.startswith(("http://", "https://")):
            die(f"--url precisa do esquema (https://): recebido '{url}'")
    env = {} if a.remove else env_map(url, a.mode, coll)

    want = {x.strip() for x in a.agents.split(",") if x.strip()}
    done = []
    if "claude" in want:
        done.append(do_claude(target, env, a.remove))
    if "opencode" in want:
        done.append(do_opencode(target, env, a.remove))
    if "codex" in want:
        done.append(do_codex(env, a.remove))
    if "antigravity" in want:
        done.append(do_antigravity(target, env, a.remove))

    verb = "removido de" if a.remove else "registrado em"
    touched = [d for d in done if d]
    if not touched:
        print("nada a fazer: nenhum config de agente encontrado.")
        return
    if not a.remove:
        print(f"modo {a.mode} · {url} · collection {coll}")
    print(f"qdrant-memory {verb}:")
    for d in touched:
        print(f"  - {d}")
    g = antigravity_global_pinned() if "antigravity" in want else None
    if g:
        print(f"aviso: {g} (GLOBAL do Antigravity) tem qdrant-memory — vale em TODO projeto aberto nele e")
        print("       mistura a memória dos projetos. Tire de lá (backup antes); o deste projeto fica em .agents/.")


if __name__ == "__main__":
    main()
