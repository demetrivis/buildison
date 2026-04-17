# Architecture Decision Records (ADR)

## Template

Localização: `docs/decisions/ADR-NNN-titulo.md`

```markdown
# ADR-NNN: Titulo da Decisão

## Status
Accepted | Superseded by ADR-XXX | Deprecated

## Contexto
O que motivou essa decisão? Qual problema estamos resolvendo?

## Decisão
O que decidimos fazer e por quê.

## Alternativas Consideradas

### Alternativa A
- Prós: ...
- Contras: ...

### Alternativa B
- Prós: ...
- Contras: ...

## Consequências
O que muda a partir dessa decisão. Impactos positivos e negativos.

## Data
YYYY-MM-DD
```

## Exemplo

```markdown
# ADR-001: Usar Supabase como BaaS

## Status
Accepted

## Contexto
Precisamos de backend com auth, storage e realtime sem montar infra complexa.

## Decisão
Supabase com client Python + acesso direto ao PostgreSQL para queries complexas.

## Alternativas Consideradas

### Firebase
- Prós: ecossistema maduro, bom SDK
- Contras: NoSQL (Firestore), vendor lock-in forte, pricing imprevisível

### Custom (PostgreSQL + Auth0)
- Prós: controle total
- Contras: muito mais infra para gerenciar, mais tempo de setup

## Consequências
- Auth delegado ao Supabase Auth
- RLS no PostgreSQL para segurança row-level
- Client Python para CRUD simples, SQL direto para analytics
- Dependência do Supabase como provider

## Data
2024-01-15
```

## Quando Criar um ADR

- Escolha de framework ou biblioteca principal
- Mudança de banco de dados ou estratégia de dados
- Decisão de deployment (cloud provider, containerização)
- Mudança de padrão arquitetural (monolito → microserviços, etc.)
- Escolha de autenticação/autorização
- Qualquer decisão que seria difícil de reverter
