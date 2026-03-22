---
name: infra
description: "Project infrastructure conventions: folder structure, Docker, env vars, deployment, and architectural decisions. Use when setting up project structure, configuring Docker, managing environment variables, or making infrastructure decisions."
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Infrastructure

Convenções de infraestrutura, estrutura de projeto, Docker, variáveis de ambiente e decisões de arquitetura.

## Stack Base

- **Runtime**: Python 3.12
- **Framework**: FastAPI + Uvicorn
- **Database**: PostgreSQL 16 via Supabase
- **Container**: Docker multi-stage builds
- **Config**: pydantic-settings com .env

## Estrutura de Pastas

```
project-root/
├── src/
│   ├── api/              # Camada HTTP (routers, schemas, dependencies, middlewares)
│   ├── core/             # Lógica de negócio (services, models, exceptions)
│   ├── db/               # Dados (repositories, migrations, client)
│   ├── shared/           # Transversal (logging, config, constants)
│   └── main.py           # Entry point
├── tests/
│   ├── unit/             # Espelha src/
│   ├── integration/      # Toca banco/serviços
│   └── conftest.py
├── scripts/              # Utilitários (seed, migrate)
├── docker/               # Dockerfile + docker-compose
├── docs/decisions/       # ADRs (Architecture Decision Records)
├── .env.example          # Template (NUNCA .env real no git)
└── pyproject.toml
```

## Regras Core

- Variáveis de ambiente NUNCA hardcoded — tudo via pydantic-settings
- Um serviço por container
- Health check obrigatório: `GET /health`
- Logs em stdout/stderr, nunca em arquivo no container
- Imagens slim/Alpine
- Sem root em produção
- `.env` no .gitignore, `.env.example` sempre atualizado
- ADRs em `docs/decisions/` para decisões de stack

## References

- @references/docker.md — Dockerfile multi-stage, docker-compose, .dockerignore
- @references/env-config.md — pydantic-settings, .env, secrets management
- @references/adr-template.md — Template para Architecture Decision Records
