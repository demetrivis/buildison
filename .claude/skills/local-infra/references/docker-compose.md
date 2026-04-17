# docker-compose.yml completo

Versão completa e comentada do stack local (`~/local-infra/docker-compose.yml`).

```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: local-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: localdev
      POSTGRES_DB: dev
      # Diretório onde scripts de init são executados na primeira inicialização
      PGDATA: /var/lib/postgresql/data/pgdata
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
      # Scripts .sql ou .sh aqui rodam uma vez quando o volume é criado
      - ./postgres-init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dev -d dev"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    networks:
      - local-infra

  redis:
    image: redis:7-alpine
    container_name: local-redis
    restart: unless-stopped
    command: >
      redis-server
      --appendonly yes
      --maxmemory 512mb
      --maxmemory-policy allkeys-lru
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    networks:
      - local-infra

  ngrok:
    image: ngrok/ngrok:latest
    container_name: local-ngrok
    restart: unless-stopped
    environment:
      NGROK_AUTHTOKEN: ${NGROK_AUTHTOKEN}
    # Modo "tunnel sob demanda" — sobe o dashboard em :4040 e você
    # cria tunnels via `docker exec local-ngrok ngrok http <host>:<porta>`
    command: "http --log=stdout host.docker.internal:8000"
    ports:
      - "4040:4040"   # dashboard web
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - local-infra
    depends_on:
      - postgres
      - redis

volumes:
  postgres-data:
    name: local-postgres-data
  redis-data:
    name: local-redis-data

networks:
  local-infra:
    name: local-infra
    driver: bridge
```

## Notas

- **`container_name` fixo**: facilita `docker exec -it local-postgres ...` sem precisar descobrir o nome gerado
- **`restart: unless-stopped`**: sobe junto com o Docker Desktop após reboot, mas respeita `docker compose down`
- **Volumes nomeados** (`local-postgres-data`, `local-redis-data`): sobrevivem a `docker compose down`; para apagar dados usar `docker compose down -v`
- **Network `local-infra`**: permite que containers de outros projetos se conectem via `docker network connect local-infra <meu-container>` se preferir comunicação interna sem passar por `host.docker.internal`
- **`host-gateway`**: garante que `host.docker.internal` resolva corretamente em Linux (no macOS/Windows Docker Desktop já resolve nativamente)
- **ngrok com tunnel fixo**: o command `http --log=stdout host.docker.internal:8000` cria um tunnel permanente pra porta 8000 do host. Ajusta conforme a porta do teu app. Para tunnels ad-hoc, substitui por `command: ""` e usa `docker exec`

## Ajustar Redis para dev

Se precisar de Redis sem persistência (mais rápido, limpa a cada restart):

```yaml
command: redis-server --save "" --appendonly no
```

## Adicionar extensions no Postgres de primeira

Criar `~/local-infra/postgres-init/01-extensions.sql`:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
```

Esse arquivo roda **apenas uma vez**, quando o volume `local-postgres-data` é criado do zero. Se você já subiu antes e quer aplicar, rode manualmente:

```bash
docker exec -it local-postgres psql -U dev -d dev -f /docker-entrypoint-initdb.d/01-extensions.sql
```
