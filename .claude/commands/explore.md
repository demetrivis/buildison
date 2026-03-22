# /explore — Explore the Project with Subagents

You have been invoked with the `/explore` command. Your job is to analisar o projeto explorando pastas, arquivos, configs, codigo, testes e tudo mais que for relevante. You decide how to divide the work and how many subagents to use.

## Core Principle

You are the orchestrator. You look at the project, decide what needs to be explored, and spawn 1, 2 or 3 subagents to do the exploration in parallel. You can also use the predefined agents from `.claude/agents/` if any of them is a good fit for a specific exploration area — but this is optional, not required. You design the exploration strategy from scratch every time.

## Instructions

1. **Quick recon first**: Before spawning anyone, do a fast `ls` and `find` (depth-limited) to understand the project's top-level structure. This takes seconds and informs your strategy.

2. **Design the exploration plan**: Based on what you see, decide:
   - How many subagents: 1 if focused question or small project, 2 for medium projects, 3 for large or complex projects
   - What each subagent investigates — divide by area, layer, concern, or whatever split makes sense
   - Whether any predefined agent from `.claude/agents/` would be useful for a specific area

3. **Define each subagent's mission**: Each subagent gets:
   - A clear scope: which folders, files, or concerns to investigate
   - Specific questions to answer about its area
   - Tools to use: bash (ls, find, tree), Grep, Glob, Read
   - Strict read-only constraint — no file modifications

4. **Spawn in parallel**: Use the Agent tool to spawn all subagents simultaneously. Each one works independently.

5. **Consolidate**: After all subagents return, synthesize everything into a single clear report. The report should answer:
   - What is this project? Tech stack, purpose, overall architecture
   - How is it organized? Key folders, modules, entry points
   - What patterns are used? Conventions, code style, architectural decisions
   - What stands out? Missing pieces, TODOs, dead code, potential issues, good practices observed

## Flexibility

**Small project, focused question** ("how does auth work?"):
- 1 subagent: grep for auth-related files, read the auth module, trace the flow

**Medium backend project, general exploration**:
- Subagent 1: Project structure, configs, dependencies, environment setup
- Subagent 2: Source code — main modules, business logic, API routes

**Large monorepo, full mapping**:
- Subagent 1: Backend — API, services, database layer
- Subagent 2: Frontend — components, state management, routing
- Subagent 3: Infrastructure — Docker, CI/CD, scripts, configs

**Database-heavy project**:
- Subagent 1 (using db agent): Explore migrations, schemas, queries, RLS
- Subagent 2: Application code that interacts with the database
- Subagent 3: Tests and data fixtures

**Unfamiliar project, need full context**:
- Subagent 1: README, docs, package.json/pyproject.toml, configs — understand intent and stack
- Subagent 2: Source code structure, entry points, main flows
- Subagent 3: Tests, CI, scripts — understand quality and deployment

## Rules

- All subagents are READ-ONLY — no file modifications, no writes, no installs
- Spawn in parallel, never sequentially
- Each subagent must have a non-overlapping area
- If the user asked a specific question, make sure the exploration answers it
- The final report is factual and direct — no filler, no fluff
- If a predefined agent fits a specific area, you can spawn it for that area, but it's never mandatory
