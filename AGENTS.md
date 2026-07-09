# AGENTS.md

> **Regras permanentes da construção (buildison).** Vem do boilerplate e **não muda por projeto** —
> evite editar aqui ao herdar o template. O que é específico do projeto (stack, comandos, arquitetura)
> vive em [`docs/agent/context.md`](docs/agent/context.md), que o agente mantém.
>
> **Fonte única, lida por todos os agentes** — Claude Code, Codex, MiniMax, Hermes/OpenCode, Cursor, Antigravity:
> - **Claude Code** lê `CLAUDE.md`, que faz `@AGENTS.md` + `@docs/agent/context.md` no boot.
> - **Demais agentes** leem `AGENTS.md` nativamente (e, por instrução abaixo, o `context.md`). O **Antigravity**
>   usa `.agents/` só para **skills + workflows** (gerado de `.claude/` por `scripts/gen-antigravity.mjs`);
>   ele **não** registra agente custom via arquivo — subagentes são orquestrados internamente.
>
> Em conflito de regra de comportamento, **este arquivo prevalece**.

## Sobre este projeto

Este repositório é construído sobre o boilerplate **buildison** (agents, commands, skills em `.claude/`).

**Antes de implementar qualquer coisa, leia [`docs/agent/context.md`](docs/agent/context.md)** — é onde mora o
conhecimento vivo do projeto: overview, stack real, comandos, arquitetura e convenções específicas.
**Mantenha esse arquivo atualizado** sempre que o stack ou a arquitetura mudarem. Aqui (AGENTS.md) ficam só as
regras permanentes; lá fica o que muda.

## Infraestrutura local (stack global)

Stack Docker Desktop **global** em `~/local-infra/` — sobe uma vez e atende **todos os projetos da máquina**.
Hostname: `host.docker.internal` (de dentro de container) / `localhost` (direto no host).
As credenciais abaixo são **exemplos de dev local** (o stack nunca é exposto além da máquina) — defina as suas no `~/local-infra/.env`.

### Postgres

- `localhost:5432` (host) / `host.docker.internal:5432` (container) · user `dev` · senha `localdev`
- Connection string: `postgresql://dev:localdev@localhost:5432/<database>`
- Um `database` por projeto (`CREATE DATABASE projeto_x OWNER dev;`)

### Redis

- `localhost:6379` (host) / `host.docker.internal:6379` (container) · sem auth
- Connection string: `redis://localhost:6379/0` — um número de DB por projeto (`/0`, `/1`, ...)

### Qdrant (memória dos agentes — dois modos)

Dois modos, escolha **uma vez por máquina** no instalador (`--memory=local|vps`,
salvo em `~/.buildison/vps.env`):

- **Local** (default): REST `http://localhost:6333` · gRPC `6334` · sem auth · dashboard em `http://localhost:6333/dashboard`. Simples; memória só nesta máquina.
- **VPS**: `https://qdrant.<seu-dominio>` com header `api-key`. Memória **segue você entre máquinas**. Setup em `docs/infra/qdrant-vps-template.md`.

Em ambos: 1 instância Qdrant, **uma collection por projeto** (ex.: `agent_<projeto>`).
Acesso via MCP `qdrant-memory`; convenções na skill `agent-memory`. Sem replicação automática
entre local e VPS — escolha uma como fonte de verdade.

### Tunnels (ngrok + cloudflared)

- **ngrok** — URL pública efêmera, só com authtoken. Teste rápido. Dashboard em `:4040`.
- **cloudflared** — tunnel nomeado, URL estável no seu domínio (roteamento no Cloudflare Zero Trust). Webhook permanente.
- Tokens no `~/local-infra/.env`.

### Subir / derrubar

```bash
cd ~/local-infra
docker compose up -d      # Postgres + Redis + Qdrant + ngrok + cloudflared
docker compose down       # derruba (mantém volumes)
```

Para montar o `~/local-infra/docker-compose.yml` do zero, use a skill `local-infra`.

## Toolbox de agentes (MCP)

Config dos MCPs do projeto: [`.mcp.json`](.mcp.json).

| Peça | Papel | Acesso |
| :--- | :--- | :--- |
| **SpecWorkflow** | Planejamento: requirements → design → tasks | MCP `spec-workflow` · skill `spec-workflow` |
| **Serena** | Navegação semântica do codebase | MCP `serena` |
| **Context7** | Docs atualizadas de libs/APIs | MCP `context7` |
| **Qdrant** | Memória vetorial persistente (collection por projeto) | MCP `qdrant-memory` · skill `agent-memory` |

**Pré-requisitos** (uma vez por máquina):

- **Serena**: `uv tool install -p 3.13 serena-agent && serena init` (o `.mcp.json` chama `serena start-mcp-server`).
- **Qdrant**: subir via `local-infra`; o MCP `qdrant-memory` roda via `uvx mcp-server-qdrant`.
- **SpecWorkflow**: nada a instalar — roda via `npx` (stdio). Templates em `.spec-workflow/templates/`.
- **Por projeto**: ajuste `COLLECTION_NAME` no `.mcp.json` para `agent_<projeto>`.

## Agent workflow

1. **Leia este arquivo e o `docs/agent/context.md`** antes de qualquer implementação.
2. Consulte `docs/agent/decisions.md` para decisões anteriores antes de mudar arquitetura.
3. Para features **não triviais**, use **SpecWorkflow** para gerar requirements → design → tasks antes de codar.
4. Use **Serena** para localizar símbolos/referências antes de editar módulos desconhecidos — não leia o repo inteiro às cegas.
5. Use **Context7** para documentação de libs/APIs externas — não confie em memória de versões antigas.
6. Use **Qdrant** (`qdrant-memory`) só para recuperar/gravar **contexto durável** do projeto. Ver `agent-memory` skill.
7. Ao final: atualize `docs/agent/context.md` se o stack/arquitetura mudou, registre decisões em `docs/agent/decisions.md` e salve memória durável no Qdrant.

## Coding rules

- Prefira diffs pequenos e focados.
- Não reescreva arquivos não relacionados à tarefa.
- Não adicione dependências sem justificativa.
- Não altere API pública sem registrar o impacto de compatibilidade.
- Siga as convenções das skills em `.claude/skills/` (api, database, logging, infra, etc).

## Memory policy

Detalhes operacionais na skill `agent-memory`. Resumo:

**Guardar** (memória durável no Qdrant ou em `docs/agent/decisions.md`):
- decisões de arquitetura e o motivo
- convenções do projeto
- bugs recorrentes e suas correções
- detalhes de integração (endpoints, contratos, quirks de terceiros)

**Nunca guardar**:
- secrets, tokens, credenciais
- dados de clientes / PII
- logs crus
- palpites temporários ou conversas inteiras sem resumo

## Security (dev local)

- Exponha serviços apenas localmente durante o dev.
- Não monte a home inteira em containers de MCP.
- Não passe `.env` de produção para containers locais.
- Não dê acesso ao Docker socket para MCPs desconhecidos.
- Trate MCPs com acesso a filesystem/shell/network como superfície de ataque.
