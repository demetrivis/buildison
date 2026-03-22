# Comandos

Comandos sao acoes que voce invoca digitando `/nome` no Claude Code. Cada comando dispara um comportamento especifico — desde um commit inteligente ate montar um time de agentes paralelos.

Os comandos ficam em `.claude/commands/` como arquivos `.md`. O Claude Code os detecta automaticamente.

## Comandos de Git

### /commit

Cria um commit inteligente a partir das mudancas atuais.

O que faz:
1. Roda `git status` e `git diff` para entender o que mudou
2. Stage os arquivos relevantes por nome (nunca `git add .`)
3. Verifica o estilo de commit do repo via `git log`
4. Escreve a mensagem no modo imperativo explicando o por que
5. Inclui `Co-Authored-By: Claude` automaticamente

Seguranca: nunca commita .env, secrets, ou credentials. Nunca usa --no-verify. Se o hook falha, corrige e cria commit novo (nunca --amend).

### /push

Push seguro para o remote.

O que faz:
1. Verifica se tem mudancas nao commitadas (avisa se sim)
2. Se a branch nao tem upstream, faz push com `-u`
3. Se ja tem, faz push normal

Seguranca: nunca force push para main/master. Se o push e rejeitado, sugere `git pull --rebase`.

### /pr

Cria um Pull Request no GitHub.

O que faz:
1. Analisa TODOS os commits da branch (nao so o ultimo)
2. Pusha a branch se necessario
3. Cria o PR com `gh pr create` com titulo e body estruturado
4. Retorna a URL do PR

Opcoes:
- `/pr` — analisa e gera tudo automaticamente
- `/pr draft` — cria como draft
- `/pr fix #123` — linka a issue
- `/pr base develop` — target especifico

### /tlg

Mostra o historico git visual com grafico de branches.

O que faz:
1. Roda `git log --oneline --graph --all --decorate`
2. Resume: branch atual, commits ahead/behind, branches ativas

Opcoes:
- `/tlg` — ultimos 30 commits, todas as branches
- `/tlg 50` — ultimos 50
- `/tlg main` — so a branch main

### /git

Operacoes git assistidas com contexto e seguranca.

Cobre: commits, branches, PRs, merge conflicts, rebase, stash, undo. Para cada operacao, o Claude entende o contexto antes de agir e nunca roda comandos destrutivos sem avisar.

## Comandos de Orquestracao

### /team

Monta uma equipe de **teammates** — sessoes Claude Code independentes que se comunicam entre si.

Isso e diferente de subagentes. Teammates tem context window propria, task list compartilhada, e podem trocar mensagens diretamente. Sao sessoes Claude Code separadas que trabalham em paralelo com coordenacao.

Quando usar: tarefas complexas que precisam de colaboracao, debate entre workers, ou trabalho paralelo em camadas diferentes (frontend, backend, testes).

Requer: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` ativado no settings.

### /sub

Spawna subagentes sob demanda — o comando leve e flexivel.

O que faz:
1. Avalia a tarefa e identifica pecas independentes
2. Decide quantos subagentes (1, 2, 3, ou mais)
3. Para cada um, define o escopo e decide se usa um agent predefinido de `.claude/agents/` ou cria um papel ad hoc
4. Spawna todos em paralelo
5. Consolida os resultados

Diferenca do /team: subagentes reportam de volta pra voce e nao falam entre si. Teammates sao sessoes independentes que se comunicam.

### /explore

Spawna subagentes para explorar o codebase.

O que faz:
1. Faz um recon rapido com `ls` e `find`
2. Decide quantos subagentes (1, 2 ou 3) baseado na complexidade
3. Divide o projeto em areas para cada subagente investigar
4. Subagentes usam bash, grep, glob e read (somente leitura)
5. Consolida num relatorio: stack, modulos, padroes, observacoes

Quando usar: onboarding num codebase novo, antes de mudancas arquiteturais, ou quando precisa entender como algo funciona.

### /logs

Spawna subagente(s) para analisar logs do projeto.

O que faz:
1. Localiza os logs (arquivos, Docker, stdout)
2. Spawna 1-3 subagentes dependendo do volume
3. Cada subagente le, parseia e categoriza findings
4. Consolida relatorio: errors, warnings, padroes, timeline, acoes recomendadas

Formato do relatorio: factual, sem emojis, sem especulacao. Cita log entries especificas como evidencia.

## Comandos de Infraestrutura

### /docker

Cria e gerencia Dockerfiles e docker-compose.

O que faz: cria Dockerfiles multi-stage otimizados, docker-compose para dev e prod, .dockerignore, e roda checklist de otimizacao (layers, cache, security, health check).

### /ghaction

Cria workflows de GitHub Actions.

O que faz: cria YAML em `.github/workflows/` para CI (testes + lint), CD (deploy), Docker build + push, e tarefas agendadas. Inclui templates prontos e boas praticas (pin versions, cache, minimal permissions, timeouts).
