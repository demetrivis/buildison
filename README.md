# buildison

Boilerplate de agents, commands e skills do Claude Code para projetos backend.

> **Infra local**: este template assume um stack global de desenvolvimento em `~/local-infra/` (Postgres + Redis + Qdrant + ngrok + cloudflared via Docker Desktop) — sobe uma vez e serve todos os projetos da máquina. Credenciais e hostnames estão no [CLAUDE.md](CLAUDE.md). Para montar o stack do zero, a skill `local-infra` tem o docker-compose completo.

## O que é isso?

Uma coleção de agentes especializados, comandos prontos e skills de referência pré-configurados para o Claude Code. Clone, copie pro seu projeto e comece a trabalhar — o Claude já sabe como se organizar, dividir trabalho entre agentes e seguir as convenções do projeto.

Os agents detectam automaticamente o stack do projeto (Python, Node.js, Go, etc.) lendo o manifesto antes de qualquer ação. As skills são templates de convenções — personalize-as para o seu projeto.

## Como Usar

### Instalador (recomendado) — multi-agente

Um comando configura a toolbox no seu projeto para **Claude Code, Codex e/ou OpenCode/Hermes**, a partir de
uma fonte única (`AGENTS.md` + `.claude/` + `docs/agent/` + `.mcp.json`). Sem duplicar conteúdo: cada agente
recebe só o "glue" no formato nativo dele.

```bash
# npx direto do GitHub (não precisa de conta npm)
npx github:demetrivis/buildison install --dir . --agents claude,codex,opencode

# ou remoto via curl (clona sozinho)
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash

# ou clone + script (engine)
git clone https://github.com/demetrivis/buildison.git && cd buildison
bash install.sh --dir /caminho/do/seu/projeto
```

> No Windows, rode via **Git Bash** (`bash install.sh`), não pelo PowerShell/duplo-clique.

Sem flags, ele roda **interativo** (pergunta destino e agentes). O que cada agente recebe:

| Agente | Glue gerado |
|--------|-------------|
| Claude Code | `.claude/` + `CLAUDE.md` (`@imports`) + `.mcp.json` |
| Codex | `AGENTS.md` (nativo) + bloco MCP em `~/.codex/config.toml` |
| OpenCode/Hermes | `AGENTS.md` (nativo) + `opencode.json` |
| _(todos)_ | `AGENTS.md` + `docs/agent/context.md` + `decisions.md` |

O instalador é **idempotente**: não sobrescreve `docs/agent/context.md` (seu conhecimento do projeto) nem
duplica o bloco MCP do Codex. Use `--force` para regravar os arquivos gerados.

#### Pré-requisitos da máquina (opt-in, uma vez por máquina)

No modo interativo o instalador também pergunta se quer montar os pré-requisitos globais — ou passe as flags:

```bash
npx buildison install --dir . --agents claude --infra --serena
```

- **`--infra`** → monta o `~/local-infra/` (Postgres + Redis + Qdrant + ngrok + cloudflared) com **senha do Postgres gerada aleatoriamente** (salva em `~/local-infra/.env` e mostrada no fim). Sobe uma vez, serve todos os projetos.
- **`--serena`** → instala o Serena no host via `uv` (`uv tool install -p 3.13 serena-agent && serena init`).

Use `--no-infra` / `--no-serena` para pular sem perguntar. Depois é só `cd ~/local-infra && docker compose up -d`.

#### MCPs de banco (Postgres + Redis) — opcional, por projeto

O agente pode consultar Postgres e Redis direto. **Não vêm por padrão** (nem todo projeto usa banco) — adicione
quando precisar. Duas formas:

**Opção 1 — Standalone no config do agente** (portável: Claude, Codex, OpenCode). Os "oficiais" antigos foram
arquivados; use estes:

`.mcp.json` (Claude Code):
```jsonc
"redis":    { "command": "uvx", "args": ["redis-mcp-server@latest", "--url", "redis://localhost:6379/0"] },
"postgres": { "command": "uvx", "args": ["postgres-mcp", "--access-mode=restricted"],
              "env": { "DATABASE_URI": "postgresql://dev:<SENHA>@localhost:5432/<DATABASE>" } }
```
`~/.codex/config.toml` (Codex):
```toml
[mcp_servers.redis]
command = "uvx"
args = ["redis-mcp-server@latest", "--url", "redis://localhost:6379/0"]
[mcp_servers.postgres]
command = "uvx"
args = ["postgres-mcp", "--access-mode=restricted"]
env = { DATABASE_URI = "postgresql://dev:<SENHA>@localhost:5432/<DATABASE>" }
```
`opencode.json` (OpenCode/Hermes): mesma ideia, dentro de `"mcp"`, com `"type": "local"` e `"command": [...]`.

