# Health Checks & Resiliência

## Health Check Endpoint

```python
# src/api/routers/health.py
from fastapi import APIRouter
from src.db.pool import get_pool
from src.cache.client import get_redis
import structlog

router = APIRouter(tags=["health"])
logger = structlog.get_logger(__name__)

@router.get("/health")
async def health():
    checks = {}

    # PostgreSQL
    try:
        pool = get_pool()
        async with pool.acquire() as conn:
            await conn.fetchval("SELECT 1")
        checks["postgres"] = "ok"
    except Exception as e:
        checks["postgres"] = f"error: {str(e)}"
        logger.error("health_check_pg_failed", error=str(e))

    # Redis
    try:
        r = get_redis()
        await r.ping()
        checks["redis"] = "ok"
    except Exception as e:
        checks["redis"] = f"error: {str(e)}"
        logger.error("health_check_redis_failed", error=str(e))

    all_ok = all(v == "ok" for v in checks.values())
    status_code = 200 if all_ok else 503

    return {"status": "healthy" if all_ok else "degraded", "checks": checks}
```

## Retry com Backoff Exponencial

```python
import asyncio
import structlog

logger = structlog.get_logger(__name__)

async def retry_with_backoff(
    func,
    max_retries: int = 3,
    base_delay: float = 1.0,
    max_delay: float = 30.0,
    exceptions: tuple = (Exception,),
):
    for attempt in range(max_retries + 1):
        try:
            return await func()
        except exceptions as e:
            if attempt == max_retries:
                logger.error("retry_exhausted", attempts=max_retries, error=str(e))
                raise

            delay = min(base_delay * (2 ** attempt), max_delay)
            logger.warning(
                "retry_attempt",
                attempt=attempt + 1,
                max_retries=max_retries,
                delay_seconds=delay,
                error=str(e),
            )
            await asyncio.sleep(delay)
```

### Uso

```python
# Conectar ao PostgreSQL com retry
pool = await retry_with_backoff(
    create_pool,
    max_retries=5,
    base_delay=2.0,
    exceptions=(ConnectionRefusedError, OSError),
)

# Conectar ao Redis com retry
redis = await retry_with_backoff(
    create_redis,
    max_retries=5,
    base_delay=2.0,
)
```

## Circuit Breaker Simples

```python
import time

class CircuitBreaker:
    def __init__(self, failure_threshold: int = 5, recovery_timeout: int = 30):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.failures = 0
        self.last_failure_time = 0
        self.state = "closed"  # closed, open, half-open
        self.logger = structlog.get_logger("circuit_breaker")

    def can_execute(self) -> bool:
        if self.state == "closed":
            return True
        if self.state == "open":
            if time.monotonic() - self.last_failure_time > self.recovery_timeout:
                self.state = "half-open"
                self.logger.info("circuit_half_open")
                return True
            return False
        return True  # half-open: allow one attempt

    def record_success(self):
        self.failures = 0
        if self.state != "closed":
            self.state = "closed"
            self.logger.info("circuit_closed")

    def record_failure(self):
        self.failures += 1
        self.last_failure_time = time.monotonic()
        if self.failures >= self.failure_threshold:
            self.state = "open"
            self.logger.error("circuit_opened", failures=self.failures)
```

### Uso com Redis

```python
redis_circuit = CircuitBreaker(failure_threshold=3, recovery_timeout=30)

async def get_cached(key: str) -> str | None:
    if not redis_circuit.can_execute():
        return None  # Fallback: skip cache

    try:
        result = await get_redis().get(key)
        redis_circuit.record_success()
        return result
    except Exception as e:
        redis_circuit.record_failure()
        logger.warning("redis_fallback", key=key, error=str(e))
        return None
```

## Startup com Retry de Conexões

```python
@app.on_event("startup")
async def startup():
    # PostgreSQL — essencial, falha se não conectar
    try:
        await retry_with_backoff(create_pool, max_retries=5, base_delay=2.0)
    except Exception:
        logger.critical("pg_connection_failed_on_startup")
        raise SystemExit(1)

    # Redis — não essencial, app funciona sem cache
    try:
        await retry_with_backoff(create_redis, max_retries=3, base_delay=1.0)
    except Exception:
        logger.warning("redis_connection_failed_on_startup", msg="running without cache")
```
