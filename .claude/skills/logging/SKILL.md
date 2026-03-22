---
name: logging
description: "Structured logging standards with structlog and JSON output. Use when writing logs, configuring logging, reviewing log patterns, or adding observability to code."
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Structured Logging

Padrões e convenções de logging estruturado do projeto. Toda log entry segue formato JSON com campos obrigatórios. Sem print(), sem emojis, só structlog.

## Stack

- **Biblioteca**: structlog
- **Formato produção**: JSON (uma linha por entry)
- **Formato dev**: Console colorido (ConsoleRenderer)
- **Config**: `src/shared/logging.py`

## Campos Obrigatórios

```json
{
  "event": "nome_em_snake_case",
  "level": "info",
  "logger": "src.modulo.submodulo",
  "timestamp": "ISO 8601",
  "request_id": "UUID v4"
}
```

## Prefixo Console

```
[backend] INFO  [src.api.routers.users] user_created user_id=abc-123
```

## Regras Invioláveis

- NUNCA `print()` — sempre logger estruturado
- NUNCA emojis em logs
- NUNCA logar dados sensíveis (passwords, tokens, PII)
- Event names em snake_case
- Logger name espelha o module path
- `request_id` bindado no middleware, propaga automaticamente

## Níveis

- **DEBUG**: detalhes de dev — valores, fluxo interno
- **INFO**: eventos de negócio com sucesso — `user_created`, `order_placed`
- **WARNING**: recuperável mas merece atenção — rate limit, fallback, deprecation
- **ERROR**: falha que impede a operação — query falhou, serviço externo caiu
- **CRITICAL**: falha sistêmica — banco inacessível, config ausente

## References

Para detalhes de implementação, consulte:
- @references/structlog-config.md — Setup completo do structlog
- @references/patterns.md — Padrões de logging em funções, performance, middleware
- @references/analysis.md — Como analisar e diagnosticar logs do projeto
