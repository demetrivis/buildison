---
name: qdrant-setup
description: "Instala e configura a memória vetorial Qdrant sob demanda: sobe o Qdrant (local via Docker ou aponta pra uma VPS), registra o MCP qdrant-memory no agente em uso (Claude Code, Codex, OpenCode, Antigravity), cria a collection do projeto e valida a ligação. Também troca o modo local↔vps e desinstala. Acione quando o usuário pedir 'configura a memória', 'instala o qdrant', 'quero memória persistente', 'troca a memória pra VPS', 'tira o qdrant', ou rodar /qdrant."
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Qdrant Setup — memória vetorial sob demanda

O buildison **não** instala Qdrant. Quem instala é esta skill, quando o usuário pedir.
Convenções de *uso* da memória (o que guardar, o que nunca guardar) ficam na skill
`agent-memory` — aqui é só **setup, troca de modo e remoção**.

> Esta skill absorveu o antigo `switch.sh`/`switch.ps1` do buildison, removido quando o
> Qdrant saiu do instalador. Não procure por eles.

## Script

Todo o trabalho de escrever config é feito por `scripts/qdrant-mcp.py` — não edite
`.mcp.json`, `opencode.json` ou `config.toml` à mão. Ele faz backup `.bak.<epoch>` de
tudo que toca e só mexe em config que já existe (exceto o `.mcp.json`, que cria se faltar).

O script fica **dentro da pasta desta skill**, que muda conforme a instalação: no projeto
(`.claude/skills/qdrant-setup/`) ou no global (`~/.claude/skills/qdrant-setup/`, e
`~/.agents/skills/qdrant-setup/` no Codex). Se o agente te informou a pasta de onde este
SKILL.md foi carregado, use-a. Senão, localize **uma vez**:

```bash
for d in .claude/skills/qdrant-setup ~/.claude/skills/qdrant-setup ~/.agents/skills/qdrant-setup; do
  [ -f "$d/scripts/qdrant-mcp.py" ] && { cd "$d" && pwd; break; }
done
```

e use o **caminho absoluto** que sair dali em todos os comandos seguintes — variável de
shell não sobrevive de uma chamada pra outra. Abaixo, `<skill>` é essa pasta.

```bash
python3 <skill>/scripts/qdrant-mcp.py --mode local
python3 <skill>/scripts/qdrant-mcp.py --mode vps --url https://qdrant.exemplo.com
python3 <skill>/scripts/qdrant-mcp.py --remove
```

Flags: `--mode local|vps` · `--url` (obrigatória em vps) · `--dir` (default: PWD) ·
`--collection` (default: `agent_<nome-do-diretório>`) · `--agents claude,codex,opencode,antigravity` ·
`--remove`.

## Procedimento

### 1. Descobrir o que já existe

Antes de perguntar qualquer coisa:

```bash
curl -s -m 3 http://localhost:6333/collections && echo "  → Qdrant local no ar"
grep -l qdrant-memory .mcp.json opencode.json 2>/dev/null
grep -c "mcp_servers.qdrant-memory" ~/.codex/config.toml 2>/dev/null
```

Se já houver Qdrant configurado, **diga em que modo está** e pergunte se é pra trocar,
em vez de reinstalar por cima.

### 2. Escolher o modo

Pergunte, apresentando o trade-off real:

- **local** — `http://localhost:6333`, sem auth, sobe no `~/local-infra` (skill `local-infra`).
  Simples; a memória **fica só nesta máquina**.
- **vps** — `https://qdrant.<seu-dominio>` com header `api-key`. A memória **segue o usuário
  entre máquinas**. Precisa da VPS já no ar — skill `vps-infra`, doc `docs/infra/qdrant-vps-template.md`.

Não há replicação entre os dois. Trocar de modo troca a fonte de verdade; **os pontos
gravados no outro lado não vêm junto**. Avise isso antes de trocar.

### 3. Garantir o Qdrant no ar

**Modo local** — se `curl http://localhost:6333/collections` falhar, o serviço não está de pé.
O `~/local-infra` já traz Qdrant no compose:

