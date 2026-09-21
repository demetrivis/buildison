# Docker Reference

## Dockerfile Multi-Stage

```dockerfile
# ============================================
# Stage 1: Build
# ============================================
FROM python:3.12-slim AS builder
WORKDIR /app
COPY pyproject.toml .
RUN pip install --no-cache-dir --prefix=/install .

# ============================================
# Stage 2: Runtime
# ============================================
FROM python:3.12-slim

RUN groupadd -r app && useradd -r -g app -d /app -s /sbin/nologin app
WORKDIR /app

COPY --from=builder /install /usr/local
COPY src/ src/

RUN chown -R app:app /app
USER app

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

EXPOSE 8000
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## docker-compose.yml (Dev)

```yaml
services:
  api:
    build:
      context: .
      dockerfile: docker/Dockerfile
    ports:
      - "8000:8000"
    env_file: .env
    volumes:
      - ./src:/app/src
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: ${DB_NAME:-app}
      POSTGRES_USER: ${DB_USER:-postgres}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-postgres}
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  pgdata:
```

## .dockerignore

```
.git
.github
.claude
.env
.env.*
__pycache__
*.pyc
.pytest_cache
.mypy_cache
.ruff_cache
node_modules
.venv
venv
docker-compose*.yml
Dockerfile*
README.md
docs/
tests/
scripts/
*.log
*.md
```

## Checklist de Otimização

1. Multi-stage build (separar build deps de runtime)
2. Base slim/Alpine
3. Layer order: deps primeiro, source code por último
4. .dockerignore existe
5. Non-root user
6. HEALTHCHECK definido
7. Sem secrets na imagem
8. --no-cache-dir no pip
9. RUN commands combinados onde possível
10. COPY paths específicos, não COPY . .
