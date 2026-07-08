# buildison — roster de agentes (espelho de .claude/agents)

> Gerado por `scripts/gen-antigravity.mjs` a partir de `.claude/agents/*.md`.
> **Não edite à mão** — rode o gerador pra ressincronizar. Fonte de verdade: `.claude/agents/`.

O Antigravity lê o `AGENTS.md` da raiz nativamente (regras permanentes + toolbox).
Este arquivo espelha os **papéis especialistas** do buildison para o Antigravity adotar a mesma
divisão de trabalho. As convenções por camada estão em `.agents/skills/`.

## api

Use this agent for HTTP-layer work: creating and reviewing endpoints/routes/controllers, request and response schemas/DTOs, middleware wiring (auth, CORS, logging, error handling), status codes, pagination, and API contracts. Invoke when adding or changing endpoints, designing an API contract, or reviewing route handlers for missing auth, inconsistent status codes, or business logic leaking into the HTTP layer. Does not handle DB queries, domain logic, infra, or logging config.

_Instruções completas do papel: `.claude/agents/api.md` (markdown legível)._

## arq-info-web

Engenharia reversa da ARQUITETURA DE INFORMAÇÃO de um app web EXTERNO rodando no navegador (ex.: um CRM de terceiro) — dirige as ferramentas de browser/devtools em modo READ-ONLY sobre o alvo, captura navegação, telas, rótulos e as requisições de rede, e ESCREVE uma pasta de artefatos (sitemap, ERD/MDM, catálogo de API, fluxos, componentes de UI, gaps). Use para mapear um sistema de terceiro e reconstruí-lo com a mesma experiência. É o par do `arq-info` (que documenta o nosso próprio código), mirando um alvo web em vez do repositório.

_Instruções completas do papel: `.claude/agents/arq-info-web.md` (markdown legível)._

## arq-info

Use this agent to document a project's architecture in READ-ONLY mode: it reads the codebase and PROPOSES four artifacts — a C4 model in Structurizr DSL, a deployment view, a data model/ERD with MDM analysis, and an ADR — delivered as versionable text in its response, never written to the repo. Invoke when the user asks to map/document the architecture, produce C4/Structurizr/deployment diagrams, model entities/MDM, or generate an architecture decision record. Runs the plano-operacao skill's 5-phase pipeline.

_Instruções completas do papel: `.claude/agents/arq-info.md` (markdown legível)._

## db

Use this agent for database work on Supabase + PostgreSQL: schema/table design, SQL migrations, RLS policies, repositories, and Supabase client CRUD. Invoke when creating tables, writing migrations, configuring Row Level Security, building repository classes, or tuning indexes and query performance. Does not handle HTTP routing, domain logic, infra, or logging config.

_Instruções completas do papel: `.claude/agents/db.md` (markdown legível)._

## design-system-extractor

Use this agent to reverse-engineer a living design system from a reference website's HTML. It emits ONE self-contained design-system.html (in the same folder as the input) that REUSES the exact class names, CSS, animations, timing, easing and layout of the original — never redesigning or inventing styles — documented as sections: an exact Hero clone, typography spec, colors/surfaces, UI components with states, layout/spacing, motion gallery and icons. Use when you have a reference page and want a faithful, self-documenting pattern library. It is the visual counterpart of arq-info-web (which reverse-engineers information architecture).

_Instruções completas do papel: `.claude/agents/design-system-extractor.md` (markdown legível)._

## golang

Use this agent for Go backend work with Gin, Fiber, Chi, Echo, or net/http: HTTP handlers, services/use cases, repositories, context propagation, error wrapping, concurrency patterns, table-driven tests, and performance reviews. Invoke when building or reviewing Go APIs — checking for business logic in handlers, missing context propagation, DB access from handlers, goroutine leaks, or ignored errors. Follows the golang skill conventions.

_Instruções completas do papel: `.claude/agents/golang.md` (markdown legível)._

## infra

Use this agent for infrastructure and project-structure work: folder layout, Dockerfiles and docker-compose, environment/secrets configuration, CI/CD and GitHub Actions, health checks, graceful shutdown, connection pooling, and architecture decisions (ADRs). Invoke when setting up project structure, containerizing, wiring deployment, or documenting an architectural trade-off. Does not handle DB queries, HTTP routing, domain logic, or logging config.

_Instruções completas do papel: `.claude/agents/infra.md` (markdown legível)._

## logger

Use this agent for structured logging: configuring the project's logging library (structlog, winston, pino, zerolog, slog) for JSON in production and readable output in dev, enforcing consistent fields and snake_case event names, request_id propagation, elapsed_ms performance tracking, and auditing code for print()/console.log() usage or sensitive data in logs. Also for parsing and diagnosing logs. Does not handle HTTP, DB, domain logic, or infra.

