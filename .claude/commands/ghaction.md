# /ghaction — Criar GitHub Actions Workflows

You have been invoked with the `/ghaction` command. Your job is to create, edit, or debug GitHub Actions workflows for this project.

## Instructions

1. **Understand the need**: Determine what the user wants automated — CI, CD, tests, linting, Docker builds, deploy, release, scheduled tasks, etc.

2. **Detect the stack**: Read the project manifest (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, etc.) to determine the language and toolchain. This determines the setup actions and commands to use.

3. **Check existing workflows**: Read `.github/workflows/` to see what already exists. Don't duplicate or conflict with existing workflows.

4. **Create the workflow**: Write the YAML file in `.github/workflows/`. Follow the conventions below.

5. **Validate**: After writing, check the YAML syntax and ensure all referenced secrets, actions, and paths are correct.

## Workflow Conventions

### File naming
```
.github/workflows/
├── ci.yml              # Tests + lint on PRs and pushes
├── cd.yml              # Automated deploy
├── docker-build.yml    # Docker image build and push
├── release.yml         # Release creation
└── scheduled.yml       # Cron tasks
```

### Structure pattern

```yaml
name: Descriptive Name

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  job-name:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4

      - name: Step description
        run: command
```

### Best practices

- **Always pin action versions** with major version: `actions/checkout@v4`
- **Set minimal permissions**: `permissions: contents: read` by default, expand only as needed
- **Use environment variables** for versions and repeated values
- **Cache dependencies**: use built-in caching in setup actions
- **Fail fast**: `strategy.fail-fast: true` in matrix builds
- **Timeout**: always set `timeout-minutes` to prevent runaway jobs
- **Secrets**: reference via `${{ secrets.NAME }}`, never hardcode

### Common workflow templates

**CI — Python (pytest + ruff + mypy)**:
```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: "pip"

      - name: Install dependencies
        run: pip install -e ".[dev]"

      - name: Lint
        run: ruff check src/

      - name: Type check
        run: mypy src/

      - name: Tests
        run: pytest tests/ -v --tb=short
```

**CI — Node.js (vitest/jest + eslint + tsc)**:
```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"

      - name: Install dependencies
        run: npm ci

      - name: Lint
        run: npm run lint

      - name: Type check
        run: npm run typecheck

      - name: Tests
        run: npm test
```

**CI — Go**:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-go@v5
        with:
          go-version: "1.22"
          cache: true

      - name: Lint
        uses: golangci/golangci-lint-action@v6

      - name: Tests
        run: go test ./... -v
```

**Docker Build + Push**:
```yaml
name: Docker Build

on:
  push:
    branches: [main]
    tags: ["v*"]

permissions:
  contents: read
  packages: write

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4

      - uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=semver,pattern={{version}}
            type=sha,prefix=

      - uses: docker/build-push-action@v6
        with:
          context: .
          file: docker/Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

**Scheduled task**:
```yaml
name: Scheduled Task

on:
  schedule:
    - cron: "0 3 * * 1"  # Every Monday at 3am UTC

permissions:
  contents: read

jobs:
  run:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
      - name: Run task
        run: <command>
```

## Rules

- Always create the `.github/workflows/` directory if it doesn't exist
- Validate YAML structure before finishing
- Don't create workflows that duplicate existing ones — extend or replace instead
- If the workflow needs secrets, list them clearly and tell the user to add them in GitHub Settings
- Use composite actions or reusable workflows for shared logic across multiple workflows
