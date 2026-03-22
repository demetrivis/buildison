# PostgreSQL — Conexão Remota à VPS

## Setup do User na VPS

Executar no PostgreSQL da VPS (como superuser):

```sql
-- Criar user dedicado (NUNCA usar o superuser postgres na app)
CREATE USER app_user WITH PASSWORD 'strong-password-here';

-- Criar database
CREATE DATABASE app_db OWNER app_user;

-- Permissões
GRANT CONNECT ON DATABASE app_db TO app_user;
GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO app_user;
```

## Configurar pg_hba.conf na VPS

```
# /etc/postgresql/16/main/pg_hba.conf

# Conexões locais
local   all   postgres   peer
local   all   all        md5

# Conexões remotas via SSL
hostssl app_db app_user 0.0.0.0/0 md5
```

Depois: `sudo systemctl reload postgresql`

## postgresql.conf — Aceitar Conexões Remotas

```
listen_addresses = '*'          # ou o IP específico da interface
port = 5432
ssl = on
ssl_cert_file = '/etc/ssl/certs/ssl-cert-snakeoil.pem'
ssl_key_file = '/etc/ssl/private/ssl-cert-snakeoil.key'
```

## Firewall na VPS

```bash
# UFW — só permitir de IPs específicos
sudo ufw allow from YOUR_IP to any port 5432

# Ou permitir de qualquer lugar (menos seguro, depende de SSL + password)
sudo ufw allow 5432/tcp
```

## Conexão com asyncpg + Pool

```python
# src/db/pool.py
import asyncpg
import structlog
from src.shared.config import settings

logger = structlog.get_logger(__name__)

_pool: asyncpg.Pool | None = None

async def create_pool() -> asyncpg.Pool:
    global _pool
    _pool = await asyncpg.create_pool(
        dsn=settings.database_url,
        min_size=5,
        max_size=20,
        max_inactive_connection_lifetime=300,  # 5 min
        command_timeout=30,                     # 30s per query
        timeout=10,                             # 10s para adquirir conexão do pool
        ssl="require",                          # SSL obrigatório
    )
    logger.info("pg_pool_created", min_size=5, max_size=20, host=settings.pg_host)
    return _pool

async def close_pool() -> None:
    global _pool
    if _pool:
        await _pool.close()
        logger.info("pg_pool_closed")
        _pool = None

def get_pool() -> asyncpg.Pool:
    if not _pool:
        raise RuntimeError("Pool not initialized. Call create_pool() first.")
    return _pool
```

## Inicialização no main.py

```python
from src.db.pool import create_pool, close_pool

@app.on_event("startup")
async def startup():
    await create_pool()

@app.on_event("shutdown")
async def shutdown():
    await close_pool()
```

## Conexão com psycopg (sync, para scripts/migrations)

```python
import psycopg
from src.shared.config import settings

def get_sync_connection():
    return psycopg.connect(
        settings.database_url,
        connect_timeout=10,
        options="-c statement_timeout=30000",  # 30s
    )
```

## SSH Tunnel (dev local → VPS)

Quando a VPS não expõe a porta 5432 publicamente:

```bash
# Terminal — abre tunnel
ssh -L 5432:localhost:5432 user@vps-ip -N

# Agora conectar como se fosse local
DATABASE_URL=postgresql://app_user:password@localhost:5432/app_db
```

Via Python (sshtunnel):

```python
from sshtunnel import SSHTunnelForwarder

tunnel = SSHTunnelForwarder(
    ("vps-ip", 22),
    ssh_username="deploy",
    ssh_pkey="/path/to/key",
    remote_bind_address=("127.0.0.1", 5432),
    local_bind_address=("127.0.0.1", 5432),
)
tunnel.start()

# Agora conectar em localhost:5432
# ...

tunnel.stop()
```

## SSL com Certificado Custom

```python
import ssl

ssl_ctx = ssl.create_default_context(cafile="/path/to/ca-cert.pem")
ssl_ctx.check_hostname = True
ssl_ctx.verify_mode = ssl.CERT_REQUIRED

pool = await asyncpg.create_pool(
    dsn=settings.database_url,
    ssl=ssl_ctx,
    min_size=5,
    max_size=20,
)
```

## Troubleshooting

| Problema | Causa Provável | Solução |
|----------|---------------|---------|
| `connection refused` | PostgreSQL não escuta no IP público | Checar `listen_addresses` em postgresql.conf |
| `no pg_hba.conf entry` | IP não autorizado | Adicionar regra em pg_hba.conf |
| `SSL connection required` | Conectando sem SSL | Adicionar `?sslmode=require` na URL |
| `too many connections` | Pool muito grande ou leak | Reduzir max_size, checar se conexões são devolvidas |
| `connection timed out` | Firewall bloqueando | Checar UFW/iptables na VPS |
| `password authentication failed` | Credenciais erradas | Verificar user/password no pg_hba.conf e no .env |
