---
name: prisma
description: "Prisma ORM conventions: schema design, migrations, Prisma Client usage, transactions, repositories, query performance, soft deletes, relations, indexes, and production database safety."
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Prisma ORM

Convenções para projetos usando Prisma com PostgreSQL em backends Node.js/TypeScript, incluindo NestJS, Express, Hono e frameworks similares.

## Stack

- ORM: Prisma
- Database: PostgreSQL
- Runtime: Node.js / TypeScript
- Migrations: Prisma Migrate
- Client: Prisma Client

## Estrutura Recomendada

```txt
prisma/
├── schema.prisma
├── migrations/
└── seed.ts

src/
├── prisma/
│   ├── prisma.module.ts
│   └── prisma.service.ts
└── modules/
    └── <domain>/
        ├── <domain>.service.ts
        └── <domain>.repository.ts
```

Em NestJS, prefira `PrismaModule` + `PrismaService`. Em Express/Hono, use um client compartilhado com lifecycle explícito.

## Regras Core

- Nunca acesse Prisma diretamente em controllers/handlers.
- Encapsule queries em services ou repositories.
- Use migrations versionadas.
- Não altere banco manualmente em produção.
- Toda entidade principal deve ter `id`, `createdAt` e `updatedAt`.
- Use `deletedAt` para soft delete em entidades auditáveis.
- Defina indexes para filtros, ordenação e relações.
- Use constraints únicas quando houver regra de unicidade.
- Evite `include` profundo sem necessidade.
- Use `select` para respostas públicas.
- Nunca retorne password, token, secret ou campos internos.
- Use transações para operações multi-step atômicas.
- Diferencie erro de domínio de erro de persistência.

## Naming

```prisma
model User {
  id        String   @id @default(uuid())
  email     String   @unique
  name      String?
  createdAt DateTime @default(now())
  updatedAt DateTime @updatedAt
  deletedAt DateTime?

  @@map("users")
}
```

## Transactions

Use transação quando:

- Criar múltiplos registros dependentes
- Atualizar saldo, estoque ou estado crítico
- Registrar auditoria junto com alteração principal
- Executar fluxo que não pode ficar parcialmente aplicado

## Query Safety

- Evite N+1 queries.
- Use paginação em listas.
- Defina limite máximo para `take`.
- Evite raw SQL salvo quando necessário.
- Raw SQL precisa ser parametrizado.

## Migrations

- Gere migrations com nome descritivo.
- Revise o SQL gerado antes de produção.
- Nunca edite migrations já aplicadas em ambiente compartilhado.
- Crie nova migration para ajustes posteriores.

## References

- @references/schema.md
- @references/migrations.md
- @references/client.md
- @references/repositories.md
- @references/transactions.md
- @references/query-performance.md
