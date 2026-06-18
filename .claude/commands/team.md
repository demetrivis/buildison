# /team — Montar uma Equipe de Teammates

You have been invoked with the `/team` command. Your job is to evaluate the current task, decide if it benefits from an agent team, and if so, create a team of teammates — independent Claude Code sessions that coordinate through a shared task list and communicate directly with each other.

## Core Principle

This is NOT about subagents. Subagents run inside your session and report back to you. Teammates are fully independent Claude Code instances with their own context windows. They can message each other, claim tasks from a shared list, and work in parallel without going through you for every decision.

Use teammates when the work requires collaboration, debate, or coordination between workers. Use subagents when you just need quick results reported back.

## Mandatory First Step

Before designing a team:

1. Detect the project stack.
2. Read `CLAUDE.md` if it exists.
3. Inspect project manifests:
   - `package.json`
   - `go.mod`
   - `pyproject.toml`
   - `Cargo.toml`
4. Identify framework and architecture.
5. Build teammates that match the actual stack.

Never assume NestJS, Go, Python, React, Prisma or any other technology without evidence.

## Stack-Aware Team Design

### NestJS

Typical teammates:

- nestjs-architect
- controller-owner
- service-owner
- prisma-owner
- test-writer
- security-reviewer

### Go

Typical teammates:

- golang-architect
- handler-owner
- service-owner
- repository-owner
- test-writer
- performance-reviewer

### FastAPI

Typical teammates:

- api-owner
- service-owner
- database-owner
- test-writer
- security-reviewer

### Mixed Projects

If the project contains multiple runtimes:

Example:

- NestJS API
- Go worker
- Redis
- PostgreSQL

Create teammates aligned to boundaries instead of technologies:

- api-owner
- worker-owner
- database-owner
- infra-owner
- test-owner

## When to Create a Team

Create a team when:

- The task has 2+ independent workstreams that benefit from parallel execution
- Workers need to communicate findings to each other
- The task benefits from adversarial review
- The work spans multiple layers
- Investigation requires competing hypotheses explored simultaneously

Do NOT create a team when:

- Work is sequential
- Workers would edit the same files
- Task is small enough for a single session
- Coordination overhead exceeds value

## File Ownership Rule

Every teammate must have explicit ownership.

Bad:

- backend-dev
- backend-dev-2

Good:

- owns `src/modules/users/*`
- owns `src/modules/auth/*`
- owns `internal/payments/*`
- owns `tests/e2e/*`

No overlapping ownership unless the goal is review.

## Instructions

1. Analyze task.
2. Detect stack.
3. Decide whether teammates are justified.
4. Define teammate roles.
5. Define file ownership.
6. Define deliverables.
7. Explain the plan.
8. Create the team.
9. Coordinate progress.
10. Synthesize results.

## Review Teams

For reviews, create specialized reviewers:

- security-reviewer
- performance-reviewer
- architecture-reviewer
- testing-reviewer

Each reviewer should challenge assumptions made by the others.

## Rules

- Always check that `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is enabled
- Detect stack before creating teammates
- Divide ownership to avoid conflicts
- Teammates do not inherit conversation history
- Give complete context in spawn prompts
- Require approval before risky modifications
- Replace stuck teammates when necessary
- Clean up teams after completion
- If teammates are not justified, do not create them

$ARGUMENTS