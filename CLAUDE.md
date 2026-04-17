# buildison — contexto do projeto

Boilerplate de `.claude/` (agents, commands, skills) para projetos backend Python. Este arquivo descreve a infraestrutura local e MCPs disponíveis, de forma que qualquer projeto que herde este template já saiba o setup.

## Infraestrutura local (Docker Desktop)

Stack roda em containers do Docker Desktop, acessível via `host.docker.internal` quando o próprio consumidor está em container, ou `localhost` quando roda direto no host.

### Postgres

- Host: `host.docker.internal:5432` (de dentro de container) / `localhost:5432` (do host)
- User: `dev`
- Senha: `localdev`
- Connection string: `postgresql://dev:localdev@host.docker.internal:5432/<database>`

### Redis

- Host: `host.docker.internal:6379` (de dentro de container) / `localhost:6379` (do host)
- Sem auth local
- Connection string: `redis://host.docker.internal:6379/0`

### ngrok

- Usado para expor endpoints HTTP locais (webhooks, integrações externas) com URL pública temporária
- Sobe via docker-compose junto com o stack

### Subir / derrubar

```bash
cd ~/local-infra
docker compose up -d      # sobe Postgres + Redis + ngrok
docker compose down       # derruba tudo (mantém volumes)
docker compose logs -f    # acompanha logs
```

Para montar o `~/local-infra/docker-compose.yml` do zero, use a skill `local-infra` — ela tem o compose completo com healthchecks, volumes nomeados, tunnel do ngrok e variáveis de ambiente já definidas.

## MCPs globais disponíveis

Já configurados em `~/.claude.json` — disponíveis em qualquer projeto:

- `MCP_DOCKER` — Docker Engine, Redis, Postgres, Playwright, Context7
- `claude_ai_Supabase` — Supabase (projects, migrations, SQL, edge functions)
- `plugin_github_github` — GitHub (PRs, issues, repos)
- `plugin_context7_context7` — documentação de libs (React, Next.js, Prisma, etc)
- `plugin_chrome-devtools-mcp_chrome-devtools` — debug e automação de browser
- `claude_ai_ClickUp` — ClickUp (tasks, docs, time tracking)
- `claude_ai_Cloudflare_Developer_Platform` — Cloudflare (DNS, D1, KV, R2, Workers)
- `claude_ai_Google_Drive_2` / `claude_ai_Google_Calendar` / `claude_ai_Gmail` — Workspace
- `claude_ai_Postman` — Postman (collections, specs, mocks)

Se um projeto específico precisar de MCP extra, cria um `.mcp.json` na raiz dele — o Claude Code carrega automaticamente.

## Fluxo de carregamento

```
Abre Claude Code no projeto
        ↓
~/.claude.json                (global — MCPs)
~/.claude/settings.json       (global — permissões, plugins)
./CLAUDE.md                   (este arquivo — contexto do projeto)
./.claude/settings.json       (projeto — overrides)
./.mcp.json                   (projeto — MCPs extras, se houver)
        ↓
Claude já tem todo o contexto
```

## Estrutura deste repo

```
.claude/
├── agents/         # db, api, logic, infra, logger, security-auditor
├── commands/       # /commit, /push, /pr, /docker, /team, ...
└── skills/         # database, api, infra, logging, local-infra, ...

docs/claude-overview/  # documentação do template (visão geral, como usar)
```

Ver `README.md` para a lista completa de agents, commands e skills.
