# Router Patterns

## Nomenclatura de Endpoints

| Operação | Método | Path | Função |
|----------|--------|------|--------|
| Listar | GET | `/users` | `list_users` |
| Buscar | GET | `/users/{user_id}` | `get_user` |
| Criar | POST | `/users` | `create_user` |
| Atualizar | PUT | `/users/{user_id}` | `update_user` |
| Patch | PATCH | `/users/{user_id}` | `patch_user` |
| Deletar | DELETE | `/users/{user_id}` | `delete_user` |

## Router Completo

```python
from fastapi import APIRouter, Depends, HTTPException, status
from src.api.schemas.users import UserCreate, UserResponse, UserListResponse
from src.api.dependencies.auth import get_current_user
from src.core.services.user_service import UserService

router = APIRouter(prefix="/api/v1/users", tags=["users"])

@router.post("/", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    payload: UserCreate,
    service: UserService = Depends(),
):
    return await service.create(payload)

@router.get("/", response_model=UserListResponse)
async def list_users(
    page: int = 1,
    page_size: int = 20,
    current_user=Depends(get_current_user),
    service: UserService = Depends(),
):
    return await service.list(page=page, page_size=page_size)

@router.get("/{user_id}", response_model=UserResponse)
async def get_user(
    user_id: str,
    current_user=Depends(get_current_user),
    service: UserService = Depends(),
):
    user = await service.get_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(
    user_id: str,
    current_user=Depends(get_current_user),
    service: UserService = Depends(),
):
    await service.delete(user_id)
```

## Registrando Routers

```python
# src/main.py
from fastapi import FastAPI
from src.api.routers import users, payments, health

app = FastAPI(title="My API", version="1.0.0")

app.include_router(health.router)
app.include_router(users.router)
app.include_router(payments.router)
```
