---
name: agent-memory
description: "Memória vetorial persistente do agente via Qdrant (MCP qdrant-memory). Use para decidir o que salvar/recuperar como contexto durável do projeto, nomear collections por projeto, modelar payload de metadados e seguir a política do que NUNCA guardar. Acione quando o usuário pedir para 'lembrar', 'salvar decisão', 'recuperar contexto', configurar Qdrant ou trabalhar com memória de agente."
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Agent Memory — Qdrant

Memória vetorial persistente para agentes de código. Um **único Qdrant local** compartilhado entre projetos,
separado por **collections**. Acesso via MCP `qdrant-memory` (ver `.mcp.json` na raiz do projeto).

> Qdrant é **infraestrutura de memória, não fonte de verdade**. Regras fixas ficam no `AGENTS.md`;
> decisões técnicas formais ficam em `docs/agent/decisions.md` (versionado no Git). O Qdrant guarda o
> que é durável mas não merece virar arquivo — aprendizados, padrões, quirks de integração.

## Infra

- 1 Qdrant local em Docker (`~/local-infra/`, skill `local-infra`) — REST `:6333`, gRPC `:6334`
- 1 volume persistente (`local-qdrant-data`) guarda todas as collections
- MCP `qdrant-memory` (`uvx mcp-server-qdrant`) faz a ponte agente ↔ Qdrant
- Embedding default: `sentence-transformers/all-MiniLM-L6-v2` (FastEmbed, roda local, sem API key)

## Estratégia de collections

**Separe por collection, não por container.** Mantém o Qdrant simples e evita memória de um projeto
contaminar outro. Cada projeto aponta seu `qdrant-memory` para uma collection via `COLLECTION_NAME`.

```
1 Qdrant local
├── agent_global          # padrões e aprendizados reutilizáveis entre projetos
├── agent_project_main    # memória do projeto atual (renomeie por projeto)
└── agent_labs            # experimentos descartáveis
```

Para começar: `agent_global`, `agent_<projeto>`, `agent_labs`. Crie novas conforme surgem projetos.

### Quando usar collection única com payload

Só se estiver construindo produto/SaaS multi-tenant, com filtros obrigatórios por `workspace`/`project`/`user`.
Para dev local, **collection por projeto é mais simples** — prefira essa.

## O que guardar (memória durável)

- decisões de arquitetura **e o motivo**
- convenções do projeto que não estão óbvias no código
- bugs recorrentes e suas correções
- detalhes de integração: endpoints, contratos, quirks de terceiros

## O que NUNCA guardar

- secrets, tokens, credenciais, connection strings com senha
- dados de clientes / PII
- logs crus
- palpites temporários ou conversas inteiras sem resumo

## Payload de metadados (recomendado)

Mesmo em collection por projeto, anexe metadados ao texto da memória para filtrar/expirar depois:

```json
{
  "project": "finance-ceo",
  "scope": "project",
  "type": "decision",
  "content": "Usamos Drizzle em vez de Prisma por controle fino sobre SQL.",
  "source": "manual",
  "importance": "high",
  "created_at": "2026-06-20"
}
```

- `type`: `decision` | `convention` | `bug-fix` | `integration` | `pattern`
- `scope`: `global` | `project`
- `importance`: `high` | `medium` | `low`

## Fluxo de uso

1. **Antes** de uma tarefa não trivial: recupere contexto relevante do Qdrant (decisões/padrões anteriores).
2. **Durante**: prefira `docs/agent/decisions.md` para decisões que merecem revisão/versionamento.
3. **Depois**: salve no Qdrant um **resumo** durável (nunca o transcript inteiro), com payload de metadados.

## Trocar a collection do projeto

No `.mcp.json`, ajuste `env.COLLECTION_NAME` do server `qdrant-memory` para `agent_<seu-projeto>`.
A collection é criada automaticamente na primeira escrita.

## Verificar Qdrant

```bash
curl -s http://localhost:6333/collections | python3 -m json.tool   # lista collections
curl -s http://localhost:6333/healthz                              # health
```
