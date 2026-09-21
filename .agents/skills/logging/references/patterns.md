# Logging Patterns

## Padrão em Funções

```python
import structlog

logger = structlog.get_logger(__name__)

async def process_payment(payment_id: str, amount: float) -> Result:
    logger.debug("payment_processing_started", payment_id=payment_id, amount=amount)

    try:
        result = await execute_payment(payment_id, amount)
        logger.info("payment_processed", payment_id=payment_id, amount=amount, elapsed_ms=result.elapsed_ms)
        return result
    except PaymentGatewayError as e:
        logger.error("payment_gateway_error", payment_id=payment_id, error=str(e), gateway=e.gateway)
        raise
```

Regra: log no entry (DEBUG), no sucesso (INFO), no erro (ERROR).

## Logging de Performance

Operações com I/O devem incluir `elapsed_ms`:

```python
import time

start = time.monotonic()
result = await db.execute(query)
elapsed = (time.monotonic() - start) * 1000

logger.info("db_query_executed", query_name="get_user", elapsed_ms=round(elapsed, 2))

if elapsed > 1000:
    logger.warning("db_query_slow", query_name="get_user", elapsed_ms=round(elapsed, 2))
```

Threshold: >1000ms = WARNING com sufixo `_slow`.

## Context Binding no Middleware

```python
import structlog
from uuid import uuid4

async def logging_middleware(request, call_next):
    request_id = str(uuid4())
    structlog.contextvars.clear_contextvars()
    structlog.contextvars.bind_contextvars(
        request_id=request_id,
        method=request.method,
        path=request.url.path,
    )
    response = await call_next(request)
    return response
```

Depois disso, toda log entry dentro desse request inclui `request_id`, `method` e `path` automaticamente.

## Padrão para Services

```python
class UserService:
    def __init__(self):
        self.logger = structlog.get_logger("src.core.services.user_service")

    async def create_user(self, data: UserCreate) -> User:
        self.logger.info("user_creation_started", email=data.email)

        existing = await self.repo.find_by_email(data.email)
        if existing:
            self.logger.warning("user_creation_conflict", email=data.email)
            raise ConflictError("Email already registered")

        user = await self.repo.create(data)
        self.logger.info("user_created", user_id=user.id, email=data.email)
        return user
```

## Padrão para Background Tasks

```python
async def process_queue():
    logger = structlog.get_logger("src.workers.queue_processor")

    while True:
        job = await queue.dequeue()
        if not job:
            await asyncio.sleep(1)
            continue

        structlog.contextvars.bind_contextvars(job_id=job.id, job_type=job.type)
        logger.info("job_started")

        try:
            await handle_job(job)
            logger.info("job_completed", elapsed_ms=job.elapsed_ms)
        except Exception as e:
            logger.error("job_failed", error=str(e), retry_count=job.retry_count)
        finally:
            structlog.contextvars.clear_contextvars()
```

## Eventos Comuns

| Evento | Nível | Quando |
|--------|-------|--------|
| `request_started` | INFO | Início de request HTTP |
| `request_completed` | INFO | Request finalizado (com status_code e elapsed_ms) |
| `db_query_executed` | INFO | Query executada |
| `db_query_slow` | WARNING | Query >1000ms |
| `cache_hit` / `cache_miss` | DEBUG | Operações de cache |
| `external_api_called` | INFO | Chamada a API externa |
| `external_api_timeout` | ERROR | Timeout em API externa |
| `auth_failed` | WARNING | Tentativa de auth inválida |
| `rate_limit_exceeded` | WARNING | Rate limit atingido |
| `job_started` / `job_completed` | INFO | Background jobs |
| `job_failed` | ERROR | Falha em background job |
