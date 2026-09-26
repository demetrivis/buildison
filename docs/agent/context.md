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

- **Bash** — `install.sh` (o coração). O `switch.sh`/`switch.ps1` **não existe mais**: trocar o modo
  de memória virou trabalho da skill `qdrant-setup`
- **PowerShell** — `install.ps1` (espelho nativo pro Windows)
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
| **Do projeto** | `docs/agent/context.md`, `docs/agent/decisions.md`, `CLAUDE.md` | preserva |

O `install.sh` emite config pros 4 agentes em **pontos distintos** do arquivo (Claude `.mcp.json`, Codex
`~/.codex/config.toml`, OpenCode `opencode.json`, Antigravity `~/.gemini/.../mcp_config.json`).
**Mexeu em como um agente é configurado, mexa nos quatro** — foi assim que as flags do Serena ficaram
meio-aplicadas por semanas: o commit `fceaae7` corrigiu só o template e deixou o instalador intacto.
O mesmo vale pro `scripts/qdrant-mcp.py` da skill `qdrant-setup`: ele escreve nos mesmos 4 pontos.

**MCP de projeto nunca vai pra config global de agente.** Claude usa `.mcp.json`, Antigravity usa
`.agents/mcp_config.json` (ambos com caminho relativo). O Codex é a exceção forçada (só tem config global):
lá `serena`/`spec-workflow` resolvem pelo CWD, mas a `COLLECTION_NAME` do Qdrant fica presa a um projeto.

**O instalador não configura Qdrant.** Memória vetorial é opt-in pela skill `qdrant-setup` (command
`/qdrant`). O installer só emite `spec-workflow` e `serena`.

**Variante Orca (`--orca`):** camada ortogonal aos presets, salva em `.buildison` (`BUILDISON_ORCA`). Liga a
tag `orca` (bloco "Trabalhando no Orca" no `AGENTS.md`) e mantém um bloco `# >>> buildison >>>` no
`.worktreeinclude` com os arquivos do buildison que estão **fora do git** naquele repo — worktree nova do Orca é
checkout limpo. As skills do Orca (`orca-cli`, `orchestration`) são do Orca: só checamos, nunca copiamos.
Doc do Orca: `https://www.onorca.dev/docs` (sem `llms.txt`; HTML).

**Agentes padrão: o trio Claude Code + Codex + Antigravity.** A escolha fica salva (`BUILDISON_AGENTS` no
`.buildison` e no `global.env`); `.buildison` antigo sem a chave → o instalador deduz do que já está instalado
em vez de impor o trio. `.agents/GERADO.md` de gerador alheio → o Antigravity é pulado naquele projeto.
**README entra em toda mudança** de comportamento do instalador — é pedido fixo do usuário.

**Preset `context`:** `DEF_PARTS=""` — o projeto recebe só o core (`AGENTS.md`, `CLAUDE.md`, `docs/agent/`),
MCP se pedido, e a camada Orca; agents/commands/skills ficam com o `--global`. É o par pensado pro global: o
aviso de duplicação só dispara quando o projeto também instala agents/commands/skills.

**Dois destinos:** projeto (default) ou `--global` (`~/.claude/{agents,commands,skills}` pro Claude,
`~/.agents/skills` pro Codex, `~/.gemini/config/{skills,agents}` + `~/.gemini/antigravity-cli/skills` pro
Antigravity — sem MCP no global dele). O global tem só duas versões — `--preset files` (sem spec-workflow) e
`--preset lite` (com, via `claude mcp add -s user` + `~/.codex/config.toml`). Ele é governado por um
**manifest** (`~/.buildison/global.manifest`): só o que está listado ali é sobrescrito ou retirado; o
resto em `~/.claude` é do usuário. Por isso **caminho de skill em agent/skill nunca é só
`.claude/skills/...`** — diga também onde fica no global, ou use a pasta da própria skill.
`--plugin-skills <nome>` leva pro Codex a skill de um plugin do Claude instalado **na máquina**
(installed_plugins.json ou `~/.claude/plugins/synced/`), reescrevendo `${CLAUDE_PLUGIN_ROOT}`.
**Nunca vendorize plugin de terceiro no repo** — ele é público (GitHub + npm); o conteúdo vem do disco
do usuário na hora do install.

