# Repository Pattern Reference

## Base Repository

```python
# src/db/repositories/base.py
from typing import TypeVar, Generic, Any
from supabase import Client
import structlog

T = TypeVar("T")
logger = structlog.get_logger(__name__)

class BaseRepository(Generic[T]):
    def __init__(self, client: Client, table_name: str):
        self.client = client
        self.table = table_name
        self.logger = structlog.get_logger(f"src.db.repositories.{table_name}")

    async def get_by_id(self, id: str) -> dict | None:
        response = (
            self.client.table(self.table)
            .select("*")
            .eq("id", id)
            .is_("deleted_at", "null")
            .single()
            .execute()
        )
        return response.data

    async def list(
        self,
        page: int = 1,
        page_size: int = 20,
        order_by: str = "created_at",
        ascending: bool = False,
    ) -> tuple[list[dict], int]:
        start = (page - 1) * page_size
        end = start + page_size - 1

        response = (
            self.client.table(self.table)
            .select("*", count="exact")
            .is_("deleted_at", "null")
            .order(order_by, desc=not ascending)
            .range(start, end)
            .execute()
        )
        return response.data, response.count

    async def create(self, data: dict) -> dict:
        response = (
            self.client.table(self.table)
            .insert(data)
            .execute()
        )
        self.logger.info(f"{self.table}_created", id=response.data[0]["id"])
        return response.data[0]

    async def update(self, id: str, data: dict) -> dict:
        response = (
            self.client.table(self.table)
            .update(data)
            .eq("id", id)
            .execute()
        )
        self.logger.info(f"{self.table}_updated", id=id)
        return response.data[0]

    async def soft_delete(self, id: str) -> None:
        from datetime import datetime, timezone
        self.client.table(self.table).update({
            "deleted_at": datetime.now(timezone.utc).isoformat(),
        }).eq("id", id).execute()
        self.logger.info(f"{self.table}_soft_deleted", id=id)

    async def exists(self, **filters) -> bool:
        query = self.client.table(self.table).select("id").is_("deleted_at", "null")
        for key, value in filters.items():
            query = query.eq(key, value)
        response = query.limit(1).execute()
        return len(response.data) > 0
```

## Repository Específico

```python
# src/db/repositories/user_repo.py
from src.db.repositories.base import BaseRepository
from src.db.client import supabase

class UserRepository(BaseRepository):
    def __init__(self):
        super().__init__(client=supabase, table_name="users")

    async def find_by_email(self, email: str) -> dict | None:
        response = (
            self.client.table(self.table)
            .select("*")
            .eq("email", email)
            .is_("deleted_at", "null")
            .single()
            .execute()
        )
        return response.data

    async def list_by_role(self, role: str, page: int = 1, page_size: int = 20) -> tuple[list[dict], int]:
        start = (page - 1) * page_size
        end = start + page_size - 1

        response = (
            self.client.table(self.table)
            .select("*", count="exact")
            .eq("role", role)
            .is_("deleted_at", "null")
            .order("created_at", desc=True)
            .range(start, end)
            .execute()
        )
        return response.data, response.count

    async def update_role(self, user_id: str, role: str) -> dict:
        return await self.update(user_id, {"role": role})
```

## Uso nos Services

```python
# src/core/services/user_service.py
from src.db.repositories.user_repo import UserRepository
from src.core.exceptions import ConflictError, NotFoundError

class UserService:
    def __init__(self):
        self.repo = UserRepository()

    async def create(self, data: UserCreate) -> dict:
        if await self.repo.exists(email=data.email):
            raise ConflictError("Email already registered")
        return await self.repo.create(data.model_dump())

    async def get_by_id(self, user_id: str) -> dict:
        user = await self.repo.get_by_id(user_id)
        if not user:
            raise NotFoundError("User not found")
        return user
```

## Queries Complexas via asyncpg

Para queries que o client Supabase não suporta bem:

```python
# src/db/repositories/analytics_repo.py
import asyncpg
from src.shared.config import settings

class AnalyticsRepository:
    def __init__(self, pool: asyncpg.Pool):
        self.pool = pool

    async def revenue_by_month(self, year: int) -> list[dict]:
        query = """
            SELECT
                DATE_TRUNC('month', created_at) AS month,
                SUM(amount) AS total,
                COUNT(*) AS count
            FROM payments
            WHERE EXTRACT(YEAR FROM created_at) = $1
              AND status = 'completed'
              AND deleted_at IS NULL
            GROUP BY DATE_TRUNC('month', created_at)
            ORDER BY month
        """
        async with self.pool.acquire() as conn:
            rows = await conn.fetch(query, year)
            return [dict(row) for row in rows]
```

## Regras

- Um repository por entidade/tabela
- Repositories herdam de BaseRepository para CRUD padrão
- Métodos custom para queries específicas do domínio
- NUNCA expor o Supabase client fora do repository
- Services usam repositories, NUNCA queries diretas
- Routers usam services, NUNCA repositories diretamente
- Toda query filtra `deleted_at IS NULL` por padrão
- Logging em operações de escrita (create, update, delete)
- asyncpg para queries complexas (analytics, reports, bulk)
