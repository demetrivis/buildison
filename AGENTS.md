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

<!-- bld:if source -->
> **Nota da fonte (não vai para o projeto):** os blocos `<!-- bld:if X -->` … `<!-- bld:end -->` são filtrados
> pelo instalador conforme o que foi instalado — `spec`, `serena`, `memory`, `mcp` (algum MCP) e `infra`;
> `!X` inverte. No projeto instalado sobra só o texto do que existe lá.
<!-- bld:end -->

## Sobre este projeto

Este repositório é construído sobre o boilerplate **buildison** (agents, commands, skills em `.claude/`).

**Antes de implementar qualquer coisa, leia [`docs/agent/context.md`](docs/agent/context.md)** — é onde mora o
conhecimento vivo do projeto: overview, stack real, comandos, arquitetura e convenções específicas.
**Mantenha esse arquivo atualizado** sempre que o stack ou a arquitetura mudarem. Aqui (AGENTS.md) ficam só as
regras permanentes; lá fica o que muda.

<!-- bld:if infra -->
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
<!-- bld:end -->

<!-- bld:if memory -->
## Memória dos agentes (Qdrant)

Dois modos, escolha **uma vez por máquina** no instalador (`--memory=local|vps`,
salvo em `~/.buildison/vps.env`):

- **Local** (default): REST `http://localhost:6333` (sobe com o `~/local-infra`) · gRPC `6334` · sem auth · dashboard em `http://localhost:6333/dashboard`. Simples; memória só nesta máquina.
- **VPS**: `https://qdrant.<seu-dominio>` com header `api-key`. Memória **segue você entre máquinas**. Setup em `docs/infra/qdrant-vps-template.md`.

Em ambos: 1 instância Qdrant, **uma collection por projeto** (ex.: `agent_<projeto>`).
Acesso via MCP `qdrant-memory`; convenções na skill `agent-memory`. Sem replicação automática
entre local e VPS — escolha uma como fonte de verdade.
<!-- bld:end -->

<!-- bld:if mcp -->
## Toolbox de agentes (MCP)

Config dos MCPs: [`.mcp.json`](.mcp.json) (Claude Code) · `~/.codex/config.toml` (Codex) · `opencode.json` (OpenCode).

<!-- bld:if spec -->
- **SpecWorkflow** — planejamento: requirements → design → tasks. MCP `spec-workflow` · skill `spec-workflow`.
  Nada a instalar (roda via `npx`, stdio). Templates em `.spec-workflow/templates/`.
<!-- bld:end -->
<!-- bld:if serena -->
- **Serena** — navegação semântica do codebase. MCP `serena`.
  Pré-requisito (uma vez por máquina): `uv tool install -p 3.13 serena-agent && serena init`.
<!-- bld:end -->
<!-- bld:if memory -->
- **Qdrant** — memória vetorial persistente, uma collection por projeto. MCP `qdrant-memory` · skill `agent-memory`.
  Roda via `uvx mcp-server-qdrant`; o Qdrant precisa estar no ar (local-infra ou VPS). Por projeto: `COLLECTION_NAME=agent_<projeto>`.
<!-- bld:end -->
- **Context7** — docs atualizadas de libs/APIs. MCP `context7` (se estiver configurado no seu agente).
<!-- bld:end -->

## Agent workflow

- **Leia este arquivo e o `docs/agent/context.md`** antes de qualquer implementação.
- Consulte `docs/agent/decisions.md` para decisões anteriores antes de mudar arquitetura.
<!-- bld:if spec -->
- Para features **não triviais**, use **SpecWorkflow** para gerar requirements → design → tasks antes de codar.
<!-- bld:end -->
<!-- bld:if !spec -->
- Para features **não triviais**, escreva primeiro um plano curto (requisitos → design → tarefas) e só então code.
<!-- bld:end -->
<!-- bld:if serena -->
- Use **Serena** para localizar símbolos/referências antes de editar módulos desconhecidos — não leia o repo inteiro às cegas.
<!-- bld:end -->
<!-- bld:if !serena -->
- Localize símbolos e referências (busca no código) antes de editar módulos desconhecidos — não leia o repo inteiro às cegas.
<!-- bld:end -->
- Use documentação atualizada (**Context7**, se disponível) para libs/APIs externas — não confie em memória de versões antigas.
<!-- bld:if memory -->
- Use **Qdrant** (`qdrant-memory`) só para recuperar/gravar **contexto durável** do projeto. Ver skill `agent-memory`.
<!-- bld:end -->
- Ao final: atualize `docs/agent/context.md` se o stack/arquitetura mudou e registre decisões em `docs/agent/decisions.md`.
<!-- bld:if memory -->
  Salve também a memória durável no Qdrant.
<!-- bld:end -->

## Coding rules

- Prefira diffs pequenos e focados.
- Não reescreva arquivos não relacionados à tarefa.
- Não adicione dependências sem justificativa.
- Não altere API pública sem registrar o impacto de compatibilidade.
- Siga as convenções das skills em `.claude/skills/` (api, database, logging, infra, etc).

## Memory policy

<!-- bld:if memory -->
Detalhes operacionais na skill `agent-memory`. Resumo:

**Guardar** (memória durável no Qdrant ou em `docs/agent/decisions.md`):
<!-- bld:end -->
<!-- bld:if !memory -->
**Guardar** (em `docs/agent/decisions.md`; o que for stack/arquitetura vai no `docs/agent/context.md`):
<!-- bld:end -->
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
