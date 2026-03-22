---
name: api
description: "FastAPI conventions: routing, schemas, error handling, dependencies, and HTTP contracts. Use when creating endpoints, designing request/response schemas, handling errors, or working with middlewares."
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# API / HTTP

Convenções da camada HTTP do projeto. FastAPI + Pydantic v2 + Uvicorn.

## Estrutura

```
src/api/
├── routers/          # Um arquivo por domínio
├── schemas/          # Request/response Pydantic models
├── dependencies/     # FastAPI Depends() (auth, db session)
└── middlewares/       # Logging, CORS, error handling
```

## Regras Core

- Todas as rotas sob `/api/v1/`
- Routers NÃO contêm lógica de negócio — delegam para services
- Schemas de request e response SEMPRE separados
- Todo endpoint com side-effect precisa de autenticação
- Paginação obrigatória em listas: `page`, `page_size`, `total`
- IDs em path params, filtros em query params, dados em body
- Erros retornam `{"detail": "mensagem legível"}`

## Status Codes

- 200: GET/PUT/PATCH com dados
- 201: POST que cria
- 204: DELETE sem body
- 400/401/403/404/409/422/429: erros do cliente
- 500/503: erros do servidor

## Schema Naming

- `UserCreate`, `UserUpdate`, `UserPatch` (request)
- `UserResponse`, `UserListResponse` (response)
- `UserFilters` (query params)

## References

- @references/routers.md — Padrão completo de router com exemplos
- @references/schemas.md — Pydantic v2 schemas, validação, serialização
- @references/error-handling.md — Error handlers, domain-to-HTTP mapping, dependencies
