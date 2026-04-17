# /docker — Build e Gerenciamento de Imagens Docker

You have been invoked with the `/docker` command. Your job is to create, optimize, debug, and manage Dockerfiles and docker-compose configurations for this project.

## Instructions

1. **Assess the project**: Check what exists — Dockerfile, docker-compose.yml, .dockerignore. Understand the tech stack to choose the right base image and build strategy.

2. **Determine the need**: Is the user creating a new Dockerfile, optimizing an existing one, debugging a build failure, or setting up a full docker-compose environment?

3. **Build with best practices**: Follow the conventions below for secure, fast, and small images.

## Dockerfile Conventions

### Multi-stage builds (default approach)

```dockerfile
# ============================================
# Stage 1: Build
# ============================================
FROM python:3.12-slim AS builder

WORKDIR /app

# Dependencies first (cache layer)
COPY pyproject.toml .
RUN pip install --no-cache-dir --prefix=/install .

# ============================================
# Stage 2: Runtime
# ============================================
FROM python:3.12-slim

# Security: non-root user
RUN groupadd -r app && useradd -r -g app -d /app -s /sbin/nologin app

WORKDIR /app

# Copy only installed packages
COPY --from=builder /install /usr/local
COPY src/ src/

# Own files as app user
RUN chown -R app:app /app
USER app

# Health check
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

EXPOSE 8000

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### .dockerignore (always create alongside Dockerfile)

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

### Build best practices

- **Order layers by change frequency**: dependencies first (cached), source code last (changes often)
- **Slim/Alpine base images**: `python:3.12-slim`, `node:20-alpine` — never use full images in production
- **No root**: always create and switch to a non-root user
- **Single process per container**: never run multiple services in one container
- **HEALTHCHECK**: always include one
- **EXPOSE**: document the ports
- **Labels**: add metadata for traceability

```dockerfile
LABEL org.opencontainers.image.source="https://github.com/user/repo"
LABEL org.opencontainers.image.description="Service description"
```

## docker-compose Conventions

### Development environment

```yaml
services:
  api:
    build:
      context: .
      dockerfile: docker/Dockerfile
      target: builder  # Use build stage for dev (has dev deps)
    ports:
      - "8000:8000"
    env_file: .env
    volumes:
      - ./src:/app/src  # Hot reload
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

### Production compose

```yaml
services:
  api:
    image: ghcr.io/user/repo:latest
    ports:
      - "8000:8000"
    env_file: .env.production
    depends_on:
      db:
        condition: service_healthy
    restart: always
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: "0.5"
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

## Common Tasks

### Build image
```bash
docker build -t app:latest -f docker/Dockerfile .
```

### Build with build args
```bash
docker build --build-arg PYTHON_VERSION=3.12 -t app:latest .
```

### Tag and push to GHCR
```bash
docker tag app:latest ghcr.io/user/repo:latest
docker push ghcr.io/user/repo:latest
```

### Analyze image size
```bash
docker images app:latest --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
docker history app:latest
```

### Debug build failures
```bash
# Build with progress output
docker build --progress=plain -f docker/Dockerfile .

# Build up to a specific stage
docker build --target builder -f docker/Dockerfile .

# Run a shell in the build stage to debug
docker run --rm -it $(docker build -q --target builder .) /bin/sh
```

## Optimization Checklist

When reviewing or optimizing a Dockerfile:

1. Multi-stage build? (separate build deps from runtime)
2. Slim/Alpine base? (not the full image)
3. Layer order correct? (deps before source code)
4. .dockerignore exists? (excludes .git, tests, docs, etc.)
5. No root user? (USER directive present)
6. HEALTHCHECK defined?
7. No secrets in the image? (use build secrets or env vars at runtime)
8. --no-cache-dir on pip install?
9. Combined RUN commands where possible? (reduce layers)
10. COPY specific paths, not COPY . .? (better cache invalidation)

## Subagent Usage

For complex Docker setups, spawn subagents:
- **Multi-service**: 1 subagent per Dockerfile when the project has multiple services
- **Optimization**: 1 subagent to analyze the current image size and layers, another to rewrite the Dockerfile
- **Migration**: 1 subagent to read the existing deployment config, another to write the Docker equivalent

## Rules

- Always create .dockerignore alongside new Dockerfiles
- Never put secrets (passwords, keys, tokens) in the Dockerfile or image layers
- Use specific version tags for base images, never `latest` in Dockerfiles
- Test the build locally before considering it done: `docker build .`
- Logs go to stdout/stderr, never to files inside the container
- If the project already has a Dockerfile, read it first before suggesting changes
