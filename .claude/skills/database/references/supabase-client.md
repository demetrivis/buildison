# Supabase Client Reference

## Inicialização

```python
# src/db/client.py
from supabase import create_client, Client
from src.shared.config import settings

supabase: Client = create_client(
    settings.supabase_url,
    settings.supabase_key,
)
```

## Variáveis Necessárias

```bash
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-key  # anon key para client-side, service_role para server-side
DATABASE_URL=postgresql://postgres:password@db.your-project.supabase.co:5432/postgres
```

- `SUPABASE_KEY` (anon): respeita RLS, usa para operações autenticadas
- `SUPABASE_KEY` (service_role): ignora RLS, usa APENAS em server-side para operações admin

## CRUD via Client

### Select
```python
# Buscar todos
response = supabase.table("users").select("*").execute()

# Com filtro
response = supabase.table("users").select("*").eq("email", email).single().execute()

# Com paginação
response = supabase.table("users").select("*", count="exact").range(0, 19).execute()
total = response.count

# Com ordenação
response = supabase.table("users").select("*").order("created_at", desc=True).execute()

# Colunas específicas
response = supabase.table("users").select("id, email, name").execute()

# Join (foreign key)
response = supabase.table("payments").select("*, users(name, email)").execute()
```

### Insert
```python
response = supabase.table("users").insert({
    "email": "user@example.com",
    "name": "John Doe",
}).execute()
```

### Update
```python
response = supabase.table("users").update({
    "name": "Jane Doe",
    "updated_at": "now()",
}).eq("id", user_id).execute()
```

### Delete (soft)
```python
response = supabase.table("users").update({
    "deleted_at": "now()",
}).eq("id", user_id).execute()
```

## Auth via Client

```python
# Sign up
response = supabase.auth.sign_up({"email": email, "password": password})

# Sign in
response = supabase.auth.sign_in_with_password({"email": email, "password": password})

# Get user from JWT
response = supabase.auth.get_user(jwt_token)

# Sign out
supabase.auth.sign_out()
```

## Storage

```python
# Upload
supabase.storage.from_("avatars").upload(
    path=f"users/{user_id}/avatar.png",
    file=file_bytes,
    file_options={"content-type": "image/png"},
)

# Get public URL
url = supabase.storage.from_("avatars").get_public_url(f"users/{user_id}/avatar.png")

# Download
data = supabase.storage.from_("avatars").download(f"users/{user_id}/avatar.png")

# Delete
supabase.storage.from_("avatars").remove([f"users/{user_id}/avatar.png"])
```

## Acesso Direto ao PostgreSQL

Para queries complexas (reports, analytics, bulk operations), usar asyncpg direto:

```python
import asyncpg
from src.shared.config import settings

async def get_db_pool():
    return await asyncpg.create_pool(settings.database_url, min_size=5, max_size=20)

async def execute_query(pool, query: str, *args):
    async with pool.acquire() as conn:
        return await conn.fetch(query, *args)
```

Usar client Supabase para CRUD simples. Usar asyncpg para queries complexas, joins pesados, aggregations, e bulk operations.
