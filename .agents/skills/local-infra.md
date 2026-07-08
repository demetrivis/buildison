---
name: local-infra
description: "Monta stack de infra local (Postgres + Redis + Qdrant + ngrok + cloudflared) via Docker Desktop para desenvolvimento. Use quando precisar criar ~/local-infra/docker-compose.yml do zero, adicionar serviços ao stack local, configurar tunnel (ngrok ou Cloudflare), subir o Qdrant para memória vetorial de agentes, ou quando o usuário pedir 'subir a infra local', 'setup do docker', 'montar ambiente local de dev'."
---

<!-- Gerado de .claude/skills/local-infra/SKILL.md por scripts/gen-antigravity.mjs — não edite à mão. -->

# Local Infra — Docker Desktop stack

Setup padrão de infraestrutura local para desenvolvimento: Postgres, Redis, Qdrant, ngrok e cloudflared rodando como containers do Docker Desktop. Fica em `~/local-infra/` (fora do repo de qualquer projeto), **stack global compartilhado entre todos os projetos da máquina** — sobe uma vez, serve todos.

## Credenciais padrão

- Postgres: user `dev`, senha `localdev`, porta `5432`
- Redis: sem auth, porta `6379`
- Qdrant: sem auth, REST `6333`, gRPC `6334` (memória vetorial de agentes — ver skill `agent-memory`)
- ngrok: porta `4040` (dashboard web) — tunnel rápido com URL efêmera
- cloudflared: tunnel nomeado com URL estável no seu domínio (token via Cloudflare Zero Trust)

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

2. **Criar `~/local-infra/.env`** com os tokens dos tunnels:

   ```env
   # ngrok — https://dashboard.ngrok.com/get-started/your-authtoken
   NGROK_AUTHTOKEN=<token_aqui>
   # Cloudflare Tunnel — Zero Trust > Networks > Tunnels > Create a tunnel (Cloudflared)
   CLOUDFLARE_TUNNEL_TOKEN=<token_aqui>
   ```

   Sem um token, o container do respectivo tunnel fica em restart loop — o resto do stack sobe normalmente.

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

   # Qdrant
   curl -s http://localhost:6333/healthz          # health check
   curl -s http://localhost:6333/collections      # lista collections (vazio no início)

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

## Expor endpoint local (tunnels)

Dois tunnels disponíveis — escolha por caso de uso:

| | ngrok | cloudflared |
| :--- | :--- | :--- |
| URL | aleatória/efêmera (grátis) | estável, no seu domínio |
| Setup | só o `NGROK_AUTHTOKEN` | conta CF + tunnel nomeado + `CLOUDFLARE_TUNNEL_TOKEN` |
| Quando | teste rápido, throwaway | webhook permanente, demo pra cliente |

### ngrok

Para receber webhooks (Stripe, GitHub, etc) no app local:

```bash
# Tunnel ad-hoc pra porta 8000 do host
docker exec -it local-ngrok ngrok http host.docker.internal:8000
```

Ou configurar tunnel permanente no `docker-compose.yml` (ver reference).

### cloudflared (tunnel nomeado, URL estável)

1. No dashboard: **Cloudflare Zero Trust → Networks → Tunnels → Create a tunnel** (tipo *Cloudflared*).
2. Copie o **token** gerado para `CLOUDFLARE_TUNNEL_TOKEN` no `~/local-infra/.env`.
3. Ainda no dashboard, em **Public Hostnames**, mapeie o hostname para o serviço local, ex:
   `webhook.seudominio.com` → `http://host.docker.internal:8000`.
4. `docker compose up -d cloudflared` — o connector conecta e o hostname já responde.

O roteamento hostname→serviço fica **no dashboard**, não no compose. O container só roda o connector com o token.

## References

- @references/docker-compose.md — `docker-compose.yml` completo comentado
- @references/troubleshooting.md — problemas comuns (porta ocupada, host.docker.internal não resolve, ngrok token, etc)

> Referências detalhadas desta skill vivem em `.claude/skills/local-infra/references/` (repo buildison).
