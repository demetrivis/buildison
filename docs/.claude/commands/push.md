# /push — Push Seguro para o Remote

You have been invoked with the `/push` command. Push the current branch to the remote safely.

## Steps

1. Run `git status` to check for uncommitted changes. If there are changes, warn the user and ask if they want to commit first (suggest using `/commit`).

2. Run `git branch --show-current` to get the current branch name.

3. Check if the branch tracks a remote:
```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
```

4. If no upstream exists, push with `-u` to set tracking:
```bash
git push -u origin <branch-name>
```

5. If upstream exists, check if we're ahead:
```bash
git status -sb
```
Then push normally:
```bash
git push
```

6. Confirm success by showing the remote status after push.

## Rules

- NEVER force push (`--force` or `-f`) to main/master — warn the user if they ask
- NEVER force push to any shared branch without explicit user confirmation
- If push is rejected (non-fast-forward), explain the situation and suggest `git pull --rebase` first
- If the branch is new and has no upstream, always use `-u` flag
- If there are uncommitted changes, warn before pushing — don't push a dirty state silently
