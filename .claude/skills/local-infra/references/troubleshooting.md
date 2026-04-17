# Troubleshooting — local-infra

Problemas comuns ao subir/usar o stack local.

## "port is already allocated" ao subir

Outro processo já ocupa 5432 / 6379 / 4040. Descobrir quem:

```bash
lsof -iTCP:5432 -sTCP:LISTEN
lsof -iTCP:6379 -sTCP:LISTEN
```

Opções:
- Matar o processo antigo (`kill <PID>`)
- Parar um Postgres/Redis instalado localmente via Homebrew: `brew services stop postgresql@16` / `brew services stop redis`
- Trocar a porta no `docker-compose.yml` (ex: `"5433:5432"`) e ajustar connection strings dos projetos

## `host.docker.internal` não resolve (Linux)

No macOS/Windows o Docker Desktop resolve automaticamente. No Linux precisa do `extra_hosts`:

```yaml
services:
  meu-app:
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

Sem isso, o container vê `host.docker.internal` como nome desconhecido.

## ngrok não sobe — "authtoken required"

Confirme que `~/local-infra/.env` existe com `NGROK_AUTHTOKEN=...` e que o docker-compose está lendo o arquivo (docker compose lê `.env` do diretório do `docker-compose.yml` automaticamente).

Testa:

```bash
cd ~/local-infra
docker compose config    # deve mostrar NGROK_AUTHTOKEN resolvido (não como ${NGROK_AUTHTOKEN})
```

Se aparecer vazio, o `.env` não foi carregado — cria o arquivo e tenta de novo.

## Postgres sobe mas não aceita conexão

Ver health:

```bash
docker compose ps
docker compose logs postgres
```

Se ficar em "starting" por muito tempo, geralmente é o init dos scripts em `postgres-init/` falhando. Checar logs — um script `.sql` com erro aborta a inicialização.

Para resetar do zero:

```bash
docker compose down -v    # -v apaga os volumes (PERDE OS DADOS)
docker compose up -d
```

## Conexão do app container → Postgres dá "connection refused"

Causas comuns:
1. App usando `localhost` em vez de `host.docker.internal` estando em container
2. App não tem `extra_hosts` (Linux)
3. App subiu antes do Postgres estar healthy — adiciona `depends_on` com `condition: service_healthy`:

```yaml
services:
  app:
    depends_on:
      postgres:
        condition: service_healthy
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

## Dados sumiram após `docker compose down`

Não deveria — volumes nomeados persistem. Se rodou `down -v`, os volumes foram apagados. Se os nomes dos volumes mudaram (ex: renomeou o diretório `local-infra`), o compose pode ter criado volumes novos e "perdido" os antigos. Listar:

```bash
docker volume ls | grep local-
```

Os volumes do stack devem aparecer como `local-postgres-data` e `local-redis-data` (nomes fixos definidos no compose).

## Redis não persiste entre restarts

Verificar se `appendonly yes` está no command e o volume `redis-data` está montado em `/data`. Se estiver usando modo dev sem persistência (`--save "" --appendonly no`), é esperado.

## Criar database adicional para um projeto específico

Por padrão só existe o database `dev`. Pra criar outro:

```bash
docker exec -it local-postgres psql -U dev -d dev -c "CREATE DATABASE projeto_x OWNER dev;"
```

Ou adiciona em `postgres-init/01-extensions.sql` (só roda em volume novo).
