# buildison — camada Claude Code

O Claude Code não lê AGENTS.md sozinho, então este arquivo **importa as duas camadas** e adiciona o que é
específico do Claude Code:

- **`@AGENTS.md`** — regras **permanentes** da construção (toolbox, infra, memory policy). Não muda por projeto.
- **`@docs/agent/context.md`** — contexto **dinâmico** do projeto (stack, comandos, arquitetura). O agente mantém.

@AGENTS.md

@docs/agent/context.md

## MCPs globais (Claude Code, `~/.claude.json`)

Disponíveis em qualquer projeto neste cliente — **não** existem em outros agentes:

- `MCP_DOCKER` — Docker Engine, Redis, Postgres, Playwright, Context7
- `claude_ai_Supabase` — Supabase (projects, migrations, SQL, edge functions)
- `plugin_github_github` — GitHub (PRs, issues, repos)
- `plugin_context7_context7` — documentação de libs (atende o papel do "Context7" da toolbox)
- `plugin_chrome-devtools-mcp_chrome-devtools` — debug e automação de browser
- `claude_ai_ClickUp` — ClickUp (tasks, docs, time tracking)
- `claude_ai_Cloudflare_Developer_Platform` — Cloudflare (DNS, D1, KV, R2, Workers)
- `claude_ai_Google_Drive_2` / `claude_ai_Google_Calendar` / `claude_ai_Gmail` — Workspace
- `claude_ai_Postman` — Postman (collections, specs, mocks)

MCP extra por projeto: `.mcp.json` na raiz (Claude Code carrega após aprovação no primeiro `/mcp`).

## O que o Claude Code carrega no boot

```
~/.claude.json            (global — MCPs do cliente)
~/.claude/settings.json   (global — permissões, plugins)
./CLAUDE.md               (este arquivo)  ──@import──>  ./AGENTS.md  (fonte única)
./.claude/settings.json   (projeto — overrides)
./.mcp.json               (projeto — toolbox: spec-workflow, serena, qdrant-memory)
```

Carregam **sozinhos**: `CLAUDE.md` (+ o `@AGENTS.md` importado) e **descrições** de skills/agents/MCPs.
Carregam **sob demanda**: corpo das skills (quando acionadas), agents (quando spawnados),
`docs/agent/*.md` (quando lidos), schemas de MCP (quando a tool é usada).

## Estrutura deste repo

```
AGENTS.md              # PERMANENTE: regras + infra + toolbox (vem do buildison, não muda por projeto)
CLAUDE.md              # bridge Claude Code → @AGENTS.md + @docs/agent/context.md
.mcp.json              # toolbox MCP (spec-workflow, serena, qdrant-memory)
.spec-workflow/        # templates de requirements/design/tasks
.claude/               # PERMANENTE: máquina do boilerplate
├── agents/         # db, api, logic, infra, logger, security-auditor, golang, prisma, nestjs, postgrest, arq-info, arq-info-web, design-system-extractor, suporte
├── commands/       # /commit, /push, /pr, /docker, /team, ...
└── skills/         # database, api, infra, logging, local-infra, agent-memory, spec-workflow, golang, nestjs, prisma, postgrest, plano-operacao, ...
.agents/               # glue p/ Antigravity (skills + workflows), gerado de .claude/ por scripts/gen-antigravity.mjs

docs/
├── agent/            # DINÂMICO: context.md (mapa do projeto) + decisions.md (log) — o agente mantém
└── claude-overview/  # documentação do template
```

Ver `README.md` para a lista completa de agents, commands e skills.
