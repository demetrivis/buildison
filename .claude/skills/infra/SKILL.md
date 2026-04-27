---
name: infra
description: "Project infrastructure conventions: folder structure, Docker, env vars, deployment, and architectural decisions. Use when setting up project structure, configuring Docker, managing environment variables, or making infrastructure decisions."
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Infrastructure

Convenções de infraestrutura, estrutura de projeto, Docker, variáveis de ambiente e decisões de arquitetura.

## Stack Base

Adapte conforme o projeto — documente a stack real aqui:

- **Runtime**: (ex: Python 3.12, Node 20, Go 1.22)
- **Framework**: (ex: FastAPI, Express, Gin)
- **Database**: (ex: PostgreSQL 16, MySQL, SQLite)
- **Container**: Docker multi-stage builds
- **Config**: variáveis de ambiente via arquivo `.env` ou secrets manager

## Estrutura de Pastas

Estrutura sugerida — adapte ao padrão da linguagem/framework:

```
project-root/
├── src/               # Código fonte
│   ├── api/           # Camada HTTP (routes, schemas, middleware)
│   ├── core/          # Lógica de negócio (services, domain, exceptions)
│   ├── db/            # Acesso a dados (repositories, migrations)
│   └── shared/        # Transversal (logging, config, constants)
├── tests/
│   ├── unit/
│   └── integration/
├── scripts/           # Utilitários (seed, migrate, etc.)
├── docker/            # Dockerfile + docker-compose
├── docs/decisions/    # ADRs (Architecture Decision Records)
└── .env.example       # Template (NUNCA .env real no git)
```

## Regras Core

- Variáveis de ambiente NUNCA hardcoded — sempre via config/env
- Um serviço por container
- Health check obrigatório: `GET /health`
- Logs em stdout/stderr, nunca em arquivo no container
- Imagens slim/Alpine
- Sem root em produção
- `.env` no .gitignore, `.env.example` sempre atualizado
- ADRs em `docs/decisions/` para decisões de stack

## References

- @references/docker.md — Dockerfile multi-stage, docker-compose, .dockerignore
- @references/env-config.md — Gerenciamento de variáveis de ambiente e secrets
- @references/adr-template.md — Template para Architecture Decision Records
