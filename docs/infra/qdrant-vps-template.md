# Qdrant na VPS (template) — memória vetorial dos agentes que segue você entre máquinas

> **Template do buildison.** Substitua os `<PLACEHOLDERS>` pelos seus valores e nunca
> commite IPs, domínios, emails ou keys reais no repo. Este doc ensina **quando** ir
> pra VPS, **como** subir com HTTPS + API key e **como plugar** no `.mcp.json` de cada
> projeto sem vazar segredo no Git.

## Quando ir pra VPS (e quando NÃO)

| Situação | Vai bem com... |
| :-- | :-- |
| Você só usa **um computador** | **Local** (`~/local-infra`). Mais simples. |
| Você programa em **vários PCs** e quer a memória do agente em todos | **VPS** (este doc). |
| Você quer **time** acessando o mesmo Qdrant | VPS (com API keys separadas se possível). |
| VPS é só pra testar uma tarde | Local. Não vale o esforço. |

> **Custo de VPS**: uma máquina de 1–2 GB RAM já roda Qdrant + Postgres + Redis pra dev (ex.: Oracle Cloud free tier, $5 VPS na Hetzner/DO, etc.).
>
> **Segurança em uma frase**: se a porta vai ficar **pública na internet**, **TEM** que ter TLS + API key. Ponto.

## Arquitetura do setup

```
                 +-------------------+
   PC laptop ────│  https://qdrant   │──┐
                 │    .seu-dominio   │  │ TLS (Let's Encrypt)
   PC desktop ───│      .com         │──┤ + API key header
                 +-------------------+  │
                                        ▼
                  [VPS]  Traefik ──► Qdrant (rede interna)
                          (porta 80/443)        (porta 6333, NÃO exposta)
```

- **Traefik** termina o TLS, valida o hostname e roteia pra rede interna do Docker.
- **Qdrant** escuta na rede privada — porta 6333 **não** abre pra internet.
- **API key** do Qdrant fica em env var no container; clientes mandam header `api-key:`.
- **A key** trafega **só sobre HTTPS** (TLS), nunca em texto puro.

## Passo a passo: subir Qdrant na VPS

Pré-requisitos na VPS:
- Docker (ou Docker Swarm) instalado.
- Um **subdomínio** apontando pra IP da VPS (ex.: `qdrant.seu-dominio.com` → `<IP-VPS>`, A record).
- Portas **80** e **443** abertas no firewall (Traefik faz o ACME challenge na 80 e serve HTTPS na 443).
- A porta **6333 NÃO precisa estar aberta** publicamente — o Traefik fala com o Qdrant pela rede interna.

### Opção A — Traefik (recomendado se vai expor outros serviços HTTP também)

> ⚠️ **Compose puro vs Swarm.** O arquivo abaixo é `docker-compose.yml` (`docker compose up -d`) e usa
> `--providers.docker`. Se a VPS roda **Docker Swarm** (`docker stack deploy`), esse provider **não enxerga
> services** — o Traefik sobe e não roteia nada, sem erro. Em Swarm troque por `--providers.swarm` e ponha as
> labels em `deploy.labels`. A skill `vps-infra` (no repo infrailson) tem o stack de Swarm pronto.

`docker-compose.yml`:

```yaml
services:
  traefik:
    image: traefik:v3
    command:
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.web.http.redirections.entrypoint.to=websecure
      - --entrypoints.web.http.redirections.entrypoint.scheme=https
      - --entrypoints.websecure.address=:443
      - --certificatesresolvers.le.acme.email=<SEU_EMAIL>
      - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.le.acme.httpchallenge=true
      - --certificatesresolvers.le.acme.httpchallenge.entrypoint=web
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - letsencrypt:/letsencrypt
    networks: [public]

  qdrant:
    image: qdrant/qdrant:latest
    environment:
      QDRANT__SERVICE__API_KEY: ${QDRANT_API_KEY}     # gere com: openssl rand -hex 32
    volumes:
      - qdrant_data:/qdrant/storage
    labels:
      - traefik.enable=true
      - traefik.http.routers.qdrant.entrypoints=websecure
      - traefik.http.routers.qdrant.rule=Host(`qdrant.<SEU_DOMINIO>`)
      - traefik.http.routers.qdrant.tls.certresolver=le
      - traefik.http.services.qdrant.loadbalancer.server.port=6333
    networks: [public, internal]

volumes:
  letsencrypt:
  qdrant_data:

networks:
  public:
  internal:
```

`.env` na VPS (NÃO commitar):
```
QDRANT_API_KEY=<gerada-com-openssl-rand-hex-32>
```

Subir: `docker compose up -d`. Em ~30s o cert é emitido e `https://qdrant.<SEU_DOMINIO>` responde.

### Opção B — Caddy (mais simples, 1 serviço a menos)

Se você só precisa do Qdrant HTTPS, Caddy faz tudo em ~10 linhas:

```yaml
services:
  caddy:
    image: caddy:2
    ports: ["80:80", "443:443"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
    depends_on: [qdrant]

  qdrant:
    image: qdrant/qdrant:latest
    environment:
      QDRANT__SERVICE__API_KEY: ${QDRANT_API_KEY}
    volumes: [qdrant_data:/qdrant/storage]
    # NÃO expõe porta — só acessível pelo caddy via rede interna do compose

volumes:
  caddy_data:
  qdrant_data:
```

