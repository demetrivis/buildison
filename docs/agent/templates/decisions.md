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

## 2026-07-08 — Antigravity (Google) como alvo first-class do installer

**Contexto:** o Antigravity (IDE agêntica da Google, base Gemini) lê `AGENTS.md` nativamente e tem convenção própria de agentes/skills (`.agents/`) e config de MCP **global** em `~/.gemini/.../mcp_config.json` (não por-projeto como `.mcp.json`). Queríamos que o buildison configurasse o Antigravity igual faz com Codex/OpenCode.
**Decisão:** (1) as regras vêm de graça via `AGENTS.md` (já copiado no core); (2) espelhar o roster de agentes e as skills para `.agents/` via `scripts/gen-antigravity.mjs` (fonte de verdade continua em `.claude/`); (3) instalar a toolbox MCP no config global do Antigravity com as chaves `spec-workflow`/`serena`/`qdrant-memory` usando **caminho absoluto do projeto** (config global não tem CWD confiável) e `serena --context ide-assistant`; (4) installer/switch localizam o `mcp_config.json` sondando `~/.gemini/config/` e `~/.gemini/antigravity/` (Windows prioriza `antigravity/`), fazem backup e merge preservando outros servers.
**Motivo:** chaves planas (não namespaced por projeto) mantêm o JSON sempre válido e sem lixo — o config global reflete o "projeto atual" (último instalado/trocado), mesmo mental model do Codex. Namespacing por projeto poluiria e ativaria N toolboxes simultâneas. Descartado embutir o corpo completo das skills no `.agents/` sem gerador (viraria fonte duplicada que apodrece) — o gerador torna o resync 1 comando.
**Impacto:** `install.sh`/`install.ps1` ganham o alvo `antigravity` (opção 4 no menu, 5 = todos); `switch.sh`/`switch.ps1` atualizam o Antigravity só se já configurado. `.agents/` e `scripts/gen-antigravity.mjs` entram no `files` do npm. Ao mudar `.claude/agents` ou `.claude/skills`, rode `node scripts/gen-antigravity.mjs` pra ressincronizar o `.agents/`. Ressalva: a expansão de `${QDRANT_API_KEY}` no modo VPS depende do Antigravity suportar env do shell — pode exigir inline manual.

## 2026-07-08 — Correção: Antigravity não registra "agente custom" via arquivo

**Contexto:** ao usar de fato o Antigravity IDE (não o CLI), o roster `.agents/agents.md` (e depois `.agents/agents/<nome>.md`, e `agent.json`) **não fez os agentes aparecerem** no picker. Investigando a máquina: a IDE guarda agentes **internamente** (protobuf em `~/.gemini/antigravity-ide/implicit/*.pb` + binário `agentapi`), não há `agent.json` em lugar nenhum, e o CLI (`~/.gemini/antigravity-cli/`) não está instalado. Fontes (fórum Google, blogs) confirmam: **não há como registrar/forçar subagente custom** — os subagentes (Browser/Terminal) são orquestrados pela IDE a partir da missão descrita. O que a IDE lê por arquivo é **skill** (`.agents/skills/`, auto-contexto, referência por `#`) e **workflow** (`.agents/workflows/`, slash-command `/`).
**Decisão:** o gerador **deixa de produzir roster de agentes**. `.agents/` passa a ter só `skills/` + `workflows/`. Os agentes **de missão** (`arq-info`, `arq-info-web`, `design-system-extractor`) viram **workflows** (`/comando`, corpo = a persona). Os agentes de **camada** (api, db, logic, …) não têm equivalente no Antigravity — suas convenções já vivem nas skills. `gen-antigravity.mjs` passou a aceitar um dir-alvo (`node scripts/gen-antigravity.mjs /projeto`).
**Motivo:** insistir em roster/agent.json era beco sem saída (bug conhecido do picker + IDE não lê agente de arquivo). Workflow é o único jeito de disparar uma "persona/missão" por comando; skill é o jeito de injetar convenções no contexto.
**Impacto:** `arq-info-web` roda no Antigravity via `/arq-info-web` (ou colando a persona). Ao herdar/atualizar, o `.agents/` não tem mais `agents.md`. Regras seguem no `AGENTS.md`. Lição de processo: validar o mecanismo real do produto-alvo **antes** de gerar/propagar formato (perdeu-se tempo com roster que a IDE nunca leu).
