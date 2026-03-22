# Agentes

Agentes sao especialistas que o Claude Code pode spawnar como subagentes para executar trabalho focado. Cada agente domina um dominio especifico e pode trabalhar em paralelo com outros agentes.

## Como funcionam

Quando o Claude precisa dividir trabalho, ele spawna agentes usando a Agent tool. Cada agente roda na sua propria context window, faz o trabalho, e retorna o resultado para o agente principal que consolida tudo.

Os agentes ficam em `.claude/agents/` e o Claude os conhece automaticamente. Voce nao precisa referencia-los manualmente — o Claude sabe quais existem e quando usar cada um.

## Agentes disponiveis

### db.md — Banco de Dados

Especialista em Supabase + PostgreSQL + Redis. Responsavel por tudo que toca dados.

O que faz:
- Design de schema e tabelas
- Migrations SQL com naming conventions
- Policies de Row Level Security (RLS)
- Repositories com BaseRepository generico
- Configuracao do client Supabase
- Conexoes remotas a PostgreSQL e Redis em VPS
- Pool de conexoes com asyncpg

Consulta a skill: `database/`

### api.md — API / HTTP

Especialista em FastAPI e camada HTTP. Responsavel por tudo entre o request e o service.

O que faz:
- Criar routers em `src/api/routers/`
- Schemas Pydantic v2 de request/response
- Dependencies de auth e database session
- Middlewares de logging, CORS, error handling
- Mapeamento de domain exceptions para HTTP status codes
- Contratos de API com paginacao e formato de erro consistente

Consulta a skill: `api/`

### logic.md — Logica de Negocio

Especialista em regras de dominio e service layer. Responsavel por tudo que e regra de negocio.

O que faz:
- Services em `src/core/services/`
- Domain models puros (sem framework)
- Validacoes de regras de negocio
- Orquestracao de processos multi-step
- State machines para entidades com ciclo de vida
- Domain exceptions em `src/core/exceptions.py`

Nao consulta skill especifica — opera com principios de DDD e clean architecture.

### infra.md — Infraestrutura

Especialista em arquitetura, Docker, deploy e configuracao. Responsavel por tudo que nao e codigo de negocio.

O que faz:
- Estrutura de pastas do projeto
- Dockerfiles multi-stage e docker-compose
- Configuracao de ambiente com pydantic-settings
- CI/CD com GitHub Actions
- ADRs (Architecture Decision Records)
- Health checks e graceful shutdown

Consulta a skill: `infra/`

### logger.md — Logging Estruturado

Especialista em observabilidade e logging. Responsavel por garantir que todo log do projeto segue o padrao.

O que faz:
- Configuracao do structlog em `src/shared/logging.py`
- Padrao JSON em producao, console colorido em dev
- Campos obrigatorios: event, level, logger, timestamp, request_id
- Tracking de performance com elapsed_ms
- Auditoria de codigo para print() e dados sensiveis em logs
- Analise e diagnostico de logs

Consulta a skill: `logging/`

### security-auditor.md — Auditoria de Seguranca

Especialista em seguranca. Revisa codigo e configuracao em busca de vulnerabilidades.

## Quando usar agentes

Agentes sao uteis quando:
- A tarefa toca 2+ dominios que podem ser trabalhados em paralelo
- Voce quer trabalho focado e profundo num dominio especifico
- Precisa de um especialista que conhece as convencoes do projeto

Agentes nao sao necessarios quando:
- A tarefa e simples e voce pode resolver direto
- O trabalho e sequencial e cada passo depende do anterior

## Como spawnar agentes

Voce nao spawna agentes diretamente. Use os comandos:
- `/sub` — spawna 1 ou mais subagentes sob demanda
- `/team` — monta uma equipe de teammates independentes
- `/explore` — spawna subagentes para explorar o codebase

Ou simplesmente peca ao Claude e ele decide se vale spawnar agentes e quais usar.