> `--access-mode=restricted` = só leitura/ops seguras (recomendado pro agente). Troque por `unrestricted` se precisar escrever.
> ⚠️ **Senha:** o `<SENHA>` fica no arquivo. Em repo **público**, **não** commite a senha real — use placeholder e
> preencha local, ou vá de Docker Toolkit (abaixo), que guarda o secret no Keychain.

**Opção 2 — Docker MCP Toolkit** (secret no Keychain, sem senha em arquivo; serve Claude, Codex e OpenCode):
```bash
printf '%s' "<SENHA>" | docker mcp secret set POSTGRES_PASSWORD   # secret no Keychain do OS
# habilite os servers Postgres/Redis no Docker Desktop → MCP Toolkit (ou via `docker mcp`)
docker mcp client connect claude-code     # e/ou: codex, opencode
```

### Manual (só Claude Code)

```bash
cp -r .claude/ /caminho/do/seu/projeto/
cd /caminho/do/seu/projeto && claude
```

### 4. Use os comandos

```bash
/commit     # Commit inteligente com stage seguro
/push       # Push seguro para o remote
/pr         # Criar Pull Request estruturado
/tlg        # Git log visual com graph
/team       # Montar equipe de teammates paralelos
/explore    # Explorar codebase
/logs       # Analisar logs do projeto
/docker     # Criar Dockerfiles e docker-compose
/ghaction   # Criar workflows GitHub Actions
```

## Agents Incluídos

| Agent | Descrição |
|-------|-----------|
| `db` | Supabase + PostgreSQL + Redis: schema, migrations, RLS, repositories |
| `api` | Camada HTTP: routes, schemas/DTOs, middlewares, error handling |
| `logic` | Lógica de negócio: services, validações, orquestração de processos |
| `infra` | Infraestrutura: Docker, env vars, CI/CD, decisões de arquitetura |
| `logger` | Logging estruturado: JSON, request tracing, análise de logs |
| `security-auditor` | Auditoria de segurança para APIs, database, auth |
| `golang` | Go backend: handlers, services, repositories, concorrência, testes |
| `prisma` | Prisma ORM: schema, migrations, queries, transactions, performance |
| `nestjs` | NestJS: módulos, controllers, services, DTOs, guards, Prisma |
| `postgrest` | PostgREST: APIs database-first, views, RPC, RLS, permissões |

## Commands Incluídos

| Command | Descrição |
|---------|-----------|
| `/commit` | Stage inteligente + commit com mensagem bem escrita |
| `/push` | Push seguro, cria upstream se necessário |
| `/pr` | Cria PR analisando todos os commits da branch |
| `/tlg` | Git log visual com graph de branches |
| `/git` | Operações git assistidas com safety checks |
| `/team` | Monta equipe de teammates independentes |
| `/explore` | Explora e mapeia o codebase |
| `/logs` | Analisa logs do projeto |
| `/docker` | Cria Dockerfiles multi-stage e compose (Python, Node, Go) |
| `/ghaction` | Cria workflows de GitHub Actions (detecta o stack) |
| `/portainer` | Gera stack para Portainer (Docker Swarm + Traefik + redes overlay) |

## Skills Incluídas

| Skill | Descrição |
|-------|-----------|
| `database` | Supabase, PostgreSQL, Redis, migrations, RLS, VPS connections |
| `api` | Camada HTTP: routes, schemas, error handling (template agnóstico de framework) |
| `infra` | Docker, env vars, estrutura de projeto, ADRs |
| `logging` | Logging estruturado em JSON, patterns de observabilidade |
| `golang` | Go backend: handlers, services, repositories, context, testing |
| `nestjs` | NestJS: módulos, controllers, services, DTOs, validação, Prisma |
| `prisma` | Prisma ORM: schema, migrations, client, transactions, performance |
| `postgrest` | PostgREST: APIs database-first, views, RPC, RLS, permissões |
| `cloudflare` | Cloudflare API, DNS, email routing, R2 storage |
| `seo-technical` | SEO técnico: sitemaps, meta tags, structured data |
| `favicon` | Favicon e metadata para Next.js |
| `local-infra` | Stack global Docker Desktop: Postgres + Redis + Qdrant + ngrok + cloudflared em `~/local-infra/` |
| `agent-memory` | Memória vetorial persistente via Qdrant: collections, payload, política do que guardar |
| `spec-workflow` | Planejamento estruturado: requirements → design → tasks (SpecWorkflow MCP) |