`Caddyfile`:
```
qdrant.<SEU_DOMINIO> {
    reverse_proxy qdrant:6333
}
```

Caddy emite o certificado Let's Encrypt automaticamente. Pronto.

### Testar a VPS

```bash
# Sem api-key: deve dar 403
curl -s -o /dev/null -w "%{http_code}\n" https://qdrant.<SEU_DOMINIO>/collections

# Com api-key: deve dar 200 com a lista (vazia no início)
curl -s -H "api-key: $QDRANT_API_KEY" https://qdrant.<SEU_DOMINIO>/collections | jq
```

## Plugar no buildison (o instalador faz isso pra você)

Em qualquer projeto que herde o boilerplate:

```bash
# escolhe modo VPS uma vez por máquina (fica salvo em ~/.buildison/vps.env)
npx buildison install --memory=vps --qdrant-url=https://qdrant.<SEU_DOMINIO>
```

O instalador gera o `.mcp.json` (e config equivalente pra Codex/OpenCode) com:

```json
"qdrant-memory": {
  "command": "uvx",
  "args": ["mcp-server-qdrant"],
  "env": {
    "QDRANT_URL": "https://qdrant.<SEU_DOMINIO>",
    "QDRANT_API_KEY": "${QDRANT_API_KEY}",
    "COLLECTION_NAME": "agent_<projeto>",
    "EMBEDDING_MODEL": "sentence-transformers/all-MiniLM-L6-v2"
  }
}
```

> A literal `${QDRANT_API_KEY}` é **expandida pelo Claude Code a partir do ambiente do shell** que iniciou o `claude`. A key real **nunca entra** no `.mcp.json` versionado.

### Exportar a key pro shell (uma vez por máquina)

**Mac/Linux** (`~/.zshrc` ou `~/.bashrc`):
```bash
export QDRANT_API_KEY='sua-key-aqui'
```

**Windows PowerShell** (persistente — `User scope`):
```powershell
[Environment]::SetEnvironmentVariable('QDRANT_API_KEY','sua-key-aqui','User')
```

Reinicie o terminal/Claude Code pra valer.

## Local vs VPS (decisão e troca)

|  | Local (`~/local-infra`) | VPS |
| :-- | :-- | :-- |
| `QDRANT_URL` | `http://localhost:6333` | `https://qdrant.<dominio>` |
| API key | (não precisa) | obrigatória |
| Memória entre máquinas | ❌ só nessa | ✅ segue você |
| Custo | grátis | VPS + domínio |
| Quem mantém | você (Docker local) | você (VPS) |

> **Trocar de modo** depois: rode o instalador de novo com `--memory=local` ou `--memory=vps`. O config per-máquina (`~/.buildison/vps.env`) é atualizado.

> **Não há replicação automática**: se você salvar memórias no local e depois trocar pra VPS, elas **não aparecem lá**. Pra migrar, exporte/importe via `curl` na API do Qdrant.

## Segurança — checklist

- [ ] **API key forte** (`openssl rand -hex 32`). Nunca reusar a do dev em outra coisa.
- [ ] **HTTPS sempre** (Traefik/Caddy faz o Let's Encrypt). Sem TLS = key vazada na primeira conexão.
- [ ] **Porta 6333 NÃO aberta** crua no firewall — só 80/443 (HTTP/HTTPS). O Qdrant fala na rede interna.
- [ ] A **API key fica fora do Git** (`.env` da VPS, `.zshrc` da sua máquina).
- [ ] Qdrant **não isola por collection** a nível de auth — a key dá acesso a TODAS. Pra isolamento real entre projetos sensíveis, use instâncias separadas.

## Gotchas

- **Claude Code NÃO lê o `.env` do projeto** pra expandir `${QDRANT_API_KEY}` — precisa estar no ambiente do **shell** que abriu o `claude`.
- Depois de mudar o `.mcp.json` ou exportar a key, **reinicie o Claude Code** (ele lê config no boot).
- Se o `/mcp` mostrar `qdrant-memory · failed`: cheque (a) a VPS está no ar (`curl ... /healthz`), (b) `QDRANT_API_KEY` está no env (`echo $QDRANT_API_KEY` no terminal antes de abrir o claude), (c) `QDRANT_URL` no `.mcp.json` é `https://...` (não `http://`).
- **`SSL certificate problem: unable to get local issuer certificate`** — o Traefik está servindo o `TRAEFIK DEFAULT CERT` (auto-assinado) porque **nunca emitiu** o Let's Encrypt pro subdomínio. Acontece quando o router entrou depois do Traefik subir: o ciclo diário só faz `Testing certificate renew...` do que já está no `acme.json`, não pede os que faltam. Labels, DNS e porta 80 podem estar todos certos. Confirme os domínios emitidos e force a reavaliação:

  ```bash
  # domínios que realmente têm cert
  sudo docker exec $(sudo docker ps -q -f name=traefik | head -1) \
    cat /etc/traefik/letsencrypt/acme.json | grep -oE '"main":"[^"]*"'

  # força o Traefik a reavaliar — emite os faltantes em ~20s
  sudo docker service update --force traefik_traefik
  ```

- **Traefik com `--log.filePath` não escreve em stdout** — `docker service logs traefik_traefik` vem **vazio** e parece que não há erro nenhum. O log real está no arquivo dentro do container (`docker exec ... cat /var/log/traefik/traefik.log`).
