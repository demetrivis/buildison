# docs/agent/decisions.md

> Log de decisões técnicas relevantes (ADR enxuto). Versionado no Git — é a fonte de verdade
> para "por que está assim". Memória durável de baixo atrito vai para o Qdrant (skill `agent-memory`).

Formato por entrada:

```
## YYYY-MM-DD — Título curto da decisão

**Contexto:** o problema/restrição.
**Decisão:** o que foi escolhido.
**Motivo:** por que, e alternativas descartadas.
**Impacto:** o que muda para quem codar.
```

---

## 2026-06-20 — Toolbox de agentes (memória + planejamento)

**Contexto:** boilerplate precisava de contexto durável, planejamento estruturado e navegação semântica para agentes de código.
**Decisão:** adotar SpecWorkflow MCP + Serena MCP + Context7 MCP + Qdrant local (memória vetorial) + AGENTS.md como contrato.
**Motivo:** separa responsabilidades (planejar / navegar / documentar / lembrar / regras fixas) sem container monolítico; segue arquitetura de referência local.
**Impacto:** projetos herdam `.mcp.json`, `AGENTS.md` e as skills `agent-memory`/`spec-workflow`; Qdrant entra no `local-infra`.
