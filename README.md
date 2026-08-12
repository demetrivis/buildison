# buildison

Toolbox de agentes — agents, commands e skills — a partir de uma **fonte única**, instalada no formato nativo
de cada agente: **Claude Code, Codex, OpenCode/Hermes e Antigravity**.

Sem duplicar conteúdo: `AGENTS.md` + `.claude/` + `docs/agent/` são a fonte; cada agente recebe só o "glue" dele.

---

## Índice

- [Instalar do zero](#instalar-do-zero)
- [Atualizar um projeto que já tem buildison](#atualizar-um-projeto-que-já-tem-buildison)
- [A infra](#a-infra) — local-infra, memória local vs VPS
- [O que cada agente recebe](#o-que-cada-agente-recebe)
- [Referência](#referência) — agents, commands, skills
- [Banco de dados via MCP](#banco-de-dados-via-mcp-opcional)
- [Estrutura do repo](#estrutura-do-repo)
- [Personalização](#personalização)
- [Quando algo quebra](#quando-algo-quebra)

---

## Instalar do zero

Entre na pasta do projeto e rode. O instalador pergunta o destino (default: pasta atual) e quais agentes quer.

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash
```

<details>
<summary>Outras formas de instalar</summary>

Direto do GitHub via npx (sempre a `main`):

```bash
npx github:demetrivis/buildison install
```

Do npm (versão publicada — pode estar atrás da `main`):

```bash
npx buildison@latest install
```

Clonando o repo:

```bash
git clone https://github.com/demetrivis/buildison.git
```

```bash
bash buildison/install.sh --dir /caminho/do/seu/projeto
```

</details>

### Sem interação

Escolhendo destino e agentes de uma vez:

```bash
npx github:demetrivis/buildison install --dir . --agents claude,codex,opencode,antigravity --yes
```

### Windows (PowerShell nativo)

```powershell
irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1 | iex
```

Com flags:

```powershell
.\install.ps1 -Dir C:\caminho\do\projeto -Agents claude,codex,opencode,antigravity -Infra -Serena
```

> O `curl | bash` e o `npx` também rodam no Windows, mas só via **Git Bash** ou WSL — no PowerShell puro não
> existe `bash`. Não dê duplo-clique nos scripts.

---

## Atualizar um projeto que já tem buildison

Entre na pasta do projeto e rode:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --update
```

Ou, se preferir npx:

```bash
npx github:demetrivis/buildison install --update
```

### O que o `--update` faz

Ele separa o que é **boilerplate** (vem do buildison, deve ser atualizado) do que é **seu** (conhecimento do
projeto, nunca sobrescrito):

| Atualiza | Preserva |
|---|---|
| `AGENTS.md` | `docs/agent/context.md` |
| `CLAUDE.md` | `docs/agent/decisions.md` |
| `.claude/`, `.agents/` | `COLLECTION_NAME` já configurada no `.mcp.json` |
| `.spec-workflow/templates/` | |

Faz `.bak` de tudo que muda e lista arquivos em `.claude/` que não existem mais na fonte — sem deletar, porque
o seu `.claude/` pode ter agents e skills próprios.

> ### ⚠️ Não use `--force` para atualizar
>
> O `--force` **apaga** o `docs/agent/context.md` e o `docs/agent/decisions.md`. Ele existe para regravar tudo
> do zero, não para atualizar. Para atualizar é sempre `--update`.

---

## A infra

O buildison assume um stack de desenvolvimento **global** em `~/local-infra/` — sobe uma vez e atende todos os
projetos da máquina. Hostname: `localhost` no host, `host.docker.internal` de dentro de container.

| Serviço | Porta | Para quê |
|---|---|---|
| **Postgres** | `5432` | Um database por projeto |
| **Redis** | `6379` | Um número de DB por projeto (`/0`, `/1`, …) |
| **Qdrant** | `6333` / `6334` | Memória vetorial dos agentes |
| **ngrok** | `4040` | URL pública efêmera (teste rápido) |
| **cloudflared** | — | Tunnel nomeado, URL estável no seu domínio |

### Montar a infra

Junto da instalação (monta o `~/local-infra/` com senha do Postgres gerada aleatoriamente):

```bash
npx github:demetrivis/buildison install --infra --serena
```

- **`--infra`** → monta o `~/local-infra/`. A senha do Postgres vai pro `~/local-infra/.env` e aparece no fim.
- **`--serena`** → instala o Serena no host via `uv`.

Use `--no-infra` / `--no-serena` para pular sem ser perguntado.

### Subir e derrubar

```bash
cd ~/local-infra && docker compose up -d
```

```bash
cd ~/local-infra && docker compose down
```

> `down` mantém os volumes — os dados sobrevivem.

### Memória: local ou VPS

A memória vetorial dos agentes (Qdrant) roda **local** (default) ou **na sua VPS** — nesse caso ela segue você
entre máquinas. A escolha é **por máquina**, salva em `~/.buildison/vps.env`, e projetos novos herdam.

Local:

```bash
npx github:demetrivis/buildison install --memory=local
```

VPS:

```bash
npx github:demetrivis/buildison install --memory=vps --qdrant-url=https://qdrant.seu-dominio.com
```

No modo VPS o `.mcp.json` gerado usa `"QDRANT_API_KEY": "${QDRANT_API_KEY}"` — a key é lida do **ambiente do
shell**, nunca entra no arquivo versionado. Exporte antes de abrir o agente:

```bash
export QDRANT_API_KEY="sua-key-aqui"
```

Para deixar permanente:

```bash
echo 'export QDRANT_API_KEY="sua-key-aqui"' >> ~/.zshrc && source ~/.zshrc
```

> **Sem replicação entre local e VPS.** São instâncias independentes — memórias salvas numa não aparecem na
> outra. Escolha uma como fonte de verdade.
>
> Setup completo da VPS (Traefik + HTTPS + API key): [`docs/infra/qdrant-vps-template.md`](docs/infra/qdrant-vps-template.md).

### Trocar de modo num projeto já instalado

Muda só os configs MCP, preservando `.claude/`, `AGENTS.md` e `docs/agent/`. Faz backup automático.

```bash
npx github:demetrivis/buildison switch --memory=vps --qdrant-url=https://qdrant.seu-dominio.com
```

```bash
npx github:demetrivis/buildison switch --memory=local
```

No PowerShell nativo:

```powershell
.\switch.ps1 -Memory vps -QdrantUrl https://qdrant.seu-dominio.com
```

Reinicie o agente depois — os configs MCP são lidos no boot.

### Uma collection por projeto

O Qdrant é uma instância só, com **uma collection por projeto** (`agent_<projeto>`). O instalador deriva o nome
do diretório; o `--update` respeita o que já estiver configurado.

> ⚠️ A API key do Qdrant dá acesso a **todas** as collections da instância — o Qdrant não isola auth por
> collection. Para isolamento real entre projetos, use instâncias separadas.

---

## O que cada agente recebe

| Agente | Glue gerado |
|---|---|
| **Claude Code** | `.claude/` + `CLAUDE.md` (`@imports`) + `.mcp.json` |
| **Codex** | `AGENTS.md` (nativo) + bloco MCP em `~/.codex/config.toml` |
| **OpenCode/Hermes** | `AGENTS.md` (nativo) + `opencode.json` |
| **Antigravity** | `AGENTS.md` (nativo) + `.agents/` (skills + workflows) + MCP no config global do Gemini |
| _(todos)_ | `AGENTS.md` + `docs/agent/context.md` + `docs/agent/decisions.md` |

<details>
<summary>Particularidades do Codex e do Antigravity</summary>

**Codex** — o `~/.codex/config.toml` é **global** e os nomes de tabela são fixos (`[mcp_servers.serena]` etc).
Por isso o buildison mantém **um bloco único**, substituído a cada install: um bloco por projeto declararia as
mesmas tabelas várias vezes, o que é TOML inválido e derruba **todos** os MCPs do Codex silenciosamente. A
consequência prática: `serena` e `spec-workflow` funcionam em qualquer projeto (resolvem pelo CWD), mas a
`COLLECTION_NAME` do Qdrant no global aponta para um projeto só — o último instalado.

**Antigravity** lê o `AGENTS.md` da raiz nativamente. O que ele reconhece por arquivo é **skill** e **workflow**
— não existe "agente custom" registrável (os subagentes Browser/Terminal são orquestrados pela IDE). Por isso o
`.agents/` gerado tem só `skills/` e `workflows/`, sem roster. Os workflows viram slash-commands (`/commit`,
`/pr`, `/tlg`…), e os agentes de missão (`arq-info`, `arq-info-web`, `design-system-extractor`) também. Os
agentes de camada (api, db, …) não têm equivalente — as convenções deles já vivem nas skills.

O MCP do Antigravity também é **global** (`~/.gemini/.../mcp_config.json`), gravado com o caminho absoluto do
projeto atual. Confira em _Settings › Customizations › Open MCP Config_.

Regenerar o `.agents/` a partir do `.claude/`:

```bash
node scripts/gen-antigravity.mjs
```

</details>

---

## Referência

### Agents

| Agent | Descrição |
|---|---|
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
| `arq-info` | Documenta a arquitetura do **nosso** código: C4/Structurizr, ERD, ADR (read-only) |
| `arq-info-web` | Engenharia reversa da arquitetura de informação de um app web **externo** |
| `design-system-extractor` | Extrai um design system fiel de um site de referência |
| `suporte` | Diagnostica o setup da toolbox: MCP falhando, troca de modo, memória |

### Commands

| Command | Descrição |
|---|---|
| `/commit` | Stage inteligente + commit com mensagem bem escrita |
| `/push` | Push seguro, cria upstream se necessário |
| `/pr` | Cria PR analisando todos os commits da branch |
| `/git` | Operações git assistidas com safety checks |
| `/tlg` | Git log visual com graph de branches |
| `/team` | Monta equipe de teammates independentes |
| `/explore` | Explora e mapeia o codebase |
| `/logs` | Analisa logs do projeto |
| `/docker` | Cria Dockerfiles multi-stage e compose (Python, Node, Go) |
| `/ghaction` | Cria workflows de GitHub Actions (detecta o stack) |
| `/portainer` | Gera stack para Portainer (Docker Swarm + Traefik + redes overlay) |
| `/mecontext` | Atualiza `docs/agent/context.md` e a memória do projeto |

### Skills

| Skill | Descrição |
|---|---|
| `database` | Supabase, PostgreSQL, Redis, migrations, RLS, VPS connections |
| `api` | Camada HTTP: routes, schemas, error handling (agnóstico de framework) |
| `infra` | Docker, env vars, estrutura de projeto, ADRs |
| `logging` | Logging estruturado em JSON, patterns de observabilidade |
| `golang` | Go backend: handlers, services, repositories, context, testing |
| `nestjs` | NestJS: módulos, controllers, services, DTOs, validação, Prisma |
| `prisma` | Prisma ORM: schema, migrations, client, transactions, performance |
| `postgrest` | PostgREST: APIs database-first, views, RPC, RLS, permissões |
| `cloudflare` | Cloudflare API, DNS, email routing, R2 storage |
| `seo-technical` | SEO técnico: sitemaps, meta tags, structured data |
| `favicon` | Favicon e metadata para Next.js |
| `local-infra` | Stack global Docker na máquina de dev: Postgres + Redis + Qdrant + tunnels |
| `vps-infra` | VPS do zero: Ubuntu, Docker, Swarm, Traefik com HTTPS, Portainer opcional |
| `agent-memory` | Memória vetorial via Qdrant: collections, payload, o que guardar |
| `spec-workflow` | Planejamento estruturado: requirements → design → tasks |
| `plano-operacao` | Pipeline read-only de documentação de arquitetura (C4, ERD, ADR) |

### A toolbox MCP

| Peça | Papel |
|---|---|
| **SpecWorkflow** | Planejamento: requirements → design → tasks |
| **Serena** | Navegação semântica do codebase |
| **Context7** | Docs atualizadas de libs/APIs |
| **Qdrant** | Memória vetorial persistente (uma collection por projeto) |

Pré-requisito do Serena, uma vez por máquina:

```bash
uv tool install -p 3.13 serena-agent && serena init
```

---

## Banco de dados via MCP (opcional)

O agente pode consultar Postgres e Redis direto. **Não vem por padrão** — nem todo projeto usa banco.

### Opção 1 — no config do agente

Portável entre Claude, Codex e OpenCode. Em `.mcp.json` (Claude Code):

```jsonc
"redis":    { "command": "uvx", "args": ["redis-mcp-server@latest", "--url", "redis://localhost:6379/0"] },
"postgres": { "command": "uvx", "args": ["postgres-mcp", "--access-mode=restricted"],
              "env": { "DATABASE_URI": "postgresql://dev:<SENHA>@localhost:5432/<DATABASE>" } }
```

Em `~/.codex/config.toml` (Codex):

```toml
[mcp_servers.redis]
command = "uvx"
args = ["redis-mcp-server@latest", "--url", "redis://localhost:6379/0"]

[mcp_servers.postgres]
command = "uvx"
args = ["postgres-mcp", "--access-mode=restricted"]
env = { DATABASE_URI = "postgresql://dev:<SENHA>@localhost:5432/<DATABASE>" }
```

Em `opencode.json` (OpenCode/Hermes): mesma ideia, dentro de `"mcp"`, com `"type": "local"` e `"command": [...]`.

> `--access-mode=restricted` = só leitura e operações seguras. Troque por `unrestricted` só se precisar escrever.
>
> ⚠️ **A senha fica no arquivo.** Em repo público não commite a senha real — use placeholder, ou vá de Docker
> Toolkit (abaixo), que guarda o secret no Keychain.

### Opção 2 — Docker MCP Toolkit

Sem senha em arquivo. Primeiro, o secret:

```bash
printf '%s' "<SENHA>" | docker mcp secret set POSTGRES_PASSWORD
```

Depois habilite os servers Postgres/Redis no Docker Desktop → MCP Toolkit e conecte:

```bash
docker mcp client connect claude-code
```

---

## Estrutura do repo

```
AGENTS.md              # PERMANENTE: regras + infra + toolbox (fonte única, todos os agentes)
CLAUDE.md              # bridge Claude Code → @AGENTS.md + @docs/agent/context.md
.mcp.json              # toolbox MCP (spec-workflow, serena, qdrant-memory)
.spec-workflow/        # templates de requirements/design/tasks

.claude/               # PERMANENTE: a máquina do boilerplate
├── settings.json
├── agents/            # db, api, logic, infra, logger, security-auditor, golang,
│                      # prisma, nestjs, postgrest, arq-info, arq-info-web,
│                      # design-system-extractor, suporte
├── commands/          # commit, push, pr, git, tlg, team, explore, logs,
│                      # docker, ghaction, portainer, mecontext
└── skills/            # database, api, infra, logging, golang, nestjs, prisma,
                       # postgrest, cloudflare, seo-technical, favicon,
                       # local-infra, vps-infra, agent-memory, spec-workflow,
                       # plano-operacao

.agents/               # glue p/ Antigravity (gerado de .claude/)
├── skills/
└── workflows/

docs/
├── agent/             # DINÂMICO: context.md (mapa do projeto) + decisions.md (log)
├── infra/             # setup da VPS de memória
└── claude-overview/   # documentação do template

scripts/
└── gen-antigravity.mjs
```

### Permanente vs dinâmico

A distinção que organiza tudo:

- **`AGENTS.md`** e **`.claude/`** são **permanentes** — vêm do boilerplate e não mudam por projeto. O
  `--update` sobrescreve.
- **`docs/agent/context.md`** e **`decisions.md`** são **dinâmicos** — o agente os mantém conforme constrói. O
  `--update` nunca encosta.

Ao herdar o template, evite editar o `AGENTS.md`: o que é específico do seu projeto vai no `context.md`.

---

## Personalização

As skills são templates — depois de instalar, adapte ao stack real do projeto:

- `skills/infra/SKILL.md` — runtime, framework e database reais
- `skills/api/SKILL.md` — os paths de pasta do seu projeto
- `skills/logging/SKILL.md` — a biblioteca de logging usada

**Nova skill:** crie `.claude/skills/nome/SKILL.md` com as convenções, e `references/` se precisar de detalhe.

**Novo agent:** crie `.claude/agents/nome.md` definindo responsabilidades e o que ele consulta.

**Novo command:** crie `.claude/commands/nome.md` com as instruções.

Depois de mexer no `.claude/`, regenere o mirror do Antigravity:

```bash
node scripts/gen-antigravity.mjs
```

---

## Quando algo quebra

O agente `suporte` (`.claude/agents/suporte.md`) é especialista no setup — diagnostica `/mcp · failed`, troca de
modo, migração de memória entre instâncias Qdrant e `QDRANT_API_KEY` não expandida. Acione em linguagem natural:

> *"a memória não está conectando, vê o que tá errado com o suporte"*

Checagens rápidas:

```bash
echo $QDRANT_API_KEY
```

```bash
curl -s -H "api-key: $QDRANT_API_KEY" https://qdrant.seu-dominio.com/collections
```

```bash
docker ps --filter name=qdrant
```

> **Reinicie o agente depois de mexer em qualquer config MCP** — todos leem no boot.

---

## Requisitos

- [Claude Code CLI](https://claude.ai/code) v2.1.32+ (ou Codex / OpenCode / Antigravity)
- `git`, `bash` e `python3`
- `uv` para o Serena · Docker Desktop para o `local-infra`

## Licença

MIT
