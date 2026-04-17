# Migrations Reference

## Estrutura

```
src/db/migrations/
├── 001_create_users.sql
├── 002_create_payments.sql
├── 003_create_order_items.sql
└── 004_add_rls_policies.sql
```

Numeração sequencial com zero-padding. Nome descritivo do que faz.

## Template de Tabela

```sql
-- 001_create_users.sql

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL,
    name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'user',
    is_active BOOLEAN NOT NULL DEFAULT true,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT ck_users_role CHECK (role IN ('user', 'admin', 'moderator'))
);

-- Indexes
CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_created_at ON users (created_at DESC);
CREATE INDEX idx_users_role ON users (role) WHERE deleted_at IS NULL;

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();
```

## Tipos Comuns

| Dado | Tipo PostgreSQL | Notas |
|------|----------------|-------|
| ID | `UUID` | `gen_random_uuid()` |
| Email | `TEXT` | Com UNIQUE constraint |
| Nome | `TEXT` | Sem limite artificial |
| Status/Enum | `TEXT` com CHECK | Não usar ENUM type (difícil de alterar) |
| Dinheiro | `NUMERIC(12,2)` | NUNCA float/double |
| Flag | `BOOLEAN` | Com DEFAULT |
| Timestamp | `TIMESTAMPTZ` | Sempre com timezone |
| JSON flexível | `JSONB` | Com index GIN se filtrado |
| Array | `TEXT[]` | Usar com moderação |

## Foreign Keys

```sql
CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'BRL',
    status TEXT NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT fk_payments_user_id FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT ck_payments_amount_positive CHECK (amount > 0),
    CONSTRAINT ck_payments_status CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'refunded'))
);

CREATE INDEX idx_payments_user_id ON payments (user_id);
CREATE INDEX idx_payments_status ON payments (status) WHERE status IN ('pending', 'processing');
CREATE INDEX idx_payments_created_at ON payments (created_at DESC);
```

## ON DELETE Policies

| Relação | Policy | Quando |
|---------|--------|--------|
| User → Payments | `RESTRICT` | Não apagar user com payments |
| Order → OrderItems | `CASCADE` | Apagar items junto com order |
| User → Sessions | `CASCADE` | Limpar sessions ao apagar user |
| Post → Comments | `SET NULL` | Manter comments órfãos |

## Partial Indexes

Usar quando queries filtram por condição fixa:

```sql
-- Só users ativos
CREATE INDEX idx_users_active ON users (email) WHERE deleted_at IS NULL AND is_active = true;

-- Só payments pendentes
CREATE INDEX idx_payments_pending ON payments (created_at) WHERE status = 'pending';
```

## Regras

- NUNCA usar `SERIAL` — sempre UUID com `gen_random_uuid()`
- NUNCA usar `ENUM` type — usar TEXT com CHECK (mais fácil de migrar)
- NUNCA usar `FLOAT` para dinheiro — usar NUMERIC
- SEMPRE `TIMESTAMPTZ`, nunca `TIMESTAMP` sem timezone
- Toda FK precisa de index na coluna referenciadora
- Soft delete com `deleted_at` em entidades principais
- Trigger de `updated_at` em toda tabela com esse campo
