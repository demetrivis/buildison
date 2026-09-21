---
name: api
description: "HTTP layer conventions: routing, schemas/DTOs, error handling, middleware, and API contracts. Use when creating endpoints, designing request/response schemas, handling errors, or working with middlewares."
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# API / HTTP

Convenções da camada HTTP do projeto. Adapte à framework em uso (FastAPI, Express, Hono, Gin, etc.).

## Estrutura

```
<src>/
└── api/
    ├── routes/       # Um arquivo por domínio
    ├── schemas/      # Request/response models (Pydantic, Zod, class-validator, etc.)
    ├── middleware/   # Logging, CORS, auth, error handling
    └── deps/         # Injeção de dependências (auth, db session, etc.)
```

## Regras Core

- Todas as rotas sob `/api/v1/` (ou conforme convenção do projeto)
- Route handlers NÃO contêm lógica de negócio — delegam para services
- Schemas de request e response SEMPRE separados
- Todo endpoint com side-effect precisa de autenticação
- Paginação obrigatória em listas: `page`, `page_size`, `total`
- IDs em path params, filtros em query params, dados em body
- Erros retornam `{"detail": "mensagem legível"}` ou formato equivalente do projeto

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

- @references/routers.md — Padrão completo de route handler com exemplos
- @references/schemas.md — Schemas de validação, serialização
- @references/error-handling.md — Error handlers, domain-to-HTTP mapping, middleware
