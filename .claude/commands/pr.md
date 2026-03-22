# /pr — Criar Pull Request

You have been invoked with the `/pr` command. Create a well-structured pull request on GitHub.

## Steps

1. Gather context in parallel:
   - `git status` — check for uncommitted changes
   - `git branch --show-current` — current branch
   - `git log main..HEAD --oneline` (or develop..HEAD) — all commits in this branch
   - `git diff main...HEAD --stat` — files changed summary

2. If there are uncommitted changes, warn the user and suggest committing first.

3. If the branch hasn't been pushed, push it with `-u`:
```bash
git push -u origin <branch-name>
```

4. Analyze ALL commits in the branch (not just the last one) to understand the full scope of changes.

5. Create the PR using `gh`:
```bash
gh pr create --title "concise title under 70 chars" --body "$(cat <<'EOF'
## Summary
- What changed and why (2-4 bullet points covering ALL commits)

## Changes
- Key technical changes

## Test plan
- [ ] How to verify this works

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

6. Return the PR URL to the user.

## Options

If the user provides context with the command, use it:
- `/pr` alone — analyze commits and generate everything
- `/pr draft` — create as draft PR: add `--draft` flag
- `/pr fix #123` — link to issue: mention "Closes #123" in the body
- `/pr base develop` — target a specific base branch: add `--base develop`

## Rules

- Title under 70 chars, descriptive but concise
- Body must cover ALL commits in the branch, not just the latest
- Always push before creating the PR
- If `gh` is not installed or not authenticated, explain how to set it up
- Link related issues when mentioned in commits or by the user
- Never create a PR from main/master to main/master
