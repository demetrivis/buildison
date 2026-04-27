# /portainer — Gerar Stack para Portainer (Docker Swarm + Traefik)

You have been invoked with the `/portainer` command. Your job is to generate a production-ready Portainer stack file (Docker Swarm compose) for this project, with Traefik as reverse proxy.

## Instructions

1. **Entenda o projeto**: Leia o manifesto (`package.json`, `pyproject.toml`, etc.), `docker-compose.yml` existente, e qualquer Dockerfile para entender os serviços, portas e variáveis de ambiente necessárias.

2. **Colete informações**: Se o usuário não especificou, pergunte:
   - Domínio público (ex: `app.exemplo.com.br`)
   - Nome do projeto/stack (usado como prefixo nos labels e redes)
   - Imagem Docker (ex: `ghcr.io/usuario/repo`)
   - Quais serviços precisa: app, worker, postgres, redis, outros?
   - Arquitetura do servidor (amd64 ou arm64/Oracle Ampere)?

3. **Gere o stack**: Siga as convenções abaixo.

4. **Gere a lista de variáveis**: Sempre produza, separado do YAML, a lista completa de variáveis que o usuário precisa configurar no Portainer → Environment variables.

---

## Convenções

### Estrutura do arquivo

```yaml
version: "3.7"

# ─────────────────────────────────────────────────────────────────────────────
# Stack Portainer — <Nome do Projeto>
#
# Pré-requisitos no host:
#   - Docker Swarm inicializado (docker swarm init)
#   - Rede overlay `network_public` já existe (Traefik usa ela)
#       docker network create --driver=overlay --attachable network_public
#   - Traefik rodando com entrypoint `websecure` e certresolver `letsencryptresolver`
#   - DNS do domínio apontando pro IP do servidor
#   - Imagens publicadas (ex: ghcr.io via GitHub Actions)
#
# Variáveis (Portainer → Environment variables):
#   <listar todas as variáveis aqui>
# ─────────────────────────────────────────────────────────────────────────────
```

### Redes

Sempre duas redes:
- `network_public` (externa, já existe — compartilhada com Traefik)
- `<stack>_internal` (overlay, internal: true — só serviços internos se comunicam)

```yaml
networks:
  network_public:
    name: network_public
    external: true

  <stack>_internal:
    driver: overlay
    internal: true
```

### Serviço exposto via Traefik (app principal)

```yaml
  app:
    image: ghcr.io/${GITHUB_REPO}-app:${APP_TAG:-latest}
    networks:
      - network_public
      - <stack>_internal
    environment:
      - NODE_ENV=production
      # ... variáveis do serviço
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
        delay: 10s
      update_config:
        order: start-first      # zero-downtime: sobe o novo antes de derrubar o velho
        parallelism: 1
        delay: 10s
        failure_action: rollback
      labels:
        - traefik.enable=1
        - traefik.http.routers.<stack>.rule=Host(`${DOMAIN}`)
        - traefik.http.routers.<stack>.entrypoints=websecure
        - traefik.http.routers.<stack>.tls.certresolver=letsencryptresolver
        - traefik.http.routers.<stack>.service=<stack>
        - traefik.http.services.<stack>.loadbalancer.server.port=<porta>
        - traefik.http.services.<stack>.loadbalancer.passHostHeader=true
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:<porta>/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 60s   # folga para migrate + boot antes do Swarm contar retries
```

### Serviço interno (worker, queue consumer, etc.)

```yaml
  worker:
    image: ghcr.io/${GITHUB_REPO}-worker:${APP_TAG:-latest}
    networks:
      - <stack>_internal    # sem network_public — não expõe nada
    environment:
      # ... mesmas variáveis do app que ele precisar
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
        delay: 10s
      update_config:
        order: stop-first   # worker: para o velho antes de subir o novo (evita job duplicado)
        parallelism: 1
        delay: 5s
        failure_action: rollback
```

### Postgres

```yaml
  postgres:
    image: postgres:16-alpine
    networks:
      - <stack>_internal
    environment:
      - POSTGRES_DB=${POSTGRES_DB:-<default_db>}
      - POSTGRES_USER=${POSTGRES_USER:-<default_user>}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-<default_user>} -d ${POSTGRES_DB:-<default_db>}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 20s
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
        delay: 5s
```

### Redis

```yaml
  redis:
    image: redis:7-alpine
    command: ["redis-server", "--appendonly", "yes"]
    networks:
      - <stack>_internal
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
        delay: 5s
```

### Volumes

```yaml
volumes:
  postgres_data:
  redis_data:
  # outros volumes persistentes
```

---

## Regras

### Variáveis de ambiente
- NUNCA hardcode senhas, tokens ou secrets no YAML
- Todos os valores sensíveis via variável Portainer: `${VARIAVEL}`
- Valores com default seguro usam `${VAR:-default}` (ex: nome de db, user)
- Senhas e secrets NUNCA têm default: `${POSTGRES_PASSWORD}` sem fallback

### Labels Traefik
- `traefik.enable=1` (não `true` — Portainer aceita os dois mas `1` é mais explícito)
- Nome do router e service = nome da stack (sem caracteres especiais)
- Sempre `passHostHeader=true`
- Sempre `tls.certresolver=letsencryptresolver` (ou o nome configurado no Traefik)
- Priority só quando há múltiplos routers para o mesmo host (subpaths)

### Deploy config
- `order: start-first` para apps expostos (zero-downtime)
- `order: stop-first` para workers e consumers (evita processamento duplicado)
- `failure_action: rollback` sempre (Swarm volta para a versão anterior se o deploy falhar)
- `placement: node.role == manager` por padrão (single-node); ajuste para multi-node

### Healthcheck
- `start_period` generoso (60s) para apps com migrate na inicialização
- `start_period` menor (20s) para postgres/redis
- Usar `wget --spider` para HTTP (não depende de curl)
- Usar `pg_isready` para postgres
- Usar `redis-cli ping` para redis

### Redes
- App exposto: `network_public` + `<stack>_internal`
- Serviços internos: somente `<stack>_internal`
- `internal: true` na rede interna (bloqueia acesso externo no nível do Swarm)

---

## Output esperado

Gere sempre dois blocos:

**1. Stack YAML** — pronto para colar no Portainer → Stacks → Add Stack

**2. Checklist de variáveis** — tabela com: variável | descrição | como gerar

```
| Variável              | Descrição                          | Como gerar                        |
|-----------------------|------------------------------------|-----------------------------------|
| GITHUB_REPO           | usuario/repositorio                | fixo                              |
| APP_TAG               | Tag da imagem (default: latest)    | fixo ou via CI                    |
| DOMAIN                | Domínio público                    | fixo                              |
| POSTGRES_DB           | Nome do banco                      | fixo                              |
| POSTGRES_USER         | Usuário do banco                   | fixo                              |
| POSTGRES_PASSWORD     | Senha do banco                     | openssl rand -hex 24              |
| JWT_SECRET            | Chave JWT                          | openssl rand -hex 32              |
```

Se o usuário não forneceu informações suficientes para gerar o stack completo, pergunte antes de gerar.
