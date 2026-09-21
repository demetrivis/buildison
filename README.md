# buildison

Toolbox de agentes — agents, commands e skills — a partir de uma **fonte única**, instalada no formato nativo
de cada agente: **Claude Code, Codex, OpenCode/Hermes e Antigravity**.

Sem duplicar conteúdo: `AGENTS.md` + `.claude/` + `docs/agent/` são a fonte; cada agente recebe só o "glue" dele.

---

## Índice

- [Instalar do zero](#instalar-do-zero)
- [Instalar leve ou sob medida](#instalar-leve-ou-sob-medida) — só os arquivos, sem MCP e sem infra
- [Instalar no global](#instalar-no-global) — pra todos os projetos da máquina, com ou sem spec-workflow
- [Atualizar um projeto que já tem buildison](#atualizar-um-projeto-que-já-tem-buildison)
- [A infra](#a-infra) — local-infra; memória vetorial via `/qdrant`
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

## Instalar leve ou sob medida

Por padrão o buildison instala tudo (`full`). Se você só quer os **arquivos** — agents, skills e commands — sem
MCP e sem `local-infra`, escolha um preset:

| Preset | O que vem | Precisa na máquina |
|---|---|---|
| `files` | `AGENTS.md`, `docs/agent/`, `.claude/agents`, `.claude/commands`, `.claude/skills` (e `.agents/` no Antigravity) | nada |
| `lite` | `files` + MCP `spec-workflow` + `.spec-workflow/templates/` | Node (`npx`) |
| `full` _(default)_ | `lite` + MCP `serena` + `.claude/settings.json` | `uv`/Serena |
| `custom` | pergunta MCPs, partes e itens | depende |

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --preset files
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Preset files
```

No modo interativo o instalador pergunta o preset logo depois dos agentes.

### Sob medida

As flags partem do preset e sobrescrevem só o que você passar:

| bash | PowerShell | Valores |
|---|---|---|
| `--mcp` | `-Mcp` | `spec-workflow`, `serena`, `chrome-devtools` ou `none` |
| `--parts` | `-Parts` | `agents`, `commands`, `skills`, `settings` |
| `--skills` | `-Skills` | só estas skills |
| `--subagents` | `-Subagents` | só estes agents |
| `--commands` | `-Commands` | só estes commands |
| `--list` | `-List` | mostra tudo que dá pra escolher |

```bash
bash install.sh --dir . --agents claude,codex --mcp spec-workflow --skills golang,nestjs,database --commands commit,pr --yes
```

O que depende de uma peça sai sozinho quando ela não é instalada: a
skill `spec-workflow` só vem com o MCP `spec-workflow`, a `local-infra` só com a infra, e o agent `suporte` só com algum
MCP. Pedir o item pelo nome força a instalação.

O `AGENTS.md` e os templates de `docs/agent/` também são filtrados: as seções de infra e Serena só aparecem
no projeto se a peça foi instalada (blocos `<!-- bld:if ... -->` na fonte).

A escolha fica salva em `.buildison`, na raiz do projeto. As próximas execuções e o `--update` reaproveitam esse
arquivo — passe outro `--preset` para mudar.

---

## Instalar no global

Em vez de instalar projeto a projeto, `--global` põe agents, commands e skills **na máquina** — valem em
todo projeto que você abrir, sem nada dentro dele:

| Agente | Onde vai |
| :-- | :-- |
| Claude Code | `~/.claude/agents`, `~/.claude/commands`, `~/.claude/skills` |
| Codex | `~/.agents/skills` (o Codex não tem agents nem commands em arquivo) |

Duas versões:

```bash
# SEM spec-workflow (default) — só arquivos
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh \
  | bash -s -- --global --agents claude,codex --yes

# COM spec-workflow — + skill spec-workflow + MCP spec-workflow valendo em todo projeto
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh \
  | bash -s -- --global --preset lite --agents claude,codex --yes
```

No PowerShell: `.\install.ps1 -Global -Agents claude,codex -Yes` (e `-Preset lite` pra versão com).

Na versão **com**, o MCP entra no **escopo user** do Claude Code (`claude mcp add -s user`) e no
`~/.codex/config.toml`. Os templates próprios do buildison em `.spec-workflow/templates/` só vêm no
install por projeto — no global o spec-workflow usa os templates padrão dele.

**O que fica de fora**, por ser de um projeto só: `AGENTS.md`, `CLAUDE.md`, `docs/agent/`, o
`settings.json` (permissões amplas em todo projeto seria demais) e o Serena (precisa do `--project`).
OpenCode e Antigravity ainda não têm instalação global.

### Skills de plugins do Claude no Codex (`--plugin-skills`)

Plugin do Claude Code (de marketplace, ou sincronizado da sua conta do claude.ai) **não roda no Codex** —
mas a skill dele roda, se estiver em `~/.agents/skills`. O `--plugin-skills` faz essa ponte:

```bash
# buildison + eng-arq, SEM spec-workflow
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh \
  | bash -s -- --global --plugin-skills eng-arq --agents claude,codex --yes

# buildison + eng-arq, COM spec-workflow
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh \
  | bash -s -- --global --preset lite --plugin-skills eng-arq --agents claude,codex --yes
```

- O conteúdo vem do plugin **instalado na sua máquina** — o buildison não carrega nada de terceiro no repo.
  Plugin que não está instalado ali é pulado com aviso.
- **No Claude nada muda:** ele continua usando o plugin (sem duplicar a skill). Os commands do plugin
  (`/eng-arq:arquitetar` etc.) seguem só no Claude — o Codex não tem commands em arquivo.
- `${CLAUDE_PLUGIN_ROOT}` só existe dentro do Claude Code; na cópia ele é reescrito pra pasta da skill no
  Codex, senão as referências da skill não abririam.
- A escolha fica salva como as outras: trocar de versão (`--preset files|lite`) mantém as skills de plugin.
  Pra tirar: `--plugin-skills none`. Plugin atualizado? Rode o mesmo comando de novo.

**Atualizar** é rodar o mesmo comando de novo: a escolha fica em `~/.buildison/global.env` e é relida.
**Trocar de versão** é passar o outro `--preset` — da com pra sem, a skill e o MCP do spec-workflow saem.

O instalador só mexe no que **ele mesmo** pôs lá (`~/.buildison/global.manifest`):

- skill ou agent **seu** com o mesmo nome de um do buildison é mantido, com aviso (`--force` sobrescreve);
- item do buildison que saiu da seleção vai pra `~/.buildison/removidos-<data>/`, não pro lixo;
- no Codex, trocar pra versão sem **não** tira o spec-workflow do `~/.codex/config.toml` — esse arquivo é
  compartilhado com os installs por projeto, e tirar dali quebraria quem conta com ele.

> **Global ou por projeto, não os dois.** Com os dois, os mesmos agents e skills aparecem duplicados — o
> install por projeto avisa quando detecta o global.

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
| `.claude/`, `.agents/` | `docs/agent/decisions.md` |
| `.spec-workflow/templates/` | `CLAUDE.md` (se já existe) |
| `.mcp.json` | `COLLECTION_NAME` já configurada no `.mcp.json` |

Faz `.bak` de tudo que muda e lista arquivos em `.claude/` que não existem mais na fonte — sem deletar, porque
o seu `.claude/` pode ter agents e skills próprios. Respeita o preset salvo em `.buildison`.

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

### Memória vetorial (Qdrant) — via `/qdrant`, não pelo instalador

**O instalador não configura Qdrant.** Memória vetorial é opt-in: instale o buildison normalmente e,
quando quiser memória persistente, peça ao agente — **`/qdrant`** (skill `qdrant-setup`).

A skill faz tudo: pergunta o modo, garante o Qdrant no ar, registra o MCP `qdrant-memory` **só nos
agentes que o projeto usa**, cria a collection `agent_<projeto>` e valida com `qdrant-store`/`qdrant-find`.
Ela também **troca de modo** e **remove** — foi ela que absorveu o antigo `buildison switch`.

| Modo | Endpoint | Quando |
| :-- | :-- | :-- |
| **local** | `http://localhost:6333` (do `~/local-infra`) | simples; a memória fica só nesta máquina |
| **VPS** | `https://qdrant.<seu-dominio>` com `api-key` | a memória segue você entre máquinas |

No modo VPS o config usa `"QDRANT_API_KEY": "${QDRANT_API_KEY}"` — a key é lida do **ambiente do
shell**, nunca entra no arquivo versionado. Exporte antes de abrir o agente:

```bash
echo 'export QDRANT_API_KEY="sua-key-aqui"' >> ~/.zshrc && source ~/.zshrc
```

> **Sem replicação entre local e VPS.** São instâncias independentes — memórias salvas numa não aparecem na
> outra, e trocar de modo **não migra** o que já foi gravado. Escolha uma como fonte de verdade.
>
> **O `~/.codex/config.toml` é global**: existe uma collection `qdrant-memory` pra máquina inteira, não uma
> por projeto. A skill avisa antes de mexer nele.
>
> Setup completo da VPS (Traefik + HTTPS + API key): [`docs/infra/qdrant-vps-template.md`](docs/infra/qdrant-vps-template.md).

### Uma collection por projeto

O Qdrant é uma instância só, com **uma collection por projeto** (`agent_<projeto>`). A skill deriva o nome
do diretório; passe `--collection` ao script dela pra usar outro.

> ⚠️ A API key do Qdrant dá acesso a **todas** as collections da instância — o Qdrant não isola auth por
> collection. Para isolamento real entre projetos, use instâncias separadas.

---

## O que cada agente recebe

| Agente | Glue gerado |
|---|---|
| **Claude Code** | `.claude/` + `CLAUDE.md` (`@imports`) + `.mcp.json` |
| **Codex** | `AGENTS.md` (nativo) + bloco MCP em `~/.codex/config.toml` |
| **OpenCode/Hermes** | `AGENTS.md` (nativo) + `opencode.json` |
| **Antigravity** | `AGENTS.md` (nativo) + `.agents/skills/` (skills e commands) + `.agents/agents/` + MCP no config global do Gemini |
| _(todos)_ | `AGENTS.md` + `docs/agent/context.md` + `docs/agent/decisions.md` |

<details>
<summary>Particularidades do Codex e do Antigravity</summary>

**Codex** — o `~/.codex/config.toml` é **global** e os nomes de tabela são fixos (`[mcp_servers.serena]` etc).
Uma tabela declarada duas vezes é TOML inválido, e aí o Codex descarta a config **inteira** — inclusive
`[windows]`, o que deixa o app em loop ou abrindo várias instâncias. Por isso os dois instaladores:

- mantêm **um bloco único** `# >>> buildison >>>` e removem os blocos legados por projeto;
- **não repetem** uma tabela que você já declarou fora do bloco;
- **não tiram** do bloco o que um install anterior pôs e o atual não pediu — um projeto `lite` não desliga a memória de outro;
- **validam** o arquivo final (tabelas duplicadas + `tomllib` quando há Python 3.11+) e, se ele ficaria inválido, não gravam nada.

O preset `files` não toca no `config.toml`. `serena` e `spec-workflow` funcionam em qualquer projeto (resolvem pelo
CWD), mas a `COLLECTION_NAME` do Qdrant no global aponta para um projeto só — o último que instalou memória.

**Antigravity** (2.0, CLI `agy` e IDE) lê o `AGENTS.md` da raiz nativamente. O resto vai no `.agents/`, no
formato da doc oficial ([llms.txt](https://antigravity.google/llms.txt) — toda página tem versão `.md`):

- **Skills** em `.agents/skills/<nome>/SKILL.md` — a **pasta inteira**, no padrão Agent Skills, então
  `references/` e `scripts/` vão junto. Os **commands** do buildison também entram como skill: no Antigravity
  toda skill vira `/<nome>` sozinha (`/commit`, `/pr`, `/tlg`…).
- **Agents** em `.agents/agents/<nome>.md` — viram subagentes que o agente principal delega (e dá pra
  escolher como agente principal no `/agents`). O frontmatter leva só `name` e `description`: o `tools` fica
  de fora de propósito, porque os nomes do Claude (`Read`, `Bash`…) não existem lá e a doc avisa que nome de
  tool inválido **trava** o subagente.
- **Workflows não são mais gerados** — o Antigravity os descontinua em 1º de novembro de 2026. Num `--update`,
  o instalador remove os workflows e as skills soltas (`.agents/skills/<nome>.md`) que **ele mesmo** gerou nas
  versões antigas; o que você escreveu à mão fica.

O MCP do Antigravity vai no **`.agents/mcp_config.json` do projeto**, com caminhos relativos (igual ao
`.mcp.json` do Claude) — **nunca** no global `~/.gemini/config/mcp_config.json`. O global vale pra todo projeto
aberto no Antigravity: as versões antigas do instalador gravavam lá com o caminho absoluto do "último projeto
instalado", e aí serena, spec-workflow e a memória Qdrant de **um** projeto apareciam em **todos** (memória de um
projeto indo pra coleção de outro). Se o global ainda tiver servidor preso a um projeto, o instalador avisa —
não apaga sozinho, porque o global é seu.

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
| `/qdrant` | Instala/troca/remove a memória vetorial Qdrant (skill `qdrant-setup`) |

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
| `vps-infra` | VPS do zero: Ubuntu, Docker, Swarm, Traefik com HTTPS, Portainer opcional. **Também vive no [infrailson](https://github.com/demetrivis/infrailson) — editou aqui, sincronize lá** |
| `qdrant-setup` | **Setup** da memória vetorial sob demanda: sobe/aponta o Qdrant, registra o MCP, cria a collection, troca de modo, remove |
| `agent-memory` | **Uso** da memória vetorial: collections, payload, o que guardar e o que nunca guardar |
| `spec-workflow` | Planejamento estruturado: requirements → design → tasks |
| `plano-operacao` | Pipeline read-only de documentação de arquitetura (C4, ERD, ADR) |

### A toolbox MCP

| Peça | Papel |
|---|---|
| **SpecWorkflow** | Planejamento: requirements → design → tasks |
| **Serena** | Navegação semântica do codebase |
| **Context7** | Docs atualizadas de libs/APIs |
| **Qdrant** | Memória vetorial persistente (uma collection por projeto) — via `/qdrant` |
| **Chrome DevTools** | Browser pro agente (`--mcp chrome-devtools`) — sempre com `--isolated` |

O `chrome-devtools-mcp` sem `--isolated` usa **o mesmo perfil do Chrome** em toda sessão: com duas abertas
ao mesmo tempo (dois Claudes, ou Claude + Antigravity), a segunda falha com _"The browser is already
running"_. Por isso o instalador sempre grava com `--isolated` (um Chrome temporário por sessão) e, no fim de
toda instalação, **avisa** onde encontrar um `chrome-devtools-mcp` sem isolamento — Claude (user, local e
`.mcp.json`), Antigravity (projeto e global), Codex e OpenCode. O preço do `--isolated` é começar deslogado
toda vez; pra site com login, `--autoConnect` usa o seu Chrome aberto.

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
│                      # docker, ghaction, portainer, mecontext, qdrant
└── skills/            # database, api, infra, logging, golang, nestjs, prisma,
                       # postgrest, cloudflare, seo-technical, favicon,
                       # local-infra, vps-infra, qdrant-setup, agent-memory, spec-workflow,
                       # plano-operacao

.agents/               # glue p/ Antigravity (gerado de .claude/)
├── skills/            # uma pasta por skill + uma por command (vira /<nome>)
└── agents/            # subagentes

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
- `git` e `bash` (ou PowerShell no Windows)
- `python3` 3.11+ é opcional: valida o `config.toml` do Codex a fundo e grava o MCP do Antigravity (bash)
- Só quando instalados: `uv` para o Serena · Qdrant (Docker Desktop com o `local-infra`, ou VPS) para a memória — este via `/qdrant`, nunca pelo instalador

## Licença

MIT
