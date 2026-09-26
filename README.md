# buildison

Toolbox de agentes — agents, commands e skills — escrita **uma vez** e instalada no formato nativo de cada
agente: **Claude Code, Codex, OpenCode/Hermes e Antigravity**.

A fonte é única: `AGENTS.md` + `.claude/` + `docs/agent/`. Cada agente recebe só o "glue" dele.

---

## Índice

- [Início rápido](#início-rápido)
- [Como os comandos funcionam](#como-os-comandos-funcionam)
- [Instalar num projeto](#instalar-num-projeto) — presets, agentes, sob medida, browser, Orca, infra
- [Instalar no global](#instalar-no-global) — pra todos os projetos da máquina
- [Atualizar](#atualizar)
- [Memória vetorial (Qdrant)](#memória-vetorial-qdrant)
- [O que cada agente recebe](#o-que-cada-agente-recebe)
- [A infra local](#a-infra-local)
- [Referência](#referência) — agents, commands, skills, MCPs
- [Todas as flags](#todas-as-flags)
- [Banco de dados via MCP](#banco-de-dados-via-mcp-opcional)
- [Estrutura do repo](#estrutura-do-repo)
- [Personalização](#personalização)
- [Quando algo quebra](#quando-algo-quebra)
- [Requisitos](#requisitos)

---

## Início rápido

Entre na pasta do projeto e rode. O instalador pergunta o destino, os agentes e o que instalar.

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash
```

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1 | iex
```

Nada fica no seu computador além do que é instalado no projeto: o instalador clona o buildison numa pasta
temporária e a apaga no fim.

---

## Como os comandos funcionam

Todo exemplo deste README é **o comando base + flags**. Sem flags, o instalador pergunta; com `--yes`
(`-Yes` no Windows), ele não pergunta nada.

| Onde | Comando base |
| :-- | :-- |
| Mac / Linux | `curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh \| bash -s -- <flags>` |
| Windows | `& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) <flags>` |

As flags têm o mesmo nome nos dois, só muda a grafia: `--dir` vira `-Dir`, `--plugin-skills` vira
`-PluginSkills`. A tabela completa está em [Todas as flags](#todas-as-flags).

> No Windows, o `irm ... | iex` só serve para o modo interativo — ele não aceita flags. Com flags, use a forma
> `[scriptblock]::Create`. O `curl | bash` e o `npx` também funcionam no Windows, mas só dentro do Git Bash ou
> do WSL.

Outras formas de rodar o mesmo instalador:

Via npx, direto do GitHub (sempre a `main`):

```bash
npx github:demetrivis/buildison install --dir . --agents claude --yes
```

Via npm (versão publicada — pode estar atrás da `main`):

```bash
npx buildison@latest install --dir . --agents claude --yes
```

Com o repo clonado (Mac / Linux):

```bash
bash buildison/install.sh --dir /caminho/do/projeto --agents claude --yes
```

Com o repo clonado (Windows):

```powershell
.\buildison\install.ps1 -Dir C:\caminho\do\projeto -Agents claude -Yes
```

---

## Instalar num projeto

O padrão instala no **diretório atual**. Para outro, passe `--dir` (`-Dir`).

### Tudo (preset `full`, o padrão)

Agents, commands, skills, MCP `spec-workflow` + `serena` e `.claude/settings.json`.

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --agents claude --yes
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Agents claude -Yes
```

### Só os arquivos (preset `files`)

Agents, commands, skills, `AGENTS.md`, `CLAUDE.md` e `docs/agent/`. Sem MCP e sem nada instalado na máquina.

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --preset files --agents claude,codex --yes
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Preset files -Agents claude,codex -Yes
```

### Arquivos + spec-workflow (preset `lite`)

O `files` mais o MCP `spec-workflow` (planejamento requirements → design → tasks) e os templates em
`.spec-workflow/templates/`. Roda via `npx`, nada a instalar.

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --preset lite --agents claude,codex --yes
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Preset lite -Agents claude,codex -Yes
```

| Preset | O que vem | Precisa na máquina |
| :-- | :-- | :-- |
| `files` | `AGENTS.md`, `CLAUDE.md`, `docs/agent/`, `.claude/{agents,commands,skills}` (e `.agents/` no Antigravity) | nada |
| `lite` | `files` + MCP `spec-workflow` + `.spec-workflow/templates/` | Node (`npx`) |
| `full` _(padrão)_ | `lite` + MCP `serena` + `.claude/settings.json` | `uv` + Serena |
| `custom` | pergunta MCPs, partes e itens (só no modo interativo) | depende |

### Escolher os agentes

`--agents` aceita qualquer combinação de `claude`, `codex`, `opencode` e `antigravity`. Sem a flag e com
`--yes`, instala só para o Claude Code.

Claude Code + Antigravity, as duas IAs no mesmo projeto (Mac / Linux):

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --preset files --agents claude,antigravity --yes
```

Claude Code + Antigravity (Windows):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Preset files -Agents claude,antigravity -Yes
```

Os quatro agentes (Mac / Linux):

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --agents claude,codex,opencode,antigravity --yes
```

Os quatro agentes (Windows):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Agents claude,codex,opencode,antigravity -Yes
```

### Em outra pasta

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --dir ~/code/meu-projeto --preset files --agents claude --yes
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Dir C:\code\meu-projeto -Preset files -Agents claude -Yes
```

### Sob medida

As flags partem do preset e trocam só o que você passar:

| Flag | Valores |
| :-- | :-- |
| `--mcp` | `spec-workflow`, `serena`, `chrome-devtools` ou `none` |
| `--parts` | `agents`, `commands`, `skills`, `settings` |
| `--skills` | só estas skills |
| `--subagents` | só estes agents |
| `--commands` | só estes commands |

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --agents claude,codex --mcp spec-workflow --skills golang,nestjs,database --commands commit,pr --yes
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Agents claude,codex -Mcp spec-workflow -Skills golang,nestjs,database -Commands commit,pr -Yes
```

O que depende de uma peça sai sozinho quando ela não é instalada: a skill `spec-workflow` só vem com o MCP
`spec-workflow`, a skill `local-infra` só com a infra, e o agent `suporte` só com algum MCP. Pedir o item pelo
nome força a instalação. O `AGENTS.md` e os templates de `docs/agent/` também são filtrados: as seções de infra
e Serena só aparecem se a peça foi instalada.

A escolha fica salva em `.buildison`, na raiz do projeto. As próximas execuções e o `--update` reaproveitam
esse arquivo — passe outro `--preset` para mudar.

### Browser pro agente (chrome-devtools)

Adiciona o MCP `chrome-devtools`, **sempre com `--isolated`**: cada sessão abre um Chrome próprio e
temporário. Sem isso, todas as sessões usam o mesmo perfil do Chrome, e com duas abertas ao mesmo tempo (dois
Claudes, ou Claude + Antigravity) a segunda falha com _"The browser is already running"_.

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --preset files --mcp chrome-devtools --agents claude,antigravity --yes
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Preset files -Mcp chrome-devtools -Agents claude,antigravity -Yes
```

Junto com o spec-workflow (Mac / Linux):

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --mcp spec-workflow,chrome-devtools --agents claude,antigravity --yes
```

Junto com o spec-workflow (Windows):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Mcp spec-workflow,chrome-devtools -Agents claude,antigravity -Yes
```

No fim de **toda** instalação, o instalador procura `chrome-devtools-mcp` sem isolamento nos configs que
conhece — Claude (escopo user, local e `.mcp.json`), Antigravity (projeto e global), Codex e OpenCode — e avisa
onde está. `--browserUrl` e `--autoConnect` contam como isolados, porque conectam num Chrome que já existe.
O preço do `--isolated` é abrir deslogado a cada sessão; para site com login, `--autoConnect` usa o seu Chrome.

### Com o contexto do Orca

Para quem usa o [Orca](https://www.onorca.dev/docs), onde **cada tarefa vira uma git worktree** e vários
agentes trabalham em paralelo. Funciona com qualquer preset — é uma camada a mais, como o spec-workflow.

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --preset files --agents claude,codex --orca --yes
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Preset files -Agents claude,codex -Orca -Yes
```

Com spec-workflow (Mac / Linux):

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --preset lite --agents claude,codex --orca --yes
```

Com spec-workflow (Windows):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Preset lite -Agents claude,codex -Orca -Yes
```

Desligar num projeto que já tem (Mac / Linux):

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --update --no-orca --yes
```

Desligar num projeto que já tem (Windows):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Update -NoOrca -Yes
```

O que o `--orca` faz:

- **Regras de worktree no `AGENTS.md`**: uma tarefa = uma worktree = um agente dono; worktree se cria pelo
  Orca, não com `git worktree add`; handoff pela skill `orca-cli` e coordenação pela `orchestration`, sempre
  carregando o guia da versão instalada (`orca skills get ...`) em vez de flags de memória.
- **`.worktreeinclude`**: uma worktree nova é um checkout limpo, então o que está no `.gitignore` não vai
  junto. Se o `.claude/`, o `AGENTS.md` ou outro arquivo do buildison estiver fora do git neste repo, o
  instalador o lista no `.worktreeinclude`, que o Orca copia para cada worktree nova. Se estiver tudo
  versionado, não há o que fazer. O resto do arquivo (o seu `.env`, por exemplo) é preservado.
- **Skills do Orca**: `orca-cli` e `orchestration` são do Orca, que as instala e atualiza. O buildison não as
  copia — só confere se estão instaladas e, se faltarem, mostra o comando (`orca skills install`).

Sem a flag, o instalador pergunta — mas só se o `orca` estiver instalado na máquina. A escolha fica salva em
`.buildison`, e o `--update` a mantém.

### Infra local e Serena

`--infra` monta o `~/local-infra/` (Postgres, Redis, Qdrant e tunnels em Docker, com a senha do Postgres gerada
na hora). `--serena` instala o CLI do Serena via `uv`.

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --agents claude --infra --serena --yes
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Agents claude -Infra -Serena -Yes
```

### Ver tudo o que dá pra escolher

Lista presets, MCPs, agents, skills e commands disponíveis, sem instalar nada.

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --list
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -List
```

---

## Instalar no global

`--global` põe agents, commands e skills **na máquina**: eles passam a valer em todo projeto que você abrir,
sem nada dentro do projeto.

| Agente | Onde vai |
| :-- | :-- |
| Claude Code | `~/.claude/agents`, `~/.claude/commands`, `~/.claude/skills` |
| Codex | `~/.agents/skills` (o Codex não tem agents nem commands em arquivo) |

São duas versões: **sem** spec-workflow (`--preset files`, o padrão) e **com** (`--preset lite`).

### Sem spec-workflow

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --global --agents claude,codex --yes
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Global -Agents claude,codex -Yes
```

### Com spec-workflow

Registra o MCP no escopo user do Claude Code (`claude mcp add -s user`) e no `~/.codex/config.toml`.

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --global --preset lite --agents claude,codex --yes
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Global -Preset lite -Agents claude,codex -Yes
```

### Com o browser (chrome-devtools)

O `chrome-devtools` não depende de projeto, então funciona bem no global — também sempre com `--isolated`.

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --global --mcp chrome-devtools --agents claude,codex --yes
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Global -Mcp chrome-devtools -Agents claude,codex -Yes
```

### Com skills de plugin do Claude no Codex

Plugin do Claude Code (de marketplace, ou sincronizado da sua conta do claude.ai) não roda no Codex — mas a
skill dele roda, se estiver em `~/.agents/skills`. O `--plugin-skills` copia a skill do plugin **instalado na
sua máquina** para lá. O repo do buildison não carrega nada de terceiro.

Exemplo com o plugin `eng-arq`, sem spec-workflow (Mac / Linux):

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --global --plugin-skills eng-arq --agents claude,codex --yes
```

Sem spec-workflow (Windows):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Global -PluginSkills eng-arq -Agents claude,codex -Yes
```

Com spec-workflow (Mac / Linux):

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --global --preset lite --plugin-skills eng-arq --agents claude,codex --yes
```

Com spec-workflow (Windows):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Global -Preset lite -PluginSkills eng-arq -Agents claude,codex -Yes
```

Tirar as skills de plugin (Mac / Linux):

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --global --plugin-skills none --yes
```

Tirar as skills de plugin (Windows):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Global -PluginSkills none -Yes
```

- No Claude nada muda: ele continua usando o próprio plugin, sem skill duplicada.
- `${CLAUDE_PLUGIN_ROOT}` só existe dentro do Claude Code; na cópia ele é trocado pela pasta da skill no
  Codex, senão as referências da skill não abririam.
- Plugin que não está instalado na máquina é pulado com aviso.

### Como o global se comporta

- **Atualizar** é rodar o mesmo comando de novo. A escolha fica em `~/.buildison/global.env` e é relida —
  inclusive os agentes e as skills de plugin, mesmo quando você troca de `--preset`.
- **Trocar de versão** é passar o outro `--preset`. Da versão com para a sem, a skill e o MCP do spec-workflow
  saem do Claude.
- O instalador só mexe no que **ele mesmo** pôs lá (lista em `~/.buildison/global.manifest`). Uma skill ou
  agent **seu** com o mesmo nome de um do buildison é mantido, com aviso (`--force` sobrescreve). Item do
  buildison que saiu da seleção vai para `~/.buildison/removidos-<data>/`, não para o lixo.
- No Codex, a versão sem **não** tira o spec-workflow do `~/.codex/config.toml`: esse arquivo é compartilhado
  com os installs por projeto.
- Ficam de fora do global, por serem de um projeto só: `AGENTS.md`, `CLAUDE.md`, `docs/agent/`, o
  `settings.json` e o Serena. OpenCode e Antigravity ainda não têm instalação global.

> **Global ou por projeto, não os dois.** Com os dois, os mesmos agents e skills aparecem duplicados. O
> install por projeto avisa quando detecta o global.

---

## Atualizar

### Um projeto que já tem buildison

Entre na pasta do projeto.

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --update --yes
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Update -Yes
```

O `--update` separa o que é **boilerplate** (vem do buildison) do que é **seu** (conhecimento do projeto):

| Atualiza | Preserva |
| :-- | :-- |
| `AGENTS.md` | `CLAUDE.md` (se já existe) |
| `.claude/` e `.agents/` | `docs/agent/context.md` |
| `.spec-workflow/templates/` | `docs/agent/decisions.md` |
| `.mcp.json` e `.agents/mcp_config.json` | servidores MCP que o instalador não gerencia (ex.: o `qdrant-memory` do `/qdrant`) |

Faz `.bak` do que muda e lista arquivos em `.claude/` que não existem mais na fonte — sem apagar, porque o seu
`.claude/` pode ter agents e skills próprios. Respeita o preset salvo em `.buildison`. No Antigravity, remove o
formato antigo que ele mesmo gerou (workflows e skills em arquivo solto); o que você escreveu à mão fica.

> **Não use `--force` para atualizar.** O `--force` **apaga** o `docs/agent/context.md` e o
> `docs/agent/decisions.md` — ele existe para regravar tudo do zero. Para atualizar é sempre `--update`.

### O global

É rodar de novo o mesmo comando do [global](#instalar-no-global): ele relê a escolha salva.

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/demetrivis/buildison/main/install.sh | bash -s -- --global --yes
```

Windows:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/demetrivis/buildison/main/install.ps1))) -Global -Yes
```

---

## Memória vetorial (Qdrant)

**O instalador não configura Qdrant.** Memória vetorial é opcional: instale o buildison normalmente e, quando
quiser memória persistente no projeto, peça ao agente:

```text
/qdrant
```

A skill `qdrant-setup` faz o resto: pergunta o modo, garante o Qdrant no ar, registra o MCP `qdrant-memory`
**só nos agentes que o projeto usa**, cria a collection `agent_<projeto>` e valida com
`qdrant-store`/`qdrant-find`. Ela também **troca de modo** e **remove**.

| Modo | Endpoint | Quando |
| :-- | :-- | :-- |
| **local** | `http://localhost:6333` (do `~/local-infra`) | simples; a memória fica só nesta máquina |
| **VPS** | `https://qdrant.<seu-dominio>` com `api-key` | a memória segue você entre máquinas |

No modo VPS o config guarda só `"QDRANT_API_KEY": "${QDRANT_API_KEY}"` — a key é lida do **ambiente do
shell** e nunca entra em arquivo versionado. Exporte antes de abrir o agente.

Mac / Linux:

```bash
echo 'export QDRANT_API_KEY="sua-key-aqui"' >> ~/.zshrc && source ~/.zshrc
```

Windows:

```powershell
[Environment]::SetEnvironmentVariable('QDRANT_API_KEY', 'sua-key-aqui', 'User')
```

- **Sem replicação entre local e VPS.** São instâncias independentes: trocar de modo **não migra** o que já foi
  gravado. Escolha uma como fonte de verdade.
- **Uma collection por projeto** (`agent_<projeto>`), numa instância só. A API key do Qdrant dá acesso a
  **todas** as collections — para isolamento real entre projetos, use instâncias separadas.
- **O `~/.codex/config.toml` é global**: existe um `qdrant-memory` para a máquina inteira, não um por projeto.
  A skill avisa antes de mexer nele.
- Setup da VPS (Traefik + HTTPS + API key): [`docs/infra/qdrant-vps-template.md`](docs/infra/qdrant-vps-template.md).

---

## O que cada agente recebe

| Agente | Recebe |
| :-- | :-- |
| **Claude Code** | `.claude/` + `CLAUDE.md` (`@imports`) + `.mcp.json` |
| **Codex** | `AGENTS.md` (nativo) + bloco MCP em `~/.codex/config.toml` |
| **OpenCode/Hermes** | `AGENTS.md` (nativo) + `opencode.json` |
| **Antigravity** | `AGENTS.md` (nativo) + `.agents/skills/` + `.agents/agents/` + `.agents/mcp_config.json` |
| _(todos)_ | `AGENTS.md` + `docs/agent/context.md` + `docs/agent/decisions.md` |

**MCP de projeto nunca vai para config global de agente.** Claude usa `.mcp.json` e Antigravity usa
`.agents/mcp_config.json`, os dois com caminhos relativos ao projeto. O Codex é a exceção, porque só tem config
global.

<details>
<summary>Particularidades do Antigravity</summary>

O Antigravity (2.0, CLI `agy` e IDE) lê o `AGENTS.md` da raiz nativamente. O resto vai no `.agents/`, no
formato da documentação oficial ([llms.txt](https://antigravity.google/llms.txt) — toda página tem versão `.md`):

- **Skills** em `.agents/skills/<nome>/SKILL.md` — a pasta inteira, no padrão Agent Skills, com `references/` e
  `scripts/`. Os **commands** do buildison também entram como skill: no Antigravity toda skill vira
  `/<nome>` sozinha (`/commit`, `/pr`, `/tlg`...).
- **Agents** em `.agents/agents/<nome>.md` — viram subagentes, e dá para escolher um como agente principal no
  `/agents`. O frontmatter leva só `name` e `description`: os nomes de ferramenta do Claude (`Read`, `Bash`...)
  não existem lá, e a doc avisa que nome de ferramenta inválido trava o subagente.
- **MCP** em `.agents/mcp_config.json`, do projeto. O global `~/.gemini/config/mcp_config.json` vale para
  **todo** projeto aberto no Antigravity; se ele ainda tiver servidor preso a um projeto, o instalador avisa.
- **Workflows não são mais gerados** — o Antigravity os descontinua em 1º de novembro de 2026.

Para regenerar o `.agents/` a partir do `.claude/`:

```bash
node scripts/gen-antigravity.mjs
```

</details>

<details>
<summary>Particularidades do Codex</summary>

O `~/.codex/config.toml` é **global** e os nomes de tabela são fixos (`[mcp_servers.serena]` etc). Uma tabela
declarada duas vezes deixa o TOML inválido, e aí o Codex descarta a config **inteira**. Por isso os instaladores:

- mantêm **um bloco único** `# >>> buildison >>>`;
- **não repetem** uma tabela que você já declarou fora do bloco;
- **não tiram** do bloco o que já estava lá — inclusive servidor seu que você pôs dentro dele;
- **validam** o arquivo final e, se ele ficaria inválido, não gravam nada.

O preset `files` não toca no `config.toml`. `serena` e `spec-workflow` funcionam em qualquer projeto porque
resolvem pela pasta atual.

</details>

---

## A infra local

Um stack de desenvolvimento **global** em `~/local-infra/`: sobe uma vez e atende todos os projetos da máquina.
Hostname: `localhost` no host, `host.docker.internal` de dentro de container.

| Serviço | Porta | Para quê |
| :-- | :-- | :-- |
| **Postgres** | `5432` | Um database por projeto |
| **Redis** | `6379` | Um número de DB por projeto (`/0`, `/1`...) |
| **Qdrant** | `6333` / `6334` | Memória vetorial dos agentes (via `/qdrant`) |
| **ngrok** | `4040` | URL pública efêmera (teste rápido) |
| **cloudflared** | — | Tunnel nomeado, URL estável no seu domínio |

Para montar, instale com `--infra` (veja [Infra local e Serena](#infra-local-e-serena)) ou peça ao agente a
skill `local-infra`. A senha do Postgres vai para o `~/local-infra/.env` e aparece no fim da instalação.

Subir (Mac / Linux):

```bash
cd ~/local-infra && docker compose up -d
```

Subir (Windows):

```powershell
cd $HOME\local-infra; docker compose up -d
```

Derrubar (Mac / Linux):

```bash
cd ~/local-infra && docker compose down
```

Derrubar (Windows):

```powershell
cd $HOME\local-infra; docker compose down
```

O `down` mantém os volumes: os dados sobrevivem.

---

## Referência

### Agents

| Agent | Descrição |
| :-- | :-- |
| `db` | Supabase + PostgreSQL + Redis: schema, migrations, RLS, repositories |
| `api` | Camada HTTP: routes, schemas/DTOs, middlewares, error handling |
| `logic` | Lógica de negócio: services, validações, orquestração de processos |
| `infra` | Infraestrutura: Docker, env vars, CI/CD, decisões de arquitetura |
| `logger` | Logging estruturado: JSON, request tracing, análise de logs |
| `security-auditor` | Auditoria de segurança para APIs, database, auth |
| `golang` | Go backend: handlers, services, repositories, concorrência, testes |
| `prisma` | Prisma ORM: schema, migrations, queries, transactions, performance |
| `nestjs` | NestJS: módulos, controllers, services, DTOs, guards, Prisma |
| `postgrest` | PostgREST: APIs database-first, views, RPC, RLS, permissões |
| `arq-info` | Documenta a arquitetura do **nosso** código: C4/Structurizr, ERD, ADR (read-only) |
| `arq-info-web` | Engenharia reversa da arquitetura de informação de um app web **externo** |
| `design-system-extractor` | Extrai um design system fiel de um site de referência |
| `suporte` | Diagnostica o setup: MCP falhando, memória, browser travado |

### Commands

| Command | Descrição |
| :-- | :-- |
| `/commit` | Stage inteligente + commit com mensagem bem escrita |
| `/push` | Push seguro, cria upstream se necessário |
| `/pr` | Cria PR analisando todos os commits da branch |
| `/git` | Operações git assistidas com safety checks |
| `/tlg` | Git log visual com graph de branches |
| `/team` | Monta equipe de teammates independentes |
| `/explore` | Explora e mapeia o codebase |
| `/logs` | Analisa logs do projeto |
| `/docker` | Cria Dockerfiles multi-stage e compose (Python, Node, Go) |
| `/ghaction` | Cria workflows de GitHub Actions (detecta o stack) |
| `/portainer` | Gera stack para Portainer (Docker Swarm + Traefik + redes overlay) |
| `/mecontext` | Atualiza `docs/agent/context.md` e a memória do projeto |
| `/qdrant` | Instala, troca ou remove a memória vetorial Qdrant (skill `qdrant-setup`) |

### Skills

| Skill | Descrição |
| :-- | :-- |
| `database` | Supabase, PostgreSQL, Redis, migrations, RLS, conexões com VPS |
| `api` | Camada HTTP: routes, schemas, error handling (agnóstico de framework) |
| `infra` | Docker, env vars, estrutura de projeto, ADRs |
| `logging` | Logging estruturado em JSON, padrões de observabilidade |
| `golang` | Go backend: handlers, services, repositories, context, testes |
| `nestjs` | NestJS: módulos, controllers, services, DTOs, validação, Prisma |
| `prisma` | Prisma ORM: schema, migrations, client, transactions, performance |
| `postgrest` | PostgREST: APIs database-first, views, RPC, RLS, permissões |
| `cloudflare` | Cloudflare API, DNS, email routing, R2 storage |
| `seo-technical` | SEO técnico: sitemaps, meta tags, structured data |
| `favicon` | Favicon e metadata para Next.js |
| `local-infra` | Stack global Docker na máquina de dev: Postgres + Redis + Qdrant + tunnels |
| `vps-infra` | VPS do zero: Ubuntu, Docker, Swarm, Traefik com HTTPS, Portainer opcional. Também vive no [infrailson](https://github.com/demetrivis/infrailson) — editou aqui, sincronize lá |
| `qdrant-setup` | **Setup** da memória vetorial: sobe ou aponta o Qdrant, registra o MCP, cria a collection, troca de modo, remove |
| `agent-memory` | **Uso** da memória vetorial: collections, payload, o que guardar e o que nunca guardar |
| `spec-workflow` | Planejamento estruturado: requirements → design → tasks |
| `plano-operacao` | Pipeline read-only de documentação de arquitetura (C4, ERD, ADR) |

### MCPs

| MCP | Papel | Como entra |
| :-- | :-- | :-- |
| **spec-workflow** | Planejamento: requirements → design → tasks | presets `lite` e `full`, ou `--mcp spec-workflow` |
| **serena** | Navegação semântica do codebase | preset `full`, ou `--mcp serena` |
| **chrome-devtools** | Browser pro agente, sempre com `--isolated` | `--mcp chrome-devtools` |
| **qdrant-memory** | Memória vetorial persistente | `/qdrant`, nunca pelo instalador |
| **Context7** | Docs atualizadas de libs e APIs | configurado no seu agente |

O Serena precisa do CLI instalado uma vez por máquina (ou use `--serena` na instalação):

```bash
uv tool install -p 3.13 serena-agent && serena init
```

---

## Todas as flags

| Mac / Linux | Windows | O que faz |
| :-- | :-- | :-- |
| `--dir <pasta>` | `-Dir <pasta>` | Onde instalar (padrão: pasta atual) |
| `--agents <lista>` | `-Agents <lista>` | `claude`, `codex`, `opencode`, `antigravity` |
| `--preset <nome>` | `-Preset <nome>` | `files`, `lite`, `full` (padrão) ou `custom` |
| `--mcp <lista>` | `-Mcp <lista>` | `spec-workflow`, `serena`, `chrome-devtools` ou `none` |
| `--parts <lista>` | `-Parts <lista>` | `agents`, `commands`, `skills`, `settings` |
| `--skills <lista>` | `-Skills <lista>` | Só estas skills |
| `--subagents <lista>` | `-Subagents <lista>` | Só estes agents |
| `--commands <lista>` | `-Commands <lista>` | Só estes commands |
| `--global` | `-Global` | Instala em `~/.claude` e `~/.agents/skills`, para todos os projetos |
| `--plugin-skills <lista>` | `-PluginSkills <lista>` | Com `--global`: leva skills de plugins do Claude para o Codex (`none` tira) |
| `--orca` / `--no-orca` | `-Orca` / `-NoOrca` | Liga (ou desliga) o contexto do Orca: regras de worktree e `.worktreeinclude` |
| `--update` | `-Update` | Atualiza o boilerplate e preserva o que é do projeto |
| `--infra` / `--no-infra` | `-Infra` / `-NoInfra` | Monta (ou não) o `~/local-infra/` |
| `--serena` / `--no-serena` | `-Serena` / `-NoSerena` | Instala (ou não) o CLI do Serena |
| `--list` | `-List` | Mostra tudo o que dá para escolher e sai |
| `--yes` | `-Yes` | Não pergunta nada |
| `--force` | `-Force` | Regrava tudo do zero — **apaga** `context.md` e `decisions.md` |
| `--help` | `-Help` | Ajuda |

---

## Banco de dados via MCP (opcional)

O agente pode consultar Postgres e Redis direto. **Não vem por padrão** — nem todo projeto usa banco.

### Opção 1 — no config do agente

Em `.mcp.json` (Claude Code):

```jsonc
"redis":    { "command": "uvx", "args": ["redis-mcp-server@latest", "--url", "redis://localhost:6379/0"] },
"postgres": { "command": "uvx", "args": ["postgres-mcp", "--access-mode=restricted"],
              "env": { "DATABASE_URI": "postgresql://dev:<SENHA>@localhost:5432/<DATABASE>" } }
```

Em `~/.codex/config.toml` (Codex):

```toml
[mcp_servers.redis]
command = "uvx"
args = ["redis-mcp-server@latest", "--url", "redis://localhost:6379/0"]

[mcp_servers.postgres]
command = "uvx"
args = ["postgres-mcp", "--access-mode=restricted"]
env = { DATABASE_URI = "postgresql://dev:<SENHA>@localhost:5432/<DATABASE>" }
```

Em `opencode.json` (OpenCode/Hermes): a mesma ideia, dentro de `"mcp"`, com `"type": "local"` e
`"command": [...]`. No Antigravity: dentro de `mcpServers` no `.agents/mcp_config.json`.

`--access-mode=restricted` permite só leitura e operações seguras; troque por `unrestricted` só se precisar
escrever. **A senha fica no arquivo**: em repo público, use placeholder ou vá de Docker MCP Toolkit (abaixo),
que guarda o secret no Keychain.

### Opção 2 — Docker MCP Toolkit

Sem senha em arquivo. Primeiro, o secret:

```bash
printf '%s' "<SENHA>" | docker mcp secret set POSTGRES_PASSWORD
```

Depois habilite os servers Postgres e Redis no Docker Desktop (MCP Toolkit) e conecte:

```bash
docker mcp client connect claude-code
```

---

## Estrutura do repo

```
AGENTS.md              # PERMANENTE: regras + infra + toolbox (fonte única, todos os agentes)
CLAUDE.md              # ponte Claude Code → @AGENTS.md + @docs/agent/context.md
.mcp.json              # toolbox MCP deste repo
.spec-workflow/        # templates de requirements/design/tasks

.claude/               # PERMANENTE: a máquina do boilerplate
├── settings.json
├── agents/            # db, api, logic, infra, logger, security-auditor, golang,
│                      # prisma, nestjs, postgrest, arq-info, arq-info-web,
│                      # design-system-extractor, suporte
├── commands/          # commit, push, pr, git, tlg, team, explore, logs,
│                      # docker, ghaction, portainer, mecontext, qdrant
└── skills/            # database, api, infra, logging, golang, nestjs, prisma,
                       # postgrest, cloudflare, seo-technical, favicon,
                       # local-infra, vps-infra, qdrant-setup, agent-memory,
                       # spec-workflow, plano-operacao

.agents/               # glue do Antigravity (gerado de .claude/)
├── skills/            # uma pasta por skill + uma por command (vira /<nome>)
└── agents/            # subagentes

docs/
├── agent/             # DINÂMICO: context.md (mapa do projeto) + decisions.md (log)
├── infra/             # setup da VPS de memória
└── claude-overview/   # documentação do template

scripts/
└── gen-antigravity.mjs

install.sh             # instalador Mac / Linux (e Git Bash / WSL)
install.ps1            # instalador Windows (PowerShell)
bin/buildison.mjs      # wrapper do npx
```

- **`AGENTS.md`** e **`.claude/`** são **permanentes**: vêm do boilerplate e o `--update` sobrescreve.
- **`docs/agent/context.md`** e **`decisions.md`** são **dinâmicos**: o agente os mantém, e o `--update` nunca
  encosta. Ao herdar o template, o que é específico do seu projeto vai no `context.md`, não no `AGENTS.md`.

---

## Personalização

As skills são templates — depois de instalar, adapte ao stack real do projeto:

- `skills/infra/SKILL.md` — runtime, framework e database reais
- `skills/api/SKILL.md` — os caminhos de pasta do seu projeto
- `skills/logging/SKILL.md` — a biblioteca de logging usada

- **Nova skill:** `.claude/skills/<nome>/SKILL.md` com as convenções, e `references/` se precisar de detalhe.
- **Novo agent:** `.claude/agents/<nome>.md` com responsabilidades e o que ele consulta.
- **Novo command:** `.claude/commands/<nome>.md` com as instruções.

Depois de mexer no `.claude/`, regenere o `.agents/` do Antigravity:

```bash
node scripts/gen-antigravity.mjs
```

---

## Quando algo quebra

O agent `suporte` é especialista no setup: diagnostica `/mcp · failed`, memória que não conecta,
`QDRANT_API_KEY` que não expande e o browser que não abre na segunda sessão. Peça em linguagem natural:

```text
a memória não está conectando, vê com o suporte o que está errado
```

Checagens rápidas.

A key do Qdrant está no ambiente? (Mac / Linux)

```bash
echo $QDRANT_API_KEY
```

A key do Qdrant está no ambiente? (Windows)

```powershell
$env:QDRANT_API_KEY
```

O Qdrant da VPS responde?

```bash
curl -s -H "api-key: $QDRANT_API_KEY" https://qdrant.seu-dominio.com/collections
```

O Qdrant local está de pé?

```bash
docker ps --filter name=qdrant
```

O `chrome-devtools-mcp` está sem `--isolated` em algum lugar? (Mac / Linux)

```bash
grep -n "chrome-devtools-mcp" ~/.claude.json .mcp.json .agents/mcp_config.json ~/.codex/config.toml 2>/dev/null
```

Reinicie o agente depois de mexer em qualquer config MCP: todos leem no boot.

---

## Requisitos

- Um agente: [Claude Code](https://claude.ai/code), Codex, OpenCode ou Antigravity
- `git` — o instalador clona o buildison numa pasta temporária
- Mac / Linux: `bash` e `curl`. Windows: PowerShell 5 ou mais novo
- `python3` é opcional no Mac / Linux: faz o merge do `.mcp.json` sem perder servidores seus, as checagens de
  config e o `--plugin-skills`. Com 3.11+, também valida o `config.toml` do Codex a fundo
- Só se for usar: `uv` para o Serena; Docker Desktop para o `local-infra`; Node (`npx`) para o spec-workflow e
  o chrome-devtools

O `install.ps1` é um espelho do `install.sh`. O caminho do bash é o mais testado — se algo falhar no
Windows, abra uma issue com a saída do terminal.

## Licença

MIT
