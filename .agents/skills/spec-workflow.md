---
name: spec-workflow
description: "Planejamento estruturado de features via SpecWorkflow MCP: requirements → design técnico → tasks → implementação → validação. Use para features não triviais, quando o usuário pedir para 'planejar', 'criar spec', 'quebrar em tasks', 'fazer requirements/design', ou quando uma mudança for grande o suficiente para justificar trilho de execução em vez de codar direto."
---

<!-- Gerado de .claude/skills/spec-workflow/SKILL.md por gen-antigravity.mjs — não edite à mão. -->

# SpecWorkflow — planejamento estruturado

SpecWorkflow é o **trilho de execução** acima das outras ferramentas. Organiza uma feature em etapas
explícitas em vez de "prompt mágico": **requirements → design técnico → tasks → implementação → validação**.

Acesso via MCP `spec-workflow` (ver `.mcp.json`). Templates em `.spec-workflow/templates/`.
Artefatos gerados ficam em `.spec-workflow/` no projeto.

> SpecWorkflow **não substitui** Qdrant (memória), Context7 (docs) nem Serena (codebase).
> Ele fica acima deles, coordenando. Use os outros MCPs *dentro* de cada etapa.

## Quando usar

- ✅ Features médias/grandes, mudanças com várias etapas, refactors com risco
- ❌ Alterações triviais (typo, ajuste de 1 linha, fix óbvio) — codar direto é mais rápido

## Etapas

1. **Requirements** — o quê e por quê. Use `requirements-template.md`.
2. **Design técnico** — como, decisões de arquitetura. Use `design-template.md` / `tech-template.md`.
   - Aqui é onde Serena (mapear código afetado) e Context7 (docs de libs) ajudam mais.
3. **Tasks** — quebra em passos pequenos e ordenados. Use `tasks-template.md`.
4. **Implementação** — task por task; commits pequenos.
5. **Validação** — testes e revisão; registrar decisões relevantes em `docs/agent/decisions.md`.

## Templates disponíveis

```
.spec-workflow/templates/
├── product-template.md       # visão de produto
├── requirements-template.md  # requisitos da feature
├── design-template.md        # design de UX/fluxo
├── tech-template.md          # design técnico/arquitetura
├── tasks-template.md         # quebra em tasks
└── structure-template.md     # estrutura/organização
```

## Dashboard (opcional)

O dashboard do SpecWorkflow pode rodar em container local para visualizar specs/tasks.
Ver instruções do repositório `@pimzino/spec-workflow-mcp`. O **MCP server** roda via `npx` (stdio)
configurado no `.mcp.json` — não precisa de container.

## Fluxo recomendado (com a toolbox)

1. Ideia → SpecWorkflow gera **requirements**.
2. **Serena** mapeia o código afetado; **Context7** traz docs de libs externas.
3. SpecWorkflow gera **design** e **tasks**.
4. Implementa task por task; recupera padrões anteriores do **Qdrant** quando útil.
5. Ao concluir: registra decisão em `docs/agent/decisions.md` e salva memória durável no Qdrant.
