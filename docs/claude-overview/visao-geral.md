# Visao Geral do Projeto

## O que e isto

Este repositorio e um template para projetos que usam Claude Code. A ideia e simples: quando voce comeca um projeto novo, clona este repo e ja tem toda a estrutura pronta — agentes especializados, comandos prontos, skills com convencoes do projeto e documentacao de referencia. Sem precisar configurar nada na mao.

## O problema que resolve

Toda vez que voce inicia um projeto com Claude Code, precisa explicar do zero como quer que ele se organize: como dividir trabalho, quais convencoes seguir, como logar, como estruturar o banco, como fazer commits. Isso e repetitivo e propenso a inconsistencia entre projetos.

Este template resolve isso com tres camadas:

1. **Agentes** (`.claude/agents/`) — Especialistas que o Claude pode spawnar como subagentes para executar trabalho focado em paralelo. Cada agente domina um dominio: banco de dados, API, logica de negocio, infraestrutura, logging.

2. **Comandos** (`.claude/commands/`) — Acoes que voce invoca com `/comando`. Desde operacoes git (/commit, /push, /pr) ate orquestracao de times de agentes (/team, /sub) e exploracao do codebase (/explore).

3. **Skills** (`.claude/skills/`) — Conhecimento de referencia sobre como as coisas funcionam neste projeto. Convencoes, padroes, templates de codigo, exemplos. O Claude consulta as skills para saber como fazer as coisas do jeito certo neste projeto especifico.

## Como as camadas se relacionam

As tres camadas tem papeis distintos e complementares:

- **Skill** = conhecimento. Diz "aqui e como fazemos X neste projeto". E passiva — o Claude consulta quando precisa.
- **Agent** = executor. Pode ser spawnado como subagente para fazer trabalho focado. Ele le a skill relevante antes de comecar.
- **Command** = gatilho. Voce invoca e o Claude executa uma acao — pode envolver spawnar agentes, rodar git, analisar logs.

Exemplo pratico: voce invoca `/sub` e pede para criar um endpoint de pagamentos. O Claude spawna o agent `api.md` que consulta a skill `api/` para saber as convencoes de rotas, schemas e error handling deste projeto. Ao mesmo tempo, spawna o agent `db.md` que consulta a skill `database/` para criar a migration seguindo o padrao de naming e tipos.

## Estrutura do repositorio

```
.claude/
├── agents/           # Especialistas que podem ser spawnados
│   ├── db.md         # Supabase + PostgreSQL
│   ├── api.md        # FastAPI + HTTP
│   ├── logic.md      # Logica de negocio
│   ├── infra.md      # Infraestrutura e arquitetura
│   ├── logger.md     # Logging estruturado
│   └── security-auditor.md
│
├── commands/         # Acoes invocaveis com /comando
│   ├── commit.md     # /commit — commit inteligente
│   ├── push.md       # /push — push seguro
│   ├── pr.md         # /pr — criar pull request
│   ├── tlg.md        # /tlg — tree log graph visual
│   ├── git.md        # /git — operacoes git assistidas
│   ├── team.md       # /team — montar equipe de teammates
│   ├── sub.md        # /sub — spawnar subagentes
│   ├── explore.md    # /explore — explorar o codebase
│   ├── logs.md       # /logs — analisar logs
│   ├── docker.md     # /docker — Dockerfiles e compose
│   └── ghaction.md   # /ghaction — GitHub Actions workflows
│
├── skills/           # Conhecimento de referencia do projeto
│   ├── database/     # Supabase, PostgreSQL, Redis, VPS
│   ├── api/          # FastAPI, routers, schemas, errors
│   ├── infra/        # Docker, env vars, ADRs
│   ├── logging/      # structlog, patterns, analise
│   ├── cloudflare/   # Cloudflare API, DNS, R2, email routing
│   ├── seo-technical/ # SEO tecnico, structured data
│   └── favicon/      # Favicon e metadata
│
└── settings.json     # Configuracoes do Claude Code

docs/
└── projeto/          # Documentacao do projeto (voce esta aqui)
```

## Como usar este template

1. Crie um repo a partir do template: `gh repo create meu-projeto --template seu-user/claude-code-template`
2. Clone e abra com Claude Code
3. Comece a trabalhar — tudo ja esta configurado

Para mais detalhes, veja os outros documentos nesta pasta:
- `agentes.md` — Como os agentes funcionam e quando usar cada um
- `comandos.md` — Todos os comandos disponiveis e como invocar
- `skills.md` — Como as skills organizam o conhecimento do projeto
- `como-usar.md` — Guia pratico com exemplos reais de uso
