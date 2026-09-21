# structlog Configuration

## Setup Completo

```python
import structlog
import logging

def setup_logging(environment: str = "production") -> None:
    shared_processors = [
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
    ]

    if environment == "development":
        renderer = structlog.dev.ConsoleRenderer()
    else:
        renderer = structlog.processors.JSONRenderer()

    structlog.configure(
        processors=[
            *shared_processors,
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )

    formatter = structlog.stdlib.ProcessorFormatter(
        processors=[
            structlog.stdlib.ProcessorFormatter.remove_processors_meta,
            renderer,
        ],
    )

    handler = logging.StreamHandler()
    handler.setFormatter(formatter)

    root_logger = logging.getLogger()
    root_logger.addHandler(handler)
    root_logger.setLevel(logging.INFO)
```

## Inicialização no main.py

```python
from src.shared.logging import setup_logging
from src.shared.config import settings

setup_logging(environment=settings.environment)
```

## Silenciar Loggers Ruidosos

```python
logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)
logging.getLogger("httpx").setLevel(logging.WARNING)
```

## Custom Processor para Request ID

```python
def add_request_id(logger, method_name, event_dict):
    from contextvars import copy_context
    ctx = copy_context()
    request_id = event_dict.get("request_id", "no-request-id")
    return event_dict
```

## Dependências

```toml
[project.dependencies]
structlog = ">=24.1.0"
```
