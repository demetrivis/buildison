# Log Analysis Guide

## Como Encontrar Logs

```bash
# Arquivos de log no projeto
find . -name "*.log" -type f 2>/dev/null

# Logs Docker
docker compose logs --tail=200
docker compose logs api --tail=200 --since=1h

# Filtrar por nível
docker compose logs api 2>&1 | grep '"level": "error"'
docker compose logs api 2>&1 | grep '"level": "warning"'
```

## Parsing de JSON Logs

```bash
# Extrair só errors com jq
cat app.log | jq 'select(.level == "error")'

# Contar eventos por tipo
cat app.log | jq -r '.event' | sort | uniq -c | sort -rn

# Filtrar por request_id
cat app.log | jq 'select(.request_id == "uuid-aqui")'

# Eventos lentos (>1000ms)
cat app.log | jq 'select(.elapsed_ms > 1000)'

# Timeline de um request
cat app.log | jq 'select(.request_id == "uuid") | {timestamp, event, level}'
```

## Padrões de Problema

### Retry Storm
```bash
# Muitas tentativas do mesmo evento em curto período
cat app.log | jq 'select(.event | contains("retry"))' | jq -r '.timestamp' | head -20
```

### Cascading Failure
```bash
# Sequência: timeout -> retry -> circuit_open -> degraded
cat app.log | jq 'select(.level == "error" or .level == "critical")' | jq '{timestamp, event, error}'
```

### Slow Queries
```bash
# Top 10 queries mais lentas
cat app.log | jq 'select(.event == "db_query_slow")' | jq -r '[.elapsed_ms, .query_name] | @tsv' | sort -rn | head -10
```

### Memory/Connection Issues
```bash
# Erros de conexão
cat app.log | jq 'select(.error | contains("connection") or contains("timeout") or contains("pool"))'
```

## Formato do Relatório de Análise

```
SUMMARY
Estado geral do sistema em 1-2 frases.

ERRORS
- [count]x event_name (first: ts, last: ts)
  Message: mensagem
  Probable cause: causa

WARNINGS
- [count]x event_name
  Risk: risco se ignorado

PATTERNS
- Descrição de padrões notáveis

RECOMMENDED ACTIONS
1. Ação concreta #1
2. Ação concreta #2
```

Sem emojis. Sem especulação sem evidência. Factual e direto.
