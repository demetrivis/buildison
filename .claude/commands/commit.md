# /commit — Commit Inteligente

You have been invoked with the `/commit` command. Create a well-crafted git commit from the current changes.

## Steps

1. Run `git status` and `git diff --staged` and `git diff` to see all changes (staged and unstaged).

2. If nothing is staged, analyze the unstaged changes and stage the relevant files **by name** — never `git add .` or `git add -A`. Skip any sensitive files (.env, credentials, keys, tokens).

3. Check `git log --oneline -5` to understand the repo's commit message style.

4. Write the commit message:
   - First line: imperative mood, under 72 chars, explains WHY not WHAT
   - Blank line
   - Body (if needed): context, reasoning, what changed and why
   - End with: `Co-Authored-By: Claude <noreply@anthropic.com>`

5. Commit using a HEREDOC:
```bash
git commit -m "$(cat <<'EOF'
the commit message here

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

6. Run `git status` after to confirm success.

## Rules

- NEVER use `git add .` or `git add -A` — stage files by name
- NEVER commit .env, secrets, credentials, or key files
- NEVER use --no-verify to skip hooks
- NEVER amend previous commits unless the user explicitly asks
- If pre-commit hook fails: fix the issue, re-stage, create a NEW commit (not --amend)
- Match the repo's existing commit style (conventional commits, etc.)
- If there are no changes to commit, say so and stop
