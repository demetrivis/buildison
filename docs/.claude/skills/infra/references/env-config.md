# Environment & Config Reference

## pydantic-settings Setup

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    environment: str = "development"
    debug: bool = False

    # Database
    supabase_url: str
    supabase_key: str
    database_url: str

    # API
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    cors_origins: list[str] = ["http://localhost:3000"]

    # Auth
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    jwt_expiration_minutes: int = 30

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}

settings = Settings()
```

Localização: `src/shared/config.py`

## .env.example

```bash
# Environment
ENVIRONMENT=development
DEBUG=true

# Database
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-key
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/app

# API
API_HOST=0.0.0.0
API_PORT=8000
CORS_ORIGINS=["http://localhost:3000"]

# Auth
JWT_SECRET=change-me-in-production
JWT_ALGORITHM=HS256
JWT_EXPIRATION_MINUTES=30
```

## Regras

- `.env` NUNCA no git — está no .gitignore
- `.env.example` sempre atualizado com todas as variáveis e valores de exemplo
- Secrets nunca com valor default — devem falhar se ausentes
- Variáveis com default razoável podem ter valor padrão
- Usar `Field(alias="...")` se o nome da env var diferir do atributo

## Acesso no Código

```python
from src.shared.config import settings

# Usar assim
db_url = settings.database_url
is_debug = settings.debug
```

NUNCA acessar `os.environ` diretamente — sempre via `settings`.

## Validação de Config na Inicialização

```python
# Em main.py
from src.shared.config import settings

@app.on_event("startup")
async def validate_config():
    assert settings.jwt_secret != "change-me-in-production", "JWT_SECRET must be changed in production"
    assert settings.supabase_url.startswith("https://"), "SUPABASE_URL must use HTTPS"
```
