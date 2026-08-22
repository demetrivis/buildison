# docs/agent/context.md — contexto vivo do projeto

> **Arquivo dinâmico — o agente mantém isto.** Este é o contexto **do buildison em si**.
> O template em branco que vai pros projetos herdados é [`templates/context.md`](templates/context.md) —
> não confunda os dois: preencher o template vaza o contexto do buildison pra todo projeto novo.

## Visão do projeto

**buildison** é o boilerplate de toolbox de agentes: distribui `agents`, `commands` e `skills` a partir de uma
**fonte única** para quatro clientes — Claude Code, Codex, OpenCode/Hermes e Antigravity — cada um recebendo só
o "glue" no formato nativo dele.

Distribuído por três caminhos: `curl | bash`, `npx github:demetrivis/buildison` (sempre a `main`) e
`npx buildison` (npm — **pode estar atrás da `main`**).

## Stack

- **Bash** — `install.sh` (583+ linhas, o coração), `switch.sh`
- **PowerShell** — `install.ps1`, `switch.ps1` (espelhos nativos pro Windows)
- **Node** — `bin/buildison.mjs` (wrapper npx), `scripts/gen-antigravity.mjs` (gera `.agents/` de `.claude/`)
- Sem build e sem testes automatizados — validação é rodar o instalador contra um diretório de teste

## Commands

```bash
bash -n install.sh                       # sintaxe — sempre antes de commitar
node scripts/gen-antigravity.mjs         # regenera .agents/ depois de mexer em .claude/
```

Instalação limpa num alvo de teste:

```bash
./install.sh --dir /tmp/alvo --agents claude --yes --no-infra --no-serena
```

Atualização de projeto existente:

```bash
./install.sh --dir /tmp/alvo --agents claude --yes --no-infra --no-serena --update
```

## Arquitetura

Duas naturezas de arquivo, e **essa distinção governa o instalador inteiro**:

| Natureza | Arquivos | No `--update` |
| :-- | :-- | :-- |
| **Boilerplate** | `AGENTS.md`, `.claude/`, `.agents/`, `.spec-workflow/templates/` | sobrescreve |
| **Do projeto** | `docs/agent/context.md`, `docs/agent/decisions.md`, `CLAUDE.md`, `COLLECTION_NAME` do `.mcp.json` | preserva |

O `install.sh` emite config pros 4 agentes em **pontos distintos** do arquivo (Claude `.mcp.json`, Codex
`~/.codex/config.toml`, OpenCode `opencode.json`, Antigravity `~/.gemini/.../mcp_config.json`).
**Mexeu em como um agente é configurado, mexa nos quatro** — foi assim que as flags do Serena ficaram
meio-aplicadas por semanas: o commit `fceaae7` corrigiu só o template e deixou o instalador intacto.

## Convenções específicas

- `--update` atualiza boilerplate. **`--force` NÃO é modo de atualização** — ele apaga `context.md` e `decisions.md`
- `.mcp.json` é versionado: segredo só via `${VAR}` do ambiente do shell, nunca em texto plano
- Doc com IP/host real é **gitignored** (`docs/infra/qdrant-vps-setup.md`); o par versionado é o `-template.md`
- Skill de infra local: `local-infra` (máquina de dev). A `vps-infra` (servidor remoto) **saiu daqui**
  em 2026-08-20 e vive no `infrailson` — ver `decisions.md`
- Commits explicam **por que**, com o modo de falha concreto quando houver

## Pontos de atenção / armadilhas

Todas já morderam de verdade neste repo:

- **`cp -R src/.claude dst/.claude` aninha** quando o destino existe → cria `.claude/.claude/` e o Claude Code
  não acha mais agents/skills. Sempre passar o diretório **pai**.
- **`cp -Rf` mescla, não sincroniza** — agent/skill renomeado no buildison fica órfão no projeto pra sempre.
- **`CLAUDE.md` não é boilerplate puro.** Regravar cego destruiu 485 e 325 linhas de doc em dois repos.
- **`~/.codex/config.toml` é global com nomes de tabela fixos** — um bloco por projeto = TOML inválido = todos
  os MCPs do Codex morrem calados.
- **Serena abre uma aba de dashboard por instância** sem as 3 flags no launch, nos 4 agentes.
- **Python do sistema é 3.9** — sem `tomllib`. Validar TOML com `uvx --python 3.12 python -c "import tomllib..."`.
- **`glob("**")` do Python não desce em diretório oculto** — `.claude/worktrees/*` passa batido em varredura.
- **Traefik não pede cert pra router criado depois que subiu** — exige `service update --force`, e não loga erro.

## Onde encontrar o quê

- Regras permanentes: `../../AGENTS.md`
- Convenções por camada: `.claude/skills/`
- Histórico de decisões: [`decisions.md`](decisions.md)
- Template em branco pros projetos herdados: [`templates/`](templates/)
- Stacks das VPS (repo separado): `~/code/devero/infrailson` → `demetrivis/infrailson` (privado)
