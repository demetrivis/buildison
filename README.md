# buildison

Boilerplate de agents, commands e skills do Claude Code para projetos backend.

> **Infra local**: este template assume stack de desenvolvimento em `~/local-infra/` (Postgres + Redis + ngrok via Docker Desktop). Credenciais e hostnames estão no [CLAUDE.md](CLAUDE.md). Para montar o stack do zero, a skill `local-infra` tem o docker-compose completo.

## O que é isso?

Uma coleção de agentes especializados, comandos prontos e skills de referência pré-configurados para o Claude Code. Clone, copie pro seu projeto e comece a trabalhar — o Claude já sabe como se organizar, dividir trabalho entre agentes e seguir as convenções do projeto.

Os agents detectam automaticamente o stack do projeto (Python, Node.js, Go, etc.) lendo o manifesto antes de qualquer ação. As skills são templates de convenções — personalize-as para o seu projeto.

## Como Usar

### 1. Clone o repositório

```bash
git clone git@github.com:xanfrO/buildison.git
cd buildison
```

### 2. Copie a pasta `.claude/` para seu projeto

```bash
cp -r .claude/ /caminho/do/seu/projeto/
```

### 3. Abra o Claude Code no seu projeto

```bash
cd /caminho/do/seu/projeto
claude
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
| `cloudflare` | Cloudflare API, DNS, email routing, R2 storage |
| `seo-technical` | SEO técnico: sitemaps, meta tags, structured data |
| `favicon` | Favicon e metadata para Next.js |
| `local-infra` | Docker Desktop stack: Postgres + Redis + ngrok em `~/local-infra/` |

## Estrutura

```
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
    │   ├── SKILL.md
    │   └── references/
    ├── api/
    │   ├── SKILL.md
    │   └── references/
    ├── infra/
    │   ├── SKILL.md
    │   └── references/
    ├── logging/
    │   ├── SKILL.md
    │   └── references/
    ├── local-infra/
    │   ├── SKILL.md
    │   └── references/
    ├── cloudflare/
    ├── seo-technical/
    └── favicon/

CLAUDE.md             # contexto de infra local + MCPs (lido automaticamente)
docs/
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
