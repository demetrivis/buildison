# Pydantic v2 Schemas

## Naming Convention

```python
# Request
class UserCreate(BaseModel):       # POST body
class UserUpdate(BaseModel):       # PUT body (todos os campos)
class UserPatch(BaseModel):        # PATCH body (campos opcionais)

# Response
class UserResponse(BaseModel):     # Individual
class UserListResponse(BaseModel): # Lista com paginação

# Query
class UserFilters(BaseModel):      # Query params
```

## Exemplo Completo

```python
from pydantic import BaseModel, EmailStr, Field
from datetime import datetime

# --- Request ---

class UserCreate(BaseModel):
    email: EmailStr
    name: str = Field(min_length=1, max_length=255)
    role: str = "user"

class UserUpdate(BaseModel):
    email: EmailStr
    name: str = Field(min_length=1, max_length=255)
    role: str

class UserPatch(BaseModel):
    email: EmailStr | None = None
    name: str | None = Field(default=None, min_length=1, max_length=255)
    role: str | None = None

# --- Response ---

class UserResponse(BaseModel):
    id: str
    email: str
    name: str
    role: str
    created_at: datetime
    updated_at: datetime | None = None

    model_config = {"from_attributes": True}

class UserListResponse(BaseModel):
    items: list[UserResponse]
    total: int
    page: int
    page_size: int

# --- Query ---

class UserFilters(BaseModel):
    role: str | None = None
    search: str | None = None
    created_after: datetime | None = None
```

## Validação Custom

```python
from pydantic import field_validator

class PaymentCreate(BaseModel):
    amount: float
    currency: str

    @field_validator("amount")
    @classmethod
    def amount_must_be_positive(cls, v):
        if v <= 0:
            raise ValueError("Amount must be positive")
        return round(v, 2)

    @field_validator("currency")
    @classmethod
    def currency_must_be_valid(cls, v):
        valid = {"USD", "EUR", "BRL"}
        if v.upper() not in valid:
            raise ValueError(f"Currency must be one of: {valid}")
        return v.upper()
```

## Regras

- Request e response NUNCA compartilham o mesmo model
- `from_attributes = True` em responses pra converter de ORM/dict
- Campos opcionais em Patch usam `Type | None = None`
- Validação via `field_validator` ou `model_validator`
- IDs nunca no request body de criação (são gerados pelo backend)
