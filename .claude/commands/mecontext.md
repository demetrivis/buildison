# Atualizar Memória e Contexto do Projeto

Analise o estado atual do projeto e atualize o contexto e memória com base no que foi feito, aprendido ou decidido nessa sessão.

Este comando serve para deixar o próximo ciclo do Claude Code mais inteligente: ele deve registrar o estado real do projeto, a stack detectada, as convenções descobertas e as decisões que precisam ser lembradas.

## O que fazer:

### 1. Detectar stack e ferramentas do projeto

Antes de editar qualquer memória, leia os manifestos disponíveis e identifique a stack real:

- `package.json` → Node.js/TypeScript; procure por `@nestjs/*`, `next`, `express`, `hono`, `vite`, `prisma`, `typeorm`, `drizzle`
- `go.mod` → Go; procure por `gin`, `fiber`, `chi`, `echo`, `gorm`, `sqlc`, `ent`
- `pyproject.toml`, `requirements.txt`, `uv.lock` → Python; procure por `fastapi`, `django`, `flask`, `sqlalchemy`, `pydantic`
- `Cargo.toml` → Rust; procure por `axum`, `actix-web`, `sqlx`, `diesel`
- `docker-compose.yml`, `compose.yml`, `Dockerfile` → infraestrutura local/produção
- `.env.example` → variáveis obrigatórias e integrações externas

Registre no contexto somente o que foi confirmado nos arquivos. Não invente stack.

### 2. Atualizar CLAUDE.md

Revise e atualize o arquivo `CLAUDE.md` na raiz do projeto com:

- Stack detectada e frameworks confirmados
- Comandos reais para instalar, rodar, testar, lintar e buildar
- Decisões arquiteturais tomadas recentemente
- Padrões de código adotados no projeto
- Convenções e regras importantes descobertas
- Skills relevantes do projeto, por exemplo: `api`, `database`, `infra`, `logging`, `nestjs`, `golang`, `fastapi`

Se o `CLAUDE.md` não existir, crie um com as informações disponíveis.

### 3. Registrar o que foi feito nessa sessão

Crie ou atualize o arquivo `.claude/session-log.md` adicionando uma entrada com:

- Data e hora da sessão
- Objetivo da sessão
- O que foi implementado ou alterado
- Arquivos relevantes modificados
- Stack/frameworks tocados nesta sessão
- Problemas encontrados e como foram resolvidos
- Decisões tomadas e o motivo
- Próximos passos pendentes

Use formato append-only. Não apague histórico antigo sem pedido explícito.

### 4. Atualizar contexto de arquivos relevantes

Se existirem arquivos modificados nessa sessão, avalie se precisam de comentários de cabeçalho explicando:

- Propósito do arquivo
- Dependências importantes
- Convenções específicas

Não adicione comentários óbvios ou ruído. Só documente quando isso ajudar manutenção futura.

### 5. Registrar convenções por stack

Quando detectar uma stack específica, registre regras úteis no `CLAUDE.md` ou em seção própria:

#### NestJS / TypeScript

- Feature modules por domínio
- Controllers sem lógica de negócio
- Services com regras de negócio
- DTOs com `class-validator`
- `ValidationPipe` global quando aplicável
- Prisma/TypeORM/Drizzle somente via service/repository, nunca direto no controller

#### Go

- Handlers sem regra de negócio pesada
- Services/usecases para regras de domínio
- Repositories para persistência
- `context.Context` propagado em operações I/O
- Erros embrulhados com contexto e mapeados na camada HTTP
- Testes table-driven quando adequado

#### Python / FastAPI

- Routers finos
- Services para regra de negócio
- Schemas Pydantic separados para request/response
- Dependency injection explícita
- Exceptions de domínio mapeadas para HTTP na camada API

### 6. Resumo final

Ao terminar, exiba um resumo curto contendo:

- Arquivos de contexto atualizados
- Stack detectada
- Decisões registradas
- Pendências para a próxima sessão
- Qualquer incerteza que permaneça

$ARGUMENTS