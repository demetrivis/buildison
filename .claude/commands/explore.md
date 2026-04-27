# /explore — Explore the Project

You have been invoked with the `/explore` command. Map the project — structure, stack, patterns, and anything notable.

## Default approach: explore directly

Use your own tools (Bash, Glob, Grep, Read) unless the project is large enough to need parallelism. Spawning subagents for a small or medium project is expensive and rarely faster.

## Steps

1. **Recon** — run these in parallel:
```bash
find . -maxdepth 3 -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/__pycache__/*' | sort
```
```bash
cat README.md 2>/dev/null || true
```
Check for the manifest file (pick whichever exists): `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle`.

2. **Read key files**: entry points, config files, main modules. Follow imports/routes to understand the structure.

3. **Grep for patterns** when you need to find things fast:
```bash
grep -r "TODO\|FIXME\|HACK\|XXX" --include="*.ts" --include="*.py" --include="*.go" -l .
```

4. **Report** — concise, factual:
   - What is this? (purpose, tech stack, runtime)
   - How is it organized? (key folders, entry points)
   - What patterns stand out? (conventions, architectural decisions)
   - What's notable? (TODOs, dead code, missing pieces, risks)

## When to spawn subagents

Only spawn subagents when the project has clearly separate, large areas that benefit from parallel exploration — e.g., a monorepo with a full frontend + backend + infra each with hundreds of files.

For focused questions ("how does auth work?"), never spawn subagents — just grep and read directly.

**Signal to spawn**: after the recon you see 3+ large independent areas AND the user asked for a full mapping.

When spawning, give each subagent a tight scope (specific folders + specific questions) and strict read-only constraint. Spawn all in a single parallel call.

## Rules

- Read-only: no file modifications, no writes, no installs
- Default to doing it yourself — don't spawn for the sake of spawning
- The final report is factual and direct — no filler
- If the user asked a specific question, make sure the answer is prominent in the report
