# /docker — Build e Gerenciamento de Imagens Docker

You have been invoked with the `/docker` command. Your job is to create, optimize, debug, and manage Dockerfiles and docker-compose configurations for this project.

## Instructions

1. **Assess the project**: Check what exists — Dockerfile, docker-compose.yml, .dockerignore. Read the project manifest (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, etc.) to understand the tech stack and choose the right base image and build strategy.

2. **Determine the need**: Is the user creating a new Dockerfile, optimizing an existing one, debugging a build failure, or setting up a full docker-compose environment?

3. **Build with best practices**: Follow the conventions below for secure, fast, and small images.

## Dockerfile Conventions

### Multi-stage builds (default approach)

Always use multi-stage builds to separate build dependencies from the runtime image. Adapt the base image and install commands to the project's stack:

**Python**
```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
COPY pyproject.toml .
RUN pip install --no-cache-dir --prefix=/install .

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
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Node.js**
```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json .
RUN npm ci --only=production

FROM node:20-alpine
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY src/ src/
RUN chown -R app:app /app
USER app
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1
EXPOSE 3000
CMD ["node", "src/index.js"]
```

**Go**
```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/server ./cmd/server

FROM alpine:3.19
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=builder /app/server .
USER app
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1
EXPOSE 8080
CMD ["./server"]
```

### .dockerignore (always create alongside Dockerfile)

```
.git
.github
.claude
.env
.env.*
# Python
__pycache__
*.pyc
.pytest_cache
.mypy_cache
.ruff_cache
.venv
venv
# Node
node_modules
.next
dist
# Generic
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
- **Slim/Alpine base images**: `python:3.12-slim`, `node:20-alpine`, `golang:1.22-alpine` — never use full images in production
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
8. Cache-friendly install commands? (pip: `--no-cache-dir`, npm: `npm ci`)
9. Combined RUN commands where possible? (reduce layers)
10. COPY specific paths, not COPY . .? (better cache invalidation)

## Rules

- Always create .dockerignore alongside new Dockerfiles
- Never put secrets (passwords, keys, tokens) in the Dockerfile or image layers
- Use specific version tags for base images, never `latest` in Dockerfiles
- Test the build locally before considering it done: `docker build .`
- Logs go to stdout/stderr, never to files inside the container
- If the project already has a Dockerfile, read it first before suggesting changes
