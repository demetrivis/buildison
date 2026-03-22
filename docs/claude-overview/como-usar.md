# Como Usar — Guia Pratico

Exemplos reais de como usar o template no dia a dia.

## Comecando um projeto novo

```bash
# Criar repo a partir do template
gh repo create meu-saas --template seu-user/claude-code-template --private
cd meu-saas

# Abrir com Claude Code
claude
```

Pronto. Os agentes, comandos e skills ja estao carregados.

## Cenario 1: Criar uma feature completa

Voce quer adicionar um sistema de pagamentos com tabela no banco, logica de processamento, e endpoint de API.

```
/sub Criar feature de pagamentos: tabela payments no banco, service de processamento, e endpoint POST /api/v1/payments
```

O Claude vai:
1. Spawnar o agent `db` para criar a migration da tabela payments com RLS
2. Spawnar o agent `logic` para implementar o PaymentService
3. Spawnar o agent `api` para criar o endpoint com schemas
4. Consolidar tudo num resultado coerente

Cada agente consulta sua skill para seguir as convencoes do projeto.

## Cenario 2: Entender um codebase existente

Voce entrou num projeto que ja tem codigo e precisa entender como funciona.

```
/explore
```

O Claude faz um recon rapido e spawna 2-3 subagentes que exploram areas diferentes do projeto em paralelo. Voce recebe um relatorio consolidado: stack, modulos, padroes, observacoes.

## Cenario 3: Diagnosticar um bug em producao

Os logs mostram erros intermitentes e voce precisa entender o que esta acontecendo.

```
/logs
```

O Claude localiza os logs, spawna subagente(s) que parseiam e categorizam tudo, e entrega um relatorio: errors agrupados com contagem, padroes de retry, timeline do incidente, e acoes recomendadas.

## Cenario 4: Tarefa complexa que precisa de debate

Voce esta redesenhando o sistema de autenticacao e quer perspectivas diferentes.

```
/team Preciso redesenhar o auth para suportar OAuth2 + magic links. Quero teammates que debatam a melhor abordagem.
```

O Claude cria uma equipe de teammates independentes — sessoes Claude Code separadas que se comunicam. Um pode focar em seguranca, outro em UX, outro em implementacao tecnica. Eles debatem entre si e convergem.

## Cenario 5: Fluxo de git completo

Voce terminou de codar e quer commitar, pushar e abrir PR.

```
/commit
```
Claude analisa as mudancas, stage os arquivos certos, escreve a mensagem.

```
/push
```
Claude verifica o estado, pusha com -u se a branch e nova.

```
/pr
```
Claude analisa todos os commits da branch, cria o PR com summary e test plan, retorna a URL.

```
/tlg
```
Claude mostra o grafico visual das branches para voce confirmar que esta tudo certo.

## Cenario 6: Configurar infraestrutura

Voce precisa de Docker e CI/CD para o projeto.

```
/docker
```
Claude cria Dockerfile multi-stage, docker-compose para dev, e .dockerignore.

```
/ghaction Quero CI com testes e lint em PRs, e build de Docker image em push para main
```
Claude cria os workflows YAML em `.github/workflows/`.

## Cenario 7: Tarefa focada com um subagente

Voce esta no meio de uma conversa e precisa refatorar um arquivo grande sem perder o fio da meada.

```
/sub Refatorar src/core/services/payment_service.py — extrair validacoes para metodos privados e adicionar logging estruturado
```

Claude spawna 1 subagente para fazer o refactor enquanto voce continua discutindo os proximos passos.

## Cenario 8: Conectar o projeto a uma VPS

Voce tem PostgreSQL e Redis rodando numa VPS e precisa configurar a conexao.

Basta pedir ao Claude — ele vai consultar a skill `database/` que tem references sobre conexao remota a PostgreSQL e Redis em VPS, incluindo: setup de user, pg_hba.conf, pool asyncpg, redis-py, SSL, SSH tunnel, health checks e retry com backoff.

## Dicas gerais

**Deixe o Claude decidir**: na maioria dos casos, voce nao precisa especificar quais agentes usar. O Claude analisa a tarefa e decide sozinho. Os comandos `/sub` e `/team` existem para quando voce quer ser explicito.

**Skills sao consultadas automaticamente**: voce nao precisa dizer "consulte a skill de API". Quando o agent `api.md` e spawnado, ele ja sabe que deve ler a skill antes de comecar.

**Comandos de git sao seguros**: /commit nunca faz `git add .`, /push nunca faz force push, /pr analisa todos os commits. Voce pode usar sem medo.

**Adicione suas proprias skills**: se o seu projeto usa uma tecnologia especifica (Stripe, AWS, etc.), crie uma skill em `.claude/skills/` seguindo o padrao pasta + SKILL.md + references/. O Claude vai consultar automaticamente.
