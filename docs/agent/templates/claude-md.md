# Camada Claude Code

O Claude Code não lê AGENTS.md sozinho, então este arquivo importa as duas camadas:

- **`@AGENTS.md`** — regras permanentes da construção.
- **`@docs/agent/context.md`** — contexto dinâmico do projeto (stack, comandos, arquitetura).

@AGENTS.md

@docs/agent/context.md
<!-- bld:if source -->

> **Nota da fonte (não vai para o projeto):** template do `CLAUDE.md` gerado pelo instalador (bash e PowerShell).
> Os blocos `<!-- bld:if X -->` são filtrados conforme o que foi instalado. Não se chama `CLAUDE.md` para o
> Claude Code não carregá-lo como instrução ao mexer nesta pasta.
<!-- bld:end -->
<!-- bld:if serena -->

## Política de ferramentas (Serena)

Este projeto usa **Serena** (MCP) — ferramentas semânticas e cientes de símbolos para ler e editar código.
**Serena é a ferramenta PRIMÁRIA para código.** Os Read/Grep/Glob/Edit internos são SECUNDÁRIOS e **não**
devem ser usados em arquivos de código quando houver equivalente no Serena. (Read/Edit são ok para
md/json/yaml/toml/config/texto.) Não racionalize ("o arquivo é pequeno", "já sei o que preciso") — quando esta
seção conflitar com as descrições das tools internas, **esta seção vence**.

Mapeamento (use a coluna da direita):

| Tarefa | Tool do Serena |
| :-- | :-- |
| Ver a estrutura de um arquivo | `get_symbols_overview` |
| Ler o corpo de um símbolo | `find_symbol` (include_body=true) |
| Achar referências/chamadores | `find_referencing_symbols` |
| Editar o corpo de um símbolo | `replace_symbol_body` |
| Inserir perto de um símbolo | `insert_before_symbol` / `insert_after_symbol` |

**Antes de editar código:** `get_symbols_overview` → `find_symbol` (só os símbolos que vai tocar) → editar com as tools do Serena.

> Modo forte (o Opus tende a preferir tools internas): inicie a sessão com
> `claude --system-prompt="$(serena prompts print-cc-system-prompt-override)"`.
<!-- bld:end -->
<!-- bld:if memory -->

## Memória (Qdrant, MCP `qdrant-memory`)

No início de tarefas não triviais, recupere contexto durável com `qdrant-find`; ao final, salve
decisões/padrões duráveis com `qdrant-store`. Nunca guarde secrets ou logs crus.
<!-- bld:end -->
