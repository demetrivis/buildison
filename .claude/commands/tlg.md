# /tlg — Tree Log Graph

You have been invoked with the `/tlg` command. Show a visual git history with branch topology.

## Steps

1. Run the tree log graph:
```bash
git log --oneline --graph --all --decorate -30
```

2. After showing the graph, provide a brief summary:
   - Current branch and where HEAD is
   - How many commits ahead/behind main (or develop)
   - Any notable branch points or merges visible in the graph
   - Active branches and their latest commit

3. If the user provides arguments, adapt:
   - `/tlg` — last 30 commits, all branches
   - `/tlg 50` — last 50 commits
   - `/tlg main` — only main branch history
   - `/tlg feat/auth` — only that branch and its base

## Extra Context

If useful, also run:
```bash
git branch -a --sort=-committerdate --format='%(refname:short) %(committerdate:relative) %(subject)'
```
This shows all branches sorted by last activity — helps understand which branches are active.

## Rules

- Keep the summary short — the graph speaks for itself
- If the repo has hundreds of branches, limit to recent/active ones
- Don't modify anything — this is read-only
