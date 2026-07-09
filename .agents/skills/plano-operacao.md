---
name: plano-operacao
description: "Read-only architecture documentation pipeline. Point it at the current project and it proposes four artifacts: a C4 model in Structurizr DSL, a deployment view, a data model / ERD with MDM analysis, and an ADR. Use when the user asks to document the architecture, map the system, produce C4 / Structurizr / deployment diagrams, model the data / entities / MDM, or generate an architecture decision record. Never writes to the repository."
---

<!-- Gerado de .claude/skills/plano-operacao/SKILL.md por gen-antigravity.mjs — não edite à mão. -->

# Plano de Operação — Documentação de Arquitetura (read-only)

Skill de **análise e documentação de arquitetura** do buildison. Lê o projeto e **propõe**
artefatos. Não escreve no repositório. `allowed-tools` sem `Write`/`Edit` é a trava: se
precisar persistir algo, isso vira uma **proposta** que o humano aplica.

## Antes de começar (convenções buildison)

1. Leia `docs/agent/context.md` — o mapa vivo do projeto (stack, comandos, arquitetura).
   Ele já pode conter metade do que esta skill produziria; parta dele, não do zero.
2. Consulte `docs/agent/decisions.md` — decisões anteriores. O ADR desta skill deve ser
   coerente com elas (ou apontar divergências).
3. Use o MCP **Serena** para localizar símbolos/models/entrypoints em vez de ler o repo
   inteiro às cegas (regra 4 do `AGENTS.md`). Use **Context7** para versões de libs se precisar.

## Regra inegociável: somente leitura
- NUNCA cria, edita, move ou apaga arquivos do projeto.
- Todo artefato é entregue como **proposta** no corpo da resposta.
- Fecha **sempre** com a seção "Suposições & Lacunas".

## Referências (carregadas sob demanda)
- @references/c4-conventions.md — o que cada nível C4 mostra e o que omitir.
- @references/structurizr-dsl.md — esqueleto e sintaxe do Structurizr DSL.
- @references/data-model-mdm.md — extração de entidades e classificação de master data.
- @references/output-templates.md — moldes dos 4 artefatos (o ADR usa o template do buildison).

## O plano de operação (5 fases)

### Fase 0 — Contexto / varredura
Depois de ler `context.md`, inventarie o que ele não cobre: linguagens e manifestos
(`pyproject.toml`, `package.json`, `go.mod`...), entrypoints, infra declarada (`Dockerfile`,
`docker-compose*`, `k8s/`, `*.tf`, `.github/workflows/`), e persistência (migrations, models,
schema). Produza um inventário bruto. Sobreposição esperada com o command `/explore` e com a
skill `infra` — reaproveite o que já existir, não reanalise à toa.

### Fase 1 — Descoberta estrutural (C4 níveis 1–3)
Ver @references/c4-conventions.md. Identifique atores e sistemas externos (Context),
containers implantáveis (Container) e componentes de 1–2 containers-chave (Component).
Use Serena para confirmar quem chama quem. Não invente serviços.

### Fase 2 — Modelagem de informação (dados + MDM)
Ver @references/data-model-mdm.md. Extraia entidades e relacionamentos de migrations/ORM/schema,
classifique master vs. transacional e sinalize candidatos a MDM (golden record). Amarre cada
grupo de entidades ao container (banco) que o hospeda.

### Fase 3 — Geração de artefatos (PROPOSTAS)
Ver @references/output-templates.md. Gere os quatro:
1. **C4 Structurizr DSL** — `model` + views (context, container, component). Se persistido:
   proposta de `docs/architecture/workspace.dsl` (versionável; casa com Structurizr Lite).
2. **Deployment** — view de deployment do C4, derivada dos arquivos de infra da Fase 0,
   citando de qual arquivo cada decisão veio.
3. **Modelo de dados / ERD + MDM** — Mermaid `erDiagram` + tabela de classificação.
4. **ADR** — usando o **template do buildison** (o mesmo de `skills/infra/references/adr-template.md`):
   Status / Contexto / Decisão / Alternativas Consideradas / Consequências / Data, em
   `docs/decisions/ADR-NNN-titulo.md`. Descreve a arquitetura observada.

### Fase 4 — Verificação
Coerência interna: todo container do DSL aparece em alguma view? Todo `containerInstance` do
deployment referencia um container existente? O ADR conflita com `docs/agent/decisions.md`?

### Fase 5 — Suposições & Lacunas
Feche com a seção do molde: lido-com-certeza vs. inferido, o que faltou, e 3–5 próximos
passos. Inclua aqui, se fizer sentido, **propostas de atualização** para `docs/agent/context.md`
e `docs/agent/decisions.md` — como texto sugerido, para o humano aplicar (a skill não escreve).

## Estilo
Português do Brasil, prático e direto. Artefatos versionáveis (DSL, Mermaid) acima de prosa.
Incerteza explícita.

> Referências detalhadas: `.claude/skills/plano-operacao/references/`.
