---
name: nestjs
description: "NestJS conventions: modules, controllers, services, DTOs, validation, guards, interceptors, filters, Prisma integration, testing, and production-grade API architecture."
---

<!-- Gerado de .claude/skills/nestjs/SKILL.md por scripts/gen-antigravity.mjs — não edite à mão. -->

# NestJS Backend

## Stack

- Node.js 20+
- TypeScript
- NestJS
- PostgreSQL
- Prisma
- Jest
- Swagger

## Architecture

- Feature modules by domain.
- Controllers receive requests.
- Services contain business logic.
- Repositories handle persistence.
- DTOs validate input.
- Guards handle authorization.
- Interceptors handle cross-cutting concerns.
- Filters map exceptions.

## Rules

- Never place business logic inside controllers.
- Never instantiate providers with `new`.
- Use NestJS Dependency Injection.
- Request and response DTOs must be separated.
- Validation via class-validator.
- ValidationPipe should be global.
- Domain errors should not know about HTTP.
- Prisma access should happen through services/repositories.
- Prefer feature modules over monolithic modules.

## ValidationPipe

```ts
app.useGlobalPipes(new ValidationPipe({
  whitelist: true,
  forbidNonWhitelisted: true,
  transform: true,
}));
```

## CLI

```bash
nest generate module
nest generate service
nest generate controller
```

## References

- @references/modules.md
- @references/controllers.md
- @references/services.md
- @references/dto-validation.md
- @references/prisma.md
- @references/auth.md
- @references/testing.md
