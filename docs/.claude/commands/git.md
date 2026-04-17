# /git — Operações Git Assistidas

You have been invoked with the `/git` command. Your job is to help with git operations intelligently — not just running commands, but understanding context, choosing the right strategy, and preventing mistakes.

## Instructions

1. **Assess the situation**: Before any git operation, run `git status` and `git log --oneline -10` to understand the current state. Know which branch you're on, what's staged, what's modified, what's untracked.

2. **Determine what the user needs**: Based on the conversation context, decide which operation is appropriate. If unclear, ask.

3. **Execute with safety**: Never run destructive operations without explaining what will happen first. Prefer safe alternatives when they exist.

## Common Operations

### Commit
- Stage only the relevant files by name — never `git add .` or `git add -A` blindly
- Check for sensitive files (.env, credentials, keys) before staging
- Write commit messages that explain WHY, not WHAT
- Follow the repo's existing commit message style (check `git log` first)
- Always include `Co-Authored-By: Claude <noreply@anthropic.com>` when Claude wrote the code

### Branch
- Branch names follow: `type/short-description` (e.g., `feat/user-auth`, `fix/payment-timeout`, `refactor/logging-setup`)
- Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`
- Always branch from an up-to-date main/develop

### Pull Request
- Use `gh pr create` with a clear title (<70 chars) and structured body
- Body includes: Summary (bullet points), Test plan, and any breaking changes
- Link related issues when they exist

### Merge Conflicts
- When conflicts are found, spawn a subagent to analyze each conflicted file
- Present the conflict with both sides explained before resolving
- Prefer the approach that preserves both intentions when possible

### Rebase vs Merge
- Default to rebase for feature branches to keep history clean
- Use merge for long-lived branches or when history matters
- Never rebase shared/public branches

### Stash
- Always name stashes: `git stash push -m "description"`
- List stashes before applying to pick the right one

### Undo Operations
- `git reset --soft` to undo commit but keep changes staged
- `git restore` to discard file changes (safer than checkout)
- Always explain what will be lost before any undo operation

## Safety Rules

- NEVER force push to main/master
- NEVER run `git reset --hard` or `git clean -f` without explicit user confirmation
- NEVER skip hooks (--no-verify) unless the user explicitly asks
- NEVER commit .env, credentials, keys, or secrets
- Always check `git status` before and after operations
- If something looks wrong, stop and explain before proceeding

## Subagent Usage

For complex git operations, spawn subagents:
- **Conflict resolution**: 1 subagent per conflicted file to analyze and propose resolution
- **Large commits**: 1 subagent to review the diff for issues before committing
- **PR preparation**: 1 subagent to analyze all commits and draft the PR description
