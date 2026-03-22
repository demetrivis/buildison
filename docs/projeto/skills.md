# Skills

Skills sao conhecimento de referencia do projeto. Definem como as coisas funcionam aqui — convencoes, padroes, templates, exemplos. O Claude consulta as skills para saber como fazer as coisas do jeito certo neste projeto especifico.

## Como funcionam

Cada skill e uma pasta dentro de `.claude/skills/` com esta estrutura:

```
skill-name/
├── SKILL.md              # Regras core, resumo, convencoes principais
└── references/           # Documentacao detalhada
    ├── topico-a.md
    ├── topico-b.md
    └── topico-c.md
```

O `SKILL.md` e enxuto — contem as regras essenciais e usa `@references/` para apontar para os detalhes de implementacao. Isso mantem o contexto leve: o Claude carrega o SKILL.md e so vai nos references quando precisa de detalhes.

## Diferenca entre Skill e Agent

- **Skill** = conhecimento passivo. Diz "como fazemos X neste projeto". O Claude consulta.
- **Agent** = executor ativo. Pode ser spawnado para fazer trabalho. Ele le a skill antes de comecar.

Exemplo: a skill `api/` define que rotas ficam sob `/api/v1/`, schemas de request e response sao separados, e erros retornam `{"detail": "..."}`. O agent `api.md` e o especialista que cria endpoints seguindo essas convencoes.

## Skills disponiveis

### database/

Supabase + PostgreSQL + Redis. Tudo sobre a camada de dados.

**SKILL.md** cobre: stack, estrutura de pastas, naming de tabelas/colunas/constraints, regras core.

**References:**
- `supabase-client.md` — Inicializacao do client, CRUD, auth, storage, asyncpg para queries complexas
- `migrations.md` — Template de tabela, tipos PostgreSQL, foreign keys, ON DELETE policies, partial indexes
- `rls.md` — Row Level Security: policies para own data, admin, multi-tenant, funcoes helper
- `repositories.md` — BaseRepository generico, repositories especificos, uso nos services
- `postgres-vps.md` — Conexao remota ao PostgreSQL em VPS: user setup, pg_hba.conf, pool asyncpg, SSL, SSH tunnel
- `redis-vps.md` — Conexao remota ao Redis em VPS: redis.conf, redis-py async, cache patterns, rate limiting, distributed lock
- `health-checks.md` — Health endpoint que verifica PG e Redis, retry com backoff exponencial, circuit breaker

### api/

FastAPI + Pydantic v2. Tudo sobre a camada HTTP.

**SKILL.md** cobre: estrutura de pastas, regras core de rotas, status codes, naming de schemas.

**References:**
- `routers.md` — Padrao completo de router com exemplos, nomenclatura de endpoints, registro de routers
- `schemas.md` — Pydantic v2 schemas, naming convention (Create/Update/Patch/Response), validacao custom
- `error-handling.md` — Global exception handler, domain-to-HTTP mapping, auth dependencies, database session dependency

### infra/

Docker, ambiente, arquitetura. Tudo sobre infraestrutura.

**SKILL.md** cobre: stack base, estrutura de pastas padrao, regras core de infra.

**References:**
- `docker.md` — Dockerfile multi-stage, docker-compose dev, .dockerignore, checklist de otimizacao
- `env-config.md` — pydantic-settings setup, .env.example, validacao de config na inicializacao
- `adr-template.md` — Template para Architecture Decision Records, quando criar, exemplo completo

### logging/

structlog + JSON. Tudo sobre observabilidade.

**SKILL.md** cobre: stack, campos obrigatorios, prefixo console, regras inviolaveis, niveis.

**References:**
- `structlog-config.md` — Setup completo do structlog, inicializacao, silenciar loggers ruidosos
- `patterns.md` — Logging em funcoes, services, middleware, background tasks. Tabela de eventos comuns.
- `analysis.md` — Como encontrar logs, parsing JSON com jq, padroes de problema, formato de relatorio

### cloudflare/

Cloudflare API, DNS, email routing, R2.

**References:**
- `cloudflare-api.md` — Autenticacao, zones, DNS records (CRUD), error handling, rate limits
- `email-routing.md` — Email routing e regras
- `r2-storage.md` — R2 object storage
- `vercel-integration.md` — Integracao Cloudflare + Vercel

### seo-technical/

SEO tecnico para projetos web.

**References:**
- `checklist.md` — Checklist de SEO tecnico
- `nextjs-implementation.md` — Implementacao de SEO no Next.js
- `structured-data.md` — Schema.org e dados estruturados

### favicon/

Favicon e metadata.

**References:**
- `nextjs-metadata.md` — Metadata e favicons no Next.js

## Como adicionar uma nova skill

1. Crie a pasta: `.claude/skills/nome-da-skill/`
2. Crie o `SKILL.md` com frontmatter (name, description, allowed-tools) e regras core
3. Crie a pasta `references/` com os detalhes de implementacao
4. Use `@references/nome.md` no SKILL.md para linkar os references
5. Se a skill tem um dominio que justifica um agente executor, crie o agent em `.claude/agents/`

## References (funcionalidade do Claude Code)

Os `@` nos SKILL.md nao sao decoracao — sao imports do Claude Code. Quando o Claude le um SKILL.md, os `@references/arquivo.md` sao expandidos e carregados no contexto automaticamente. Funciona com paths relativos, absolutos, e ate `@~/` para o home directory. Imports recursivos com limite de 5 niveis.
