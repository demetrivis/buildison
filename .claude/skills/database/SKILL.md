---
name: database
description: "Supabase + PostgreSQL + Redis conventions: schema design, migrations, RLS, repositories, client setup, VPS connections, connection pools, caching. Use when designing tables, writing queries, creating migrations, configuring RLS policies, connecting to remote databases, setting up Redis cache, or working with the Supabase client."
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Database — Supabase + PostgreSQL + Redis

Convenções de banco de dados e cache do projeto. Supabase como BaaS, PostgreSQL como engine, Redis como cache/pub-sub. Acesso via client Python, SQL direto e redis-py.

## Stack

- **BaaS**: Supabase
- **Engine**: PostgreSQL 16
- **Cache**: Redis 7
- **Client Python**: supabase-py, asyncpg, redis-py
- **Migrations**: SQL puro em `src/db/migrations/`
- **ORM**: Nenhum — repositories com queries diretas
- **Auth**: Supabase Auth (JWT)

## Estrutura

```
src/db/
├── client.py             # Supabase client init
├── repositories/         # Um repo por entidade
│   ├── base.py           # BaseRepository com CRUD genérico
│   ├── user_repo.py
│   └── payment_repo.py
└── migrations/           # SQL files ordenados por timestamp
    ├── 001_create_users.sql
    ├── 002_create_payments.sql
    └── 003_add_rls_policies.sql
```

## Regras Core

- Tabelas em snake_case, plural: `users`, `payments`, `order_items`
- Colunas em snake_case: `created_at`, `user_id`, `is_active`
- Toda tabela tem: `id` (UUID), `created_at`, `updated_at`
- Foreign keys explícitas com ON DELETE definido
- Indexes em colunas usadas em WHERE e JOIN
- RLS ativado em TODAS as tabelas com dados de usuário
- Soft delete via `deleted_at` timestamp, nunca DELETE físico em entidades principais
- NUNCA queries SQL em routers — sempre via repository

## Naming de Constraints

```sql
-- Primary key
pk_users

-- Foreign key
fk_payments_user_id

-- Unique
uq_users_email

-- Index
idx_users_created_at
idx_payments_user_id_status

-- Check
ck_payments_amount_positive
```

## References

- @references/supabase-client.md — Inicialização do client, auth, storage
- @references/migrations.md — Padrão de migrations, schema design, tipos
- @references/rls.md — Row Level Security policies e patterns
- @references/repositories.md — Repository pattern, BaseRepository, queries
- @references/postgres-vps.md — Conexão remota PostgreSQL, pool asyncpg, SSL, SSH tunnel, user setup
- @references/redis-vps.md — Conexão remota Redis, pool, cache patterns, rate limiting, pub/sub
- @references/health-checks.md — Health checks de conectividade, retry com backoff, circuit breaker