```bash
cd ~/local-infra && docker compose up -d qdrant
```

Se o `~/local-infra` não existir, use a skill `local-infra` pra montá-lo. Nunca suba um
container Qdrant avulso — vira um segundo Qdrant concorrendo pela porta 6333.

**Modo vps** — confirme que responde e que a key está exportada:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H "api-key: $QDRANT_API_KEY" https://qdrant.<dominio>/collections
```

`200` = ok. `401`/`403` = key errada ou não exportada. Se `$QDRANT_API_KEY` estiver vazia,
oriente a exportar **no shell que abre o agente** (o config guarda só `${QDRANT_API_KEY}`,
nunca a key em texto plano):

```bash
echo 'export QDRANT_API_KEY=<key>' >> ~/.zshrc && source ~/.zshrc
```

### 4. Registrar o MCP

Detecte quais agentes o projeto usa e passe só esses em `--agents`:
`.mcp.json` → claude · `opencode.json` → opencode · `~/.codex/config.toml` → codex ·
`~/.gemini/.../mcp_config.json` → antigravity.

```bash
python3 <skill>/scripts/qdrant-mcp.py --mode local --agents claude
```

> **Codex é GLOBAL.** O `~/.codex/config.toml` tem nomes de tabela fixos: existe **um**
> `[mcp_servers.qdrant-memory]` pra máquina inteira, não um por projeto. Configurar o Codex
> aqui **troca a collection de todos os projetos**. Se o usuário usa Codex em mais de um
> projeto, diga isso e confirme antes de incluir `codex` em `--agents`.

O script grava a tabela do Codex **dentro** do bloco `# >>> buildison >>>` quando ele existe;
o instalador preserva o que encontra lá, então um `install.sh --update` depois não apaga.

### 5. Criar a collection

```bash
curl -s -X PUT http://localhost:6333/collections/agent_<projeto> \
  -H 'Content-Type: application/json' \
  -d '{"vectors":{"size":384,"distance":"Cosine"}}'
```

`size: 384` casa com `all-MiniLM-L6-v2`, o embedding que o script grava. Mudou o modelo,
mude a dimensão — dimensão errada faz o `qdrant-store` falhar só na hora de gravar.
Na VPS, acrescente `-H "api-key: $QDRANT_API_KEY"`.

### 6. Validar

O MCP só sobe quando o agente **reinicia**. Peça pro usuário reabrir o agente (no Claude
Code, rodar `/mcp` e aprovar `qdrant-memory`), e então teste de ponta a ponta:
grave um ponto com `qdrant-store` e recupere com `qdrant-find`. Só declare pronto depois
que o `qdrant-find` devolver o que você gravou.

### 7. Registrar

Anote em `docs/agent/decisions.md` o modo escolhido, a collection e o porquê.
**Nunca** grave a `QDRANT_API_KEY` em arquivo versionado.

## Trocar de modo

Mesmo script, outro `--mode`. Reveja o passo 2 (a memória não migra) e o passo 5
(a collection precisa existir também do outro lado).

## Remover

```bash
python3 <skill>/scripts/qdrant-mcp.py --remove
```

Tira o `qdrant-memory` dos configs. **Não** apaga a collection nem derruba o container —
faça isso à mão se for a intenção, e confirme com o usuário antes (é irreversível):

```bash
curl -X DELETE http://localhost:6333/collections/agent_<projeto>
```

## Armadilhas

- **Dimensão errada na collection** — `all-MiniLM-L6-v2` é 384. Criar com outro tamanho só
  falha na hora de gravar, não na criação.
- **`${QDRANT_API_KEY}` não expande** — o agente precisa ter sido **aberto** por um shell
  onde a variável já existia. Exportar depois, na sessão, não alcança o processo do agente.
- **Codex é global** — ver aviso no passo 4.
- **Dois Qdrants** — um container avulso e o do `~/local-infra` brigam pela 6333. Use só o do local-infra.
- **Trocar de modo não migra dados** — não é sincronização, é troca de fonte de verdade.
