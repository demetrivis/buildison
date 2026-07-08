---
name: golang
description: "Go backend conventions: handlers, services, repositories, context propagation, error handling, testing, project structure, and production-ready APIs. Use when working on Go projects using Gin, Fiber, Chi, Echo or standard net/http."
---

<!-- Gerado de .claude/skills/golang/SKILL.md por scripts/gen-antigravity.mjs — não edite à mão. -->

# Golang Backend

Convenções para projetos backend em Go.

## Stack

- Language: Go 1.23+
- HTTP: Gin, Fiber, Chi, Echo ou net/http
- Database: PostgreSQL
- Migrations: SQL ou Goose
- Testing: testing + testify

## Estrutura Recomendada

```txt
cmd/
internal/
├── api/
├── service/
├── repository/
├── domain/
├── config/
└── infra/
pkg/
```

## Regras Core

- Handlers não contêm regra de negócio.
- Services contêm regras de negócio.
- Repositories encapsulam persistência.
- Propague context.Context em operações I/O.
- Nunca acesse banco diretamente em handlers.
- Erros devem ser embrulhados com contexto.
- Dependências explícitas via construtores.
- Interfaces apenas quando houver necessidade real.
- Testes table-driven quando apropriado.
- Health check obrigatório.

## Error Handling

- Erros de domínio não conhecem HTTP.
- Mapeamento para status HTTP acontece na camada API.
- Nunca exponha detalhes internos ao cliente.

## References

- @references/handlers.md
- @references/services.md
- @references/repositories.md
- @references/testing.md
- @references/error-handling.md