## Convenções específicas

- `--update` atualiza boilerplate. **`--force` NÃO é modo de atualização** — ele apaga `context.md` e `decisions.md`
- `.mcp.json` é versionado: segredo só via `${VAR}` do ambiente do shell, nunca em texto plano
- Doc com IP/host real é **gitignored** (`docs/infra/qdrant-vps-setup.md`); o par versionado é o `-template.md`
- Skills de infra vêm em par: `local-infra` (máquina de dev) e `vps-infra` (servidor remoto)
- Memória vetorial vem em par também: `qdrant-setup` (**setup**: instalar, trocar modo, remover) e
  `agent-memory` (**uso**: o que guardar, como nomear collection). Não misture os dois papéis
- **`vps-infra` existe em DOIS repos** (aqui e no `infrailson`), de propósito. Editou num, sincronize
  no outro — `diff -rq` entre as duas pastas antes de commitar
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
- **Fatiar o instalador por marcadores leva o que está no meio.** O refactor do Qdrant cortou do
  `install.ps1` de um marcador até outro e levou junto o `$Tags = @()`: no Windows as tags viraram a
  string `"mcpinfra"` e todo `-contains` passou a dar falso, sem erro (não há StrictMode). Depois de
  cortar bloco, rode `git diff` e leia **todas** as linhas `-`, não só as que você esperava.
- **O `install.ps1` não tem como ser executado nesta máquina** (sem `pwsh`). Mudança nele é revisada,
  não testada — diga isso explicitamente ao entregar.
- **Doc do produto muda debaixo de você.** Em julho o Antigravity não tinha agente por arquivo e usava
  workflows; em setembro tinha `.agents/agents/`, skills em pasta, e workflows deprecados. Antes de mexer
  no `gen-antigravity.mjs`, leia a doc atual: `https://antigravity.google/llms.txt` (e `<página>.md`). O `agy`
  local só lista agentes com login feito — sem login, `agy agents` sai com 0 e não imprime nada.
- **`chrome-devtools-mcp` sem `--isolated` quebra com duas sessões.** Todas usam o mesmo perfil
  (`~/.cache/chrome-devtools-mcp/chrome-profile`); a segunda sessão (outro Claude, ou o Antigravity) falha
  com "browser is already running". Toda config que o buildison gera leva `--isolated`, e o
  `devtools_unisolated`/`Get-DevtoolsUnisolated` avisa das que ele não gerou.
- **Testar com o repo local não pega o que ficou fora do git.** O `.gitignore` tinha `logs/`, que ignorava
  `.agents/skills/logs/` — o `/logs` do Antigravity nunca foi pro GitHub, e toda instalação via `curl`/`npx`
  (que clonam) saía com 12 commands em vez de 13. Só apareceu na primeira execução real no Windows. Depois de
  gerar arquivos, rode `git status --ignored .claude .agents`; e teste pelo menos uma vez pelo `curl`.
- **O bloco `# >>> buildison >>>` do Codex guarda MCP que não é do buildison** — quem edita o
  `~/.codex/config.toml` à mão põe servidor próprio lá dentro. Regravar só o trio conhecido apagava
  isso em silêncio (aconteceu com o `computer-use`). O `keep` varre o bloco inteiro; ao mexer nele,
  mantenha essa varredura nos **dois** instaladores.

## Onde encontrar o quê

- Regras permanentes: `../../AGENTS.md`
- Convenções por camada: `.claude/skills/`
- Histórico de decisões: [`decisions.md`](decisions.md)
- Template em branco pros projetos herdados: [`templates/`](templates/)
- Stacks das VPS (repo separado): `~/code/devero/infrailson` → `demetrivis/infrailson` (privado)