_Instruções completas do papel: `.claude/agents/logger.md` (markdown legível)._

## logic

Use this agent for business-logic and domain work: the service layer, plain domain models, business-rule validation beyond schema checks, multi-step process orchestration, domain exceptions, and state machines / status transitions. Invoke when implementing or reviewing services, designing a domain flow, or checking that rules aren't leaking into route handlers and that the domain stays framework-agnostic. Does not handle HTTP concerns, DB schema/queries, infra, or logging config.

_Instruções completas do papel: `.claude/agents/logic.md` (markdown legível)._

## nestjs

Use this agent for NestJS backend work: feature modules, controllers, services, DTOs with class-validator validation, guards/interceptors/filters, Prisma integration, and testing. Invoke when building or reviewing a NestJS API — checking for business logic in controllers, providers instantiated with new instead of DI, missing global ValidationPipe, request DTOs reused as entities, or Prisma access from controllers. Follows the nestjs skill conventions.

_Instruções completas do papel: `.claude/agents/nestjs.md` (markdown legível)._

## postgrest

Use this agent for database-first APIs with PostgREST (or Supabase's embedded PostgREST): exposing tables, read-model views, and RPC functions as the API, RLS policies, roles and grants, pagination/filtering, and API exposure through PostgreSQL schemas. Invoke when the database is the API — designing what to expose, locking down RLS, or reviewing for tables exposed without RLS, overly permissive policies, or SECURITY DEFINER functions with an unlocked search_path. Follows the postgrest and database skills.

_Instruções completas do papel: `.claude/agents/postgrest.md` (markdown legível)._

## prisma

Use this agent for Prisma ORM work: schema/model design, migrations via Prisma Migrate, Prisma Client usage, transactions, repository patterns, relations and indexes, query performance, and production database safety. Invoke when designing models, writing or reviewing migrations, tuning queries (N+1, deep includes, pagination), or checking for sensitive fields being returned or edited historical migrations. Follows the prisma skill conventions.

_Instruções completas do papel: `.claude/agents/prisma.md` (markdown legível)._

## security-auditor

Use this agent when you need to identify and fix security vulnerabilities in your codebase, including database security, Row Level Security (RLS) policies, Next.js applications, server configurations, API endpoints, authentication flows, and authorization logic. This agent should be invoked after implementing new features that handle sensitive data, when setting up database access patterns, when creating or modifying API routes, or when you want a comprehensive security review of existing code.\n\nExamples:\n\n<example>\nContext: User has just implemented a new API endpoint for user data.\nuser: "I just created a new API route at /api/users/[id] to fetch user profiles"\nassistant: "Let me review that endpoint for security vulnerabilities using the security-auditor agent."\n<commentary>\nSince the user created a new API endpoint that handles user data, use the security-auditor agent to check for authentication, authorization, input validation, and data exposure issues.\n</commentary>\n</example>\n\n<example>\nContext: User is setting up Supabase RLS policies for a new table.\nuser: "I added a new 'documents' table to my Supabase database with some RLS policies"\nassistant: "I'll use the security-auditor agent to review your RLS policies and ensure they properly protect your data."\n<commentary>\nSince the user implemented RLS policies, use the security-auditor agent to verify the policies don't have gaps, properly restrict access, and follow security best practices.\n</commentary>\n</example>\n\n<example>\nContext: User wants a general security review before deployment.\nuser: "Can you check my app for security issues before I deploy to production?"\nassistant: "I'll launch the security-auditor agent to perform a comprehensive security audit of your application."\n<commentary>\nSince the user is preparing for production deployment, use the security-auditor agent to conduct a thorough security review across all layers of the application.\n</commentary>\n</example>\n\n<example>\nContext: User implemented authentication logic.\nuser: "I just finished implementing the login and signup flows"\nassistant: "Let me use the security-auditor agent to review your authentication implementation for security vulnerabilities."\n<commentary>\nSince the user implemented authentication flows, use the security-auditor agent to check for common auth vulnerabilities like weak password policies, session management issues, and credential exposure.\n</commentary>\n</example>

_Instruções completas do papel: `.claude/agents/security-auditor.md` (markdown legível)._

## suporte

Use this agent to diagnose and fix buildison toolbox setup problems: MCP servers failing in /mcp (qdrant-memory, serena, spec-workflow), switching between local and VPS memory modes, migrating vector memories between Qdrant instances, and QDRANT_API_KEY not expanding. Invoke when the user reports 'MCP failed', 'qdrant não conecta', 'serena offline', 'spec-workflow não aparece', 'como troco pra VPS', 'perdi a memória ao trocar de modo', or wants to verify the setup is healthy. Diagnostic-first — runs checks before proposing changes.

_Instruções completas do papel: `.claude/agents/suporte.md` (markdown legível)._
