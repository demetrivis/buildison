---
description: "Memória Vetorial (Qdrant)"
---

<!-- Gerado de .claude/commands/qdrant.md por gen-antigravity.mjs — não edite à mão. -->

Configure, troque ou remova a memória vetorial Qdrant deste projeto.

Use a skill **`qdrant-setup`** e siga o procedimento dela na íntegra: descobrir o que já
existe, escolher o modo (local ou VPS), garantir o Qdrant no ar, registrar o MCP
`qdrant-memory` só nos agentes que este projeto usa, criar a collection e **validar com
`qdrant-store` + `qdrant-find` antes de declarar pronto**.

Escreva os configs pelo script da skill (`scripts/qdrant-mcp.py`), nunca à mão.

Atenção aos dois avisos que a skill detalha: o `~/.codex/config.toml` é **global** (uma
collection pra máquina toda) e trocar de modo **não migra** os dados já gravados.

Argumentos livres do usuário (ex.: `local`, `vps`, `remover`, uma URL) entram como a
intenção; na falta deles, pergunte.
