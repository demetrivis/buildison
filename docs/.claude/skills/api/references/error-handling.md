# Error Handling & Dependencies

## Global Exception Handler

```python
from fastapi import Request
from fastapi.responses import JSONResponse
import structlog

logger = structlog.get_logger(__name__)

async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.error(
        "unhandled_exception",
        path=request.url.path,
        method=request.method,
        error=str(exc),
        error_type=type(exc).__name__,
    )
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"},
    )
```

## Domain-to-HTTP Mapping

Erros de domínio mapeados no middleware, NUNCA dentro do service:

```python
from src.core.exceptions import NotFoundError, ConflictError, ForbiddenError, ValidationError

DOMAIN_TO_HTTP = {
    NotFoundError: 404,
    ConflictError: 409,
    ForbiddenError: 403,
    ValidationError: 400,
}

async def domain_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    status_code = DOMAIN_TO_HTTP.get(type(exc), 500)
    logger.warning(
        "domain_error",
        path=request.url.path,
        error_type=type(exc).__name__,
        detail=str(exc),
        status_code=status_code,
    )
    return JSONResponse(status_code=status_code, content={"detail": str(exc)})
```

## Registrando Handlers

```python
# src/main.py
from src.core.exceptions import DomainError

app.add_exception_handler(Exception, global_exception_handler)
app.add_exception_handler(DomainError, domain_exception_handler)
```

## Domain Exceptions

```python
# src/core/exceptions.py

class DomainError(Exception):
    """Base para erros de domínio."""
    pass

class NotFoundError(DomainError):
    pass

class ConflictError(DomainError):
    pass

class ForbiddenError(DomainError):
    pass

class ValidationError(DomainError):
    pass
```

## Auth Dependencies

```python
from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/token")

async def get_current_user(token: str = Depends(oauth2_scheme)) -> User:
    user = await verify_token(token)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return user

def require_role(*roles: str):
    async def checker(user=Depends(get_current_user)):
        if user.role not in roles:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        return user
    return checker

# Uso
@router.get("/admin/users", dependencies=[Depends(require_role("admin"))])
async def admin_list_users(): ...

@router.get("/me")
async def get_me(user=Depends(get_current_user)): ...
```

## Database Session Dependency

```python
from src.db.client import get_session

async def get_db():
    async with get_session() as session:
        yield session

# Uso
@router.get("/users")
async def list_users(db=Depends(get_db)): ...
```

## Status Code Reference

```python
# Sucesso
200  # GET, PUT, PATCH com dados
201  # POST que cria recurso
204  # DELETE ou operação sem body

# Erro do cliente
400  # Validação custom falhou
401  # Não autenticado
403  # Sem permissão
404  # Não encontrado
409  # Conflito (duplicata)
422  # Validação Pydantic (FastAPI auto)
429  # Rate limit

# Erro do servidor
500  # Erro interno
503  # Dependência fora
```
