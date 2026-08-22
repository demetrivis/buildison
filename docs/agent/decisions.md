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

## 2026-08-12 — `--update`: separar boilerplate do que é do projeto

**Contexto:** não havia caminho seguro pra atualizar um repo que já tinha o buildison. O `AGENTS.md` era copiado com `copy_keep` (não sobrescreve se existe), então repo antigo **nunca** recebia regra nova; e `--force`, a alternativa óbvia, atualizava o `AGENTS.md` mas apagava junto `docs/agent/context.md` e `decisions.md`. Catch-22. Pior: o `CLAUDE.md` era regravado **incondicionalmente** (`cat >`), sem backup — encontrado o estrago já feito em dois repos (`confortese`, 485 linhas de doc; `datacrazy_mcpivis`, 325), salvos só porque as mudanças não tinham sido commitadas.
**Decisão:** classificar cada arquivo por natureza. **Boilerplate** (`AGENTS.md`, `.claude/`, `.agents/`, `.spec-workflow/templates/`) é atualizado no `--update`; **do projeto** (`context.md`, `decisions.md`, `CLAUDE.md`, `COLLECTION_NAME` do `.mcp.json`) é preservado. `--force` continua regravando tudo, mas deixa de ser o caminho de atualização. Os placeholders de `context.md`/`decisions.md` saíram pra `docs/agent/templates/` — antes o instalador copiava o arquivo do próprio buildison, o que vazaria o contexto dele pra todo projeto herdado assim que fosse preenchido.
**Motivo:** a distinção "permanente vs dinâmico" já existia no `AGENTS.md` como conceito, mas o instalador não a implementava. Descartado fazer merge do `CLAUDE.md` (injetar `@imports` preservando o resto): é lógica de merge, mais superfície pra errar, e os `@imports` mudam raramente.
**Impacto:** atualizar repo antigo agora é `--update`, nunca `--force`. O `--update` faz `.bak` do que muda e lista órfãos em `.claude/` sem deletar. Ao editar o template de contexto, edite `docs/agent/templates/` — o `docs/agent/context.md` da raiz descreve o buildison em si.

## 2026-08-20 — `vps-infra` passa a existir em dois repos, deliberadamente

**Contexto:** o `infrailson` virou modelo para outros devs fazerem infra. Quem clona ele para aprender
infraestrutura precisa da skill de provisionamento junto — não deveria ter que instalar o buildison
só por causa dela.

**Considerado e recusado:** mover a skill para o infrailson. O argumento era evitar duas cópias que
derivam. Recusado porque tira a skill de todo projeto que instala o buildison, e provisionar servidor
é operação legítima de quem tem uma aplicação para publicar.

**Decisão:** **copiar**, e assumir o custo da sincronização em vez do custo da ausência.

**Mitigação, já que o risco é real:** as duas pastas são idênticas hoje. Antes de commitar mudança na
skill em qualquer um dos repos:

```bash
diff -rq ~/code/devero/buildison/.claude/skills/vps-infra \
         ~/code/devero/infrailson/.claude/skills/vps-infra
```

Silêncio = sincronizadas. E o `.agents/` do buildison é gerado — depois de editar a skill aqui, rode
`node scripts/gen-antigravity.mjs`, senão o espelho do Antigravity fica velho.

## 2026-08-12 — Skill `vps-infra` derivada de produção, não de teoria

**Contexto:** o `/portainer` gerava o stack da aplicação mas listava "Swarm inicializado, `network_public`, Traefik rodando" como pré-requisito — e nada no repo ensinava a chegar lá. O conhecimento existia só numa VPS de produção e num doc gitignored que descreve o resultado, não o caminho.
**Decisão:** criar a skill `vps-infra` extraindo a receita por SSH de uma instalação que funciona (Oracle Ampere, Ubuntu 22.04, Docker, Traefik v3, Swarm de 1 nó), e depois **executá-la contra uma VPS nova** pra validar. Portainer é opcional e a skill pergunta, com o caminho só-terminal documentado.
**Motivo:** receita escrita de memória erra nos detalhes que não aparecem na doc oficial. A execução real corrigiu três coisas que a versão "de teoria" errava: número de linha do iptables hardcoded (o REJECT não está sempre na mesma posição), router `http-catchall` redundante com as flags de redirect do entrypoint (e com namespace `@docker` errado pro provider swarm), e Traefik fixado numa versão atrasada por ter sido copiada da produção.
**Impacto:** VPS nova sobe com `./install.sh` da skill em ~5 fases verificáveis. Os stacks passam a viver em repo versionado (`demetrivis/infra`), não na UI do Portainer — na VPS antiga eles só existiam no banco dele, e reconstruir exigiu `docker service inspect`.
