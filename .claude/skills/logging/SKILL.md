---
name: logging
description: "Structured logging standards with JSON output. Use when writing logs, configuring logging, reviewing log patterns, or adding observability to code."
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Structured Logging

Padrões e convenções de logging estruturado do projeto. Toda log entry segue formato JSON com campos obrigatórios.

## Stack

Adapte à biblioteca do projeto:

- **Python**: structlog (JSON em prod, ConsoleRenderer em dev)
- **Node.js**: pino ou winston
- **Go**: slog ou zerolog
- **Config**: arquivo de setup dedicado (ex: `src/shared/logging.py`, `src/lib/logger.ts`)

## Campos Obrigatórios

```json
{
  "event": "nome_em_snake_case",
  "level": "info",
  "logger": "caminho.do.modulo",
  "timestamp": "ISO 8601",
  "request_id": "UUID v4"
}
```

## Regras Invioláveis

- NUNCA `print()` / `console.log()` / equivalente — sempre logger estruturado
- NUNCA emojis em logs
- NUNCA logar dados sensíveis (passwords, tokens, PII)
- Event names em snake_case: `user_created`, `payment_failed`
- Logger name espelha o module/file path
- `request_id` bindado no middleware, propaga por toda a request

## Níveis

- **DEBUG**: detalhes de dev — valores, fluxo interno
- **INFO**: eventos de negócio com sucesso — `user_created`, `order_placed`
- **WARNING**: recuperável mas merece atenção — rate limit, fallback, deprecation
- **ERROR**: falha que impede a operação — query falhou, serviço externo caiu
- **CRITICAL**: falha sistêmica — banco inacessível, config ausente

## References

Para detalhes de implementação, consulte:
- @references/structlog-config.md — Setup completo (exemplo em Python/structlog)
- @references/patterns.md — Padrões de logging em funções, performance, middleware
- @references/analysis.md — Como analisar e diagnosticar logs do projeto
