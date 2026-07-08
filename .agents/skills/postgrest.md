---
name: postgrest
description: "PostgREST conventions: database-first APIs, schema design, RLS, views, RPC functions, permissions, pagination and API exposure directly from PostgreSQL."
---

<!-- Gerado de .claude/skills/postgrest/SKILL.md por scripts/gen-antigravity.mjs — não edite à mão. -->

# PostgREST

Use PostgREST when the database is the API.

## Principles

- Database-first architecture.
- Prefer tables, views and RPC functions over custom CRUD endpoints.
- Use PostgreSQL as the source of truth.
- Expose business-safe operations through views and functions.
- Enforce security with RLS.

## Rules

- CRUD should come from PostgREST whenever possible.
- Avoid building duplicate REST endpoints in application code.
- Use views for read models.
- Use RPC functions for workflows.
- Enable RLS on user data.
- Version API through schemas when necessary.
- Document exposed tables, views and functions.

## Good Fit

- Admin systems
- Internal tools
- SaaS backends
- Analytics APIs
- Rapid CRUD delivery

## References

- @references/rls.md
- @references/views.md
- @references/rpc.md
- @references/schema-design.md
