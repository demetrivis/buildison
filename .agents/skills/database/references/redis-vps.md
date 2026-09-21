# Redis — Conexão Remota à VPS

## Setup do Redis na VPS

```bash
# Instalar
sudo apt install redis-server -y

# Configurar
sudo nano /etc/redis/redis.conf
```

### redis.conf — Configurações Essenciais

```conf
# Aceitar conexões remotas (default é só 127.0.0.1)
bind 0.0.0.0

# Porta
port 6379

# Password OBRIGATÓRIO para acesso remoto
requirepass strong-redis-password-here

# Proteção contra comandos perigosos
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command CONFIG "CONFIG_secret_prefix"

# Limites de memória
maxmemory 256mb
maxmemory-policy allkeys-lru

# Persistência (RDB + AOF)
save 900 1
save 300 10
save 60 10000
appendonly yes

# TLS (opcional mas recomendado)
# tls-port 6380
# tls-cert-file /path/to/redis.crt
# tls-key-file /path/to/redis.key
# tls-ca-cert-file /path/to/ca.crt
```

Depois: `sudo systemctl restart redis-server`

### Firewall

```bash
sudo ufw allow from YOUR_IP to any port 6379
```

## Conexão com redis-py (async)

```python
# src/cache/client.py
import redis.asyncio as redis
import structlog
from src.shared.config import settings

logger = structlog.get_logger(__name__)

_redis: redis.Redis | None = None

async def create_redis() -> redis.Redis:
    global _redis
    _redis = redis.Redis(
        host=settings.redis_host,
        port=settings.redis_port,
        password=settings.redis_password,
        db=settings.redis_db,
        decode_responses=True,
        socket_timeout=5,
        socket_connect_timeout=5,
        retry_on_timeout=True,
        max_connections=20,
        health_check_interval=30,
    )
    # Testar conexão
    await _redis.ping()
    logger.info("redis_connected", host=settings.redis_host, port=settings.redis_port)
    return _redis

async def close_redis() -> None:
    global _redis
    if _redis:
        await _redis.close()
        logger.info("redis_disconnected")
        _redis = None

def get_redis() -> redis.Redis:
    if not _redis:
        raise RuntimeError("Redis not initialized. Call create_redis() first.")
    return _redis
```

## Conexão via URL

```python
_redis = redis.Redis.from_url(
    settings.redis_url,  # redis://:password@host:6379/0
    decode_responses=True,
    socket_timeout=5,
    max_connections=20,
)
```

## Inicialização no main.py

```python
from src.cache.client import create_redis, close_redis

@app.on_event("startup")
async def startup():
    await create_pool()    # PostgreSQL
    await create_redis()   # Redis

@app.on_event("shutdown")
async def shutdown():
    await close_redis()
    await close_pool()
```

## Cache Patterns

### Simple get/set

```python
async def get_user_cached(user_id: str) -> dict | None:
    r = get_redis()
    cached = await r.get(f"user:{user_id}")
    if cached:
        logger.debug("cache_hit", key=f"user:{user_id}")
        return json.loads(cached)

    logger.debug("cache_miss", key=f"user:{user_id}")
    user = await user_repo.get_by_id(user_id)
    if user:
        await r.set(f"user:{user_id}", json.dumps(user), ex=300)  # 5 min TTL
    return user
```

### Cache invalidation

```python
async def update_user(user_id: str, data: dict) -> dict:
    user = await user_repo.update(user_id, data)
    await get_redis().delete(f"user:{user_id}")  # Invalidar cache
    logger.info("cache_invalidated", key=f"user:{user_id}")
    return user
```

### Rate limiting

```python
async def check_rate_limit(key: str, limit: int = 60, window: int = 60) -> bool:
    r = get_redis()
    current = await r.incr(f"ratelimit:{key}")
    if current == 1:
        await r.expire(f"ratelimit:{key}", window)
    return current <= limit
```

### Distributed lock

```python
async def acquire_lock(name: str, timeout: int = 10) -> bool:
    r = get_redis()
    return await r.set(f"lock:{name}", "1", nx=True, ex=timeout)

async def release_lock(name: str) -> None:
    await get_redis().delete(f"lock:{name}")
```

## SSH Tunnel (dev)

```bash
ssh -L 6379:localhost:6379 user@vps-ip -N
# Agora REDIS_URL=redis://localhost:6379/0
```

## Dependências

```toml
[project.dependencies]
redis = ">=5.0.0"  # redis-py com suporte async
```

## Troubleshooting

| Problema | Causa | Solução |
|----------|-------|---------|
| `NOAUTH` | Password não enviado | Adicionar password na config |
| `connection refused` | Redis não escuta no IP público | Checar `bind` em redis.conf |
| `OOM command not allowed` | Memória excedida | Aumentar maxmemory ou usar eviction policy |
| `connection timed out` | Firewall | Checar UFW/iptables |
| `WRONGTYPE` | Tipo de dado errado na key | Verificar se a key existe com tipo diferente |