## Toolbox de agentes (memória + planejamento)

Além das skills, o template traz uma stack para dar **contexto, memória e planejamento estruturado** a agentes de código. A documentação é dividida em **permanente** (vem do boilerplate, não muda por projeto) e **dinâmica** (o agente mantém, muda por projeto):

- **`AGENTS.md`** *(permanente)* — fonte única de regras + infra + toolbox, lida por **todos** os agentes (Claude Code, Codex, MiniMax, Hermes, Cursor...). O Claude Code lê via `@import` no `CLAUDE.md`.
- **`docs/agent/context.md`** *(dinâmico)* — mapa do projeto: stack real, comandos, arquitetura. O agente atualiza conforme constrói.
- **`docs/agent/decisions.md`** *(dinâmico)* — log de decisões técnicas.
- **`.mcp.json`** — toolbox MCP: `spec-workflow` (planejamento), `serena` (navegação semântica), `qdrant-memory` (memória vetorial). Context7 já vem global.
- **Qdrant** — memória vetorial persistente, no stack `local-infra`. Convenções na skill `agent-memory`.

**Pré-requisitos** (uma vez por máquina): `uv tool install -p 3.13 serena-agent && serena init` para o Serena; `docker compose up -d` no `~/local-infra/` para o Qdrant. Detalhes no [CLAUDE.md](CLAUDE.md).

## Estrutura

```
AGENTS.md             # contrato fixo do repo para agentes
.mcp.json             # toolbox MCP (spec-workflow, serena, qdrant-memory)
.spec-workflow/       # templates de requirements/design/tasks
.claude/
├── settings.json
├── agents/
│   ├── db.md
│   ├── api.md
│   ├── logic.md
│   ├── infra.md
│   ├── logger.md
│   └── security-auditor.md
├── commands/
│   ├── commit.md
│   ├── push.md
│   ├── pr.md
│   ├── tlg.md
│   ├── git.md
│   ├── team.md
│   ├── explore.md
│   ├── logs.md
│   ├── docker.md
│   └── ghaction.md
└── skills/
    ├── database/
    ├── api/
    ├── infra/
    ├── logging/
    ├── local-infra/
    ├── agent-memory/     # memória vetorial (Qdrant)
    ├── spec-workflow/    # planejamento estruturado
    ├── cloudflare/
    ├── seo-technical/
    └── favicon/

AGENTS.md             # PERMANENTE: regras + infra + toolbox (fonte única, todos os agentes)
CLAUDE.md             # bridge Claude Code → @AGENTS.md + @docs/agent/context.md
docs/
├── agent/            # DINÂMICO: context.md (mapa do projeto) + decisions.md (log)
└── claude-overview/
```

## Personalização

### Adaptar as skills ao seu projeto

As skills são templates — após copiar para o seu projeto, edite para refletir o stack real:

- `skills/infra/SKILL.md` — coloque o runtime, framework e database reais
- `skills/api/SKILL.md` — adapte os paths de pasta ao seu projeto
- `skills/logging/SKILL.md` — especifique a biblioteca de logging usada

### Adicionar novas skills

1. Crie uma pasta em `.claude/skills/nome-da-skill/`
2. Adicione um `SKILL.md` com as convenções
3. Adicione `references/` com documentação detalhada

### Adicionar novos agents

1. Crie um arquivo em `.claude/agents/nome.md`
2. Defina responsabilidades e o que o agent consulta

### Adicionar novos commands

1. Crie um arquivo em `.claude/commands/nome.md`
2. Defina as instruções do comando

## Requisitos

- [Claude Code CLI](https://claude.ai/code) v2.1.32+
- Conta Anthropic com acesso ao Claude Code

## Licença

MIT
