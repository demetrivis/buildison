# docs/agent/context.md — contexto vivo do projeto

> **Arquivo dinâmico — o agente mantém isto.** Muda conforme o projeto evolui. É aqui (não no `AGENTS.md`,
> que é permanente) que vive o conhecimento específico deste projeto: o quê é, qual o stack real, como rodar,
> como está organizado. Atualize sempre que o stack ou a arquitetura mudarem.
>
> Mantenha curto e verdadeiro. Decisões formais vão para [`decisions.md`](decisions.md); memória de baixo
> atrito vai para o Qdrant (skill `agent-memory`).

## Visão do projeto

<!-- O que é este projeto, qual problema resolve, domínio. -->
- _A preencher por projeto._

## Stack

<!-- Runtime, framework, banco, libs centrais REAIS deste projeto. -->
- Runtime: _ex: Python 3.12 / Node 20 / Go 1.22_
- Framework: _ex: FastAPI / NestJS / Gin_
- Banco: _ex: PostgreSQL (Supabase) + Redis_
- ORM/acesso a dados: _ex: Prisma / SQLAlchemy / PostgREST_

## Commands

<!-- Comandos REAIS deste projeto (substituem os exemplos genéricos). -->
```bash
# Python:  uv sync · uv run uvicorn src.main:app --reload · uv run pytest · uv run ruff check .
# Node:    pnpm install · pnpm dev · pnpm test · pnpm lint
# Go:      go mod download · go run ./cmd/... · go test ./... · golangci-lint run
```

## Arquitetura

<!-- Módulos principais, fronteiras, como se comunicam. -->
- _A preencher por projeto._

## Convenções específicas

<!-- Padrões deste projeto que não estão nas skills genéricas. -->
- _A preencher por projeto._

## Pontos de atenção / armadilhas

<!-- Quirks, partes frágeis, áreas que quebram fácil. -->
- _A preencher por projeto._

## Onde encontrar o quê

- Regras permanentes (toolbox, infra, memory policy): `../../AGENTS.md`
- Convenções por camada: `.claude/skills/` (api, database, logging, infra, ...)
- Histórico de decisões: `decisions.md`
