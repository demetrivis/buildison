# Row Level Security (RLS) Reference

## Ativar RLS

```sql
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- IMPORTANTE: Force RLS para o table owner também (senão owner bypassa)
ALTER TABLE users FORCE ROW LEVEL SECURITY;
```

## Padrões Comuns

### User só vê seus próprios dados

```sql
-- Select
CREATE POLICY "Users can view own data"
    ON users FOR SELECT
    USING (auth.uid() = id);

-- Update
CREATE POLICY "Users can update own data"
    ON users FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Delete (soft)
CREATE POLICY "Users can soft delete own data"
    ON users FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id AND deleted_at IS NOT NULL);
```

### User vê seus dados + dados relacionados

```sql
-- Payments do próprio user
CREATE POLICY "Users can view own payments"
    ON payments FOR SELECT
    USING (auth.uid() = user_id);

-- Insert só para si mesmo
CREATE POLICY "Users can create own payments"
    ON payments FOR INSERT
    WITH CHECK (auth.uid() = user_id);
```

### Admin vê tudo

```sql
-- Função helper para checar role
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN (
        SELECT role = 'admin'
        FROM users
        WHERE id = auth.uid()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Policy de admin
CREATE POLICY "Admins can view all users"
    ON users FOR SELECT
    USING (is_admin() OR auth.uid() = id);

CREATE POLICY "Admins can update all users"
    ON users FOR UPDATE
    USING (is_admin())
    WITH CHECK (is_admin());
```

### Dados públicos (read-only para todos)

```sql
CREATE POLICY "Anyone can view published posts"
    ON posts FOR SELECT
    USING (status = 'published' AND deleted_at IS NULL);
```

### Multi-tenant (por organização)

```sql
CREATE POLICY "Users can view org data"
    ON projects FOR SELECT
    USING (
        org_id IN (
            SELECT org_id FROM org_members
            WHERE user_id = auth.uid()
        )
    );
```

## Funções Helper do Supabase

```sql
-- auth.uid() → UUID do user autenticado
-- auth.jwt() → JSON completo do JWT
-- auth.role() → Role do JWT (anon, authenticated, service_role)

-- Exemplo: checar claim custom do JWT
CREATE POLICY "Premium users only"
    ON premium_content FOR SELECT
    USING (
        (auth.jwt() ->> 'user_role') = 'premium'
    );
```

## Migration de RLS

```sql
-- 003_add_rls_policies.sql

-- Enable RLS on all user-data tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments FORCE ROW LEVEL SECURITY;

-- Users
CREATE POLICY "users_select_own" ON users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "users_update_own" ON users FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
CREATE POLICY "users_select_admin" ON users FOR SELECT USING (is_admin());

-- Payments
CREATE POLICY "payments_select_own" ON payments FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "payments_insert_own" ON payments FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "payments_select_admin" ON payments FOR ALL USING (is_admin());
```

## Regras

- RLS ativado em TODA tabela com dados de usuário
- Sempre usar `FORCE ROW LEVEL SECURITY` para incluir table owner
- Policies nomeadas descritivamente: `"users_select_own"`, `"payments_insert_own"`
- USING = filtro para SELECT/UPDATE/DELETE (linhas visíveis)
- WITH CHECK = filtro para INSERT/UPDATE (linhas que podem ser escritas)
- Funções helper marcadas como `SECURITY DEFINER` para rodar com permissão elevada
- Testar policies com `SET ROLE authenticated` antes de deployar
- Service role key bypassa RLS — NUNCA expor no client
