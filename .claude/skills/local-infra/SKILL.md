---
name: local-infra
description: "Monta stack de infra local (Postgres + Redis + ngrok) via Docker Desktop para desenvolvimento. Use quando precisar criar ~/local-infra/docker-compose.yml do zero, adicionar serviços ao stack local, configurar ngrok tunnel, ou quando o usuário pedir 'subir a infra local', 'setup do docker', 'montar ambiente local de dev'."
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# Local Infra — Docker Desktop stack

Setup padrão de infraestrutura local para desenvolvimento: Postgres, Redis e ngrok rodando como containers do Docker Desktop. Fica em `~/local-infra/` (fora do repo de qualquer projeto), compartilhado entre todos os projetos da máquina.

## Credenciais padrão

- Postgres: user `dev`, senha `localdev`, porta `5432`
- Redis: sem auth, porta `6379`
- ngrok: porta `4040` (dashboard web)

De dentro de um container consumidor, use `host.docker.internal`. Do host (máquina), use `localhost`.

## Estrutura

```
~/local-infra/
├── docker-compose.yml
├── .env                    # NGROK_AUTHTOKEN
└── postgres-init/
    └── 01-extensions.sql   # extensions + databases iniciais (opcional)
```

## Passos para montar do zero

1. **Criar diretório**: `mkdir -p ~/local-infra/postgres-init`

2. **Criar `~/local-infra/.env`** com token do ngrok (obter em https://dashboard.ngrok.com/get-started/your-authtoken):

   ```env
   NGROK_AUTHTOKEN=<token_aqui>
   ```

3. **Criar `~/local-infra/docker-compose.yml`** — ver `@references/docker-compose.md` para versão completa e comentada.

4. **Criar `~/local-infra/postgres-init/01-extensions.sql`** (opcional, cria extensions comuns e databases por projeto):

   ```sql
   CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
   CREATE EXTENSION IF NOT EXISTS "pgcrypto";
   -- Databases adicionais por projeto (além do 'dev' default):
   -- CREATE DATABASE projeto_x OWNER dev;
   ```

5. **Subir**:

   ```bash
   cd ~/local-infra
   docker compose up -d
   docker compose ps      # verifica se todos subiram healthy
   ```

6. **Testar conectividade**:

   ```bash
   # Postgres
   docker exec -it local-postgres psql -U dev -d dev -c "SELECT version();"

   # Redis
   docker exec -it local-redis redis-cli ping   # deve retornar PONG

   # ngrok dashboard
   open http://localhost:4040
   ```

## Regras

- O stack fica em `~/local-infra/`, **NUNCA** dentro de um repo de projeto — é infra compartilhada da máquina
- Volumes nomeados (não bind mounts) para dados persistentes
- Healthchecks em todos os serviços
- Portas expostas no host para acesso direto (psql, redis-cli, clientes de DB)
- `host.docker.internal` é o hostname correto para containers de projetos consumirem o stack (Docker Desktop resolve isso automaticamente no macOS/Windows)
- Credenciais locais podem ficar commitadas — o stack nunca é exposto além da máquina local

## Acesso a partir de projetos

**Projeto rodando no host** (ex: `uvicorn src.main:app`):
```env
DATABASE_URL=postgresql://dev:localdev@localhost:5432/meu_projeto
REDIS_URL=redis://localhost:6379/0
```

**Projeto rodando em container** (docker-compose do próprio projeto):
```env
DATABASE_URL=postgresql://dev:localdev@host.docker.internal:5432/meu_projeto
REDIS_URL=redis://host.docker.internal:6379/0
```

E no `docker-compose.yml` do projeto, adiciona `extra_hosts` para garantir resolução em Linux:

```yaml
services:
  app:
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

## Expor endpoint local via ngrok

Para receber webhooks (Stripe, GitHub, etc) no app local:

```bash
# Entra no container do ngrok e cria tunnel pra porta 8000 do host
docker exec -it local-ngrok ngrok http host.docker.internal:8000
```

Ou configurar tunnel permanente no `docker-compose.yml` (ver reference).

## References

- @references/docker-compose.md — `docker-compose.yml` completo comentado
- @references/troubleshooting.md — problemas comuns (porta ocupada, host.docker.internal não resolve, ngrok token, etc)
