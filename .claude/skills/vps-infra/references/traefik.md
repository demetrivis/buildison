# Traefik — reverse proxy com HTTPS automático

Fase 5. Requer o [bootstrap](bootstrap.md) completo: Swarm ativo, `network_public` criada, portas 80/443
abertas e **verificadas de fora**.

## Antes: o DNS precisa existir

O Let's Encrypt valida por HTTP-01 — ele acessa `http://<dominio>/.well-known/acme-challenge/...`. Sem DNS
apontando pro IP, não há certificado.

Crie um registro **A** para cada subdomínio → IP da VPS, e confirme a propagação:

```bash
dig +short <dominio>
```

Tem que devolver o IP da VPS. Se vier vazio ou outro IP, **espere** — subir o Traefik antes só gera falha de
challenge e consome cota do Let's Encrypt (5 falhas/hora por domínio).

### ⚠️ Cloudflare: comece com a nuvem CINZA

Se o domínio está na Cloudflare, o registro A tem um toggle de proxy. **Deixe cinza (DNS only)** para emitir o
certificado.

| Estado | O que acontece |
|---|---|
| 🔘 **Cinza (DNS only)** | O tráfego vai direto pra VPS. O Traefik emite e serve o cert dele. É o que você quer. |
| 🟠 **Laranja (Proxied)** | A Cloudflare termina o TLS e serve o **cert dela**. O do Traefik fica invisível pro visitante. |

Como saber em qual está: o `dig +short <dominio>` devolve o **IP da sua VPS** se for cinza, e um IP da
Cloudflare (`104.x`, `172.67.x`) se for laranja.

Se depois quiser ligar o laranja (DDoS, cache, esconder o IP), **antes** vá em SSL/TLS → Overview e ponha em
**Full (strict)**. No modo *Flexible* a Cloudflare fala HTTP com a origem enquanto o Traefik redireciona pra
HTTPS — resultado é loop de redirecionamento infinito, e o sintoma (`ERR_TOO_MANY_REDIRECTS`) não aponta pra
causa.

---

## Apontar um domínio novo pra um serviço

O fluxo completo, do zero ao HTTPS:

**1.** Crie o registro **A**: `<sub>.<dominio>` → IP da VPS, nuvem **cinza**.

**2.** Confirme que propagou (pode levar de segundos a minutos):

```bash
dig +short <sub>.<dominio>
```

**3.** Adicione as labels ao serviço (veja [Expondo um serviço](#expondo-um-serviço) abaixo) e deployе:

```bash
docker stack deploy -c <arquivo>.yml <stack>
```

**4.** Se o Traefik já estava rodando, **force a reavaliação** — ele não pede cert pra router novo sozinho:

```bash
sudo docker service update --force traefik_traefik
```

**5.** Valide de fora, sem `-k`:

```bash
echo | openssl s_client -connect <sub>.<dominio>:443 -servername <sub>.<dominio> 2>/dev/null | grep issuer
```

O passo 4 é o que mais se esquece — e é justamente o que não dá erro.

## O stack

Crie `traefik-stack.yml` na VPS:

```yaml
version: "3.8"

services:
  traefik:
    # Pin no MINOR, não no patch: pega correção de segurança sem salto de minor
    # surpresa. Confira o atual antes de instalar — esta linha envelhece:
    #   curl -s https://api.github.com/repos/traefik/traefik/releases/latest | grep tag_name
    image: traefik:v3.7
    command:
      - --api.dashboard=true
      # ⚠️ providers.SWARM — não providers.docker. Em Swarm, o provider `docker`
      # não descobre services; o Traefik sobe e não roteia nada.
      - --providers.swarm=true
      - --providers.swarm.endpoint=unix:///var/run/docker.sock
      - --providers.swarm.exposedByDefault=false
      - --providers.swarm.network=network_public
      - --entrypoints.web.address=:80
      - --entrypoints.web.http.redirections.entryPoint.to=websecure
      - --entrypoints.web.http.redirections.entryPoint.scheme=https
      - --entrypoints.web.http.redirections.entrypoint.permanent=true
      - --entrypoints.websecure.address=:443
      - --certificatesresolvers.letsencryptresolver.acme.httpchallenge=true
      - --certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web
      - --certificatesresolvers.letsencryptresolver.acme.email=SEU@EMAIL.com
      - --certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json
      - --log.level=INFO
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - volume_swarm_certificates:/etc/traefik/letsencrypt
    networks:
      - network_public
    ports:
      # mode: host preserva o IP real do cliente nos logs (com o ingress mesh,
      # tudo chega como IP interno do Swarm)
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host
    deploy:
      placement:
        constraints:
          - node.role == manager
      # ⚠️ SEM router "http-catchall". As flags --entrypoints.web.http.redirections.*
      # acima já redirecionam 80 -> 443 no nível do entrypoint; um catchall só
      # duplica isso e ainda obriga a acertar o namespace do middleware
      # (com o provider swarm é @swarm, não @docker — errar não dá erro, só
      # não aplica). Verificado: sem catchall, http:// devolve 301 normalmente.

volumes:
  volume_swarm_certificates:
    external: false

networks:
  network_public:
    external: true
```

Troque `SEU@EMAIL.com`. Depois:

```bash
docker stack deploy -c traefik-stack.yml traefik
```

### Verificação

```bash
docker service ls --filter name=traefik
```

Tem que estar `1/1`. Se ficar `0/1`, veja o porquê:

```bash
docker service ps traefik_traefik --no-trunc
```

## Expondo um serviço

Qualquer serviço entra no HTTPS com **quatro labels** e presença na `network_public`:

```yaml
    networks:
      - network_public
    deploy:
      labels:
        - traefik.enable=true
        - traefik.http.routers.<nome>.rule=Host(`<dominio>`)
        - traefik.http.routers.<nome>.entrypoints=websecure
        - traefik.http.routers.<nome>.tls.certresolver=letsencryptresolver
        - traefik.http.services.<nome>.loadbalancer.server.port=<porta_interna>
```

> ⚠️ Em Swarm as labels vão em **`deploy.labels`** (do service), não em `labels` (do container). Label no
> lugar errado = o Traefik não enxerga, sem erro nenhum.
>
> `<porta_interna>` é a porta que o processo escuta **dentro** do container — não precisa publicar nada.

## Verificação final — de fora, sem `-k`

```bash
echo | openssl s_client -connect <dominio>:443 -servername <dominio> 2>/dev/null | grep -E '^(subject|issuer)'
```

Esperado:

```
subject=/CN=<dominio>
issuer=/C=US/O=Let's Encrypt/CN=...
```

Se o `issuer` for `TRAEFIK DEFAULT CERT`, o certificado não foi emitido — siga abaixo.

---

## Diagnóstico: `TRAEFIK DEFAULT CERT`

Sintoma no cliente: `SSL certificate problem: unable to get local issuer certificate`.

### 1. Quais domínios têm certificado de fato

```bash
sudo docker exec $(sudo docker ps -q -f name=traefik | head -1) cat /etc/traefik/letsencrypt/acme.json | grep -oE '"main":"[^"]*"'
```

Se o seu domínio **não** está na lista, o Traefik nunca emitiu.

### 2. ⚠️ Router criado depois do Traefik subir

**A causa mais comum, e a que não dá erro.** O Traefik pede certificado para os routers que conhece no momento
em que monta a config TLS. Um serviço publicado depois pode nunca receber cert — e o log só mostra o ciclo
diário `Testing certificate renew...` dos que já existem.

Se as labels estão certas, o DNS resolve, a porta 80 responde e **mesmo assim** não há cert, force:

```bash
sudo docker service update --force traefik_traefik
```

O cert costuma sair em ~20 segundos. Reverifique com o `openssl` acima.

### 3. ⚠️ O log pode estar indo pra arquivo

Se o Traefik roda com `--log.filePath`, o `docker service logs` vem **vazio** — parece que não há erro, mas o
log está dentro do container:

```bash
sudo docker exec $(sudo docker ps -q -f name=traefik | head -1) tail -50 /var/log/traefik/traefik.log
```

O stack acima não usa `--log.filePath` justamente por isso: com stdout, `docker service logs` funciona.

### 4. Erros de ACME

```bash
sudo docker service logs traefik_traefik --tail 200 2>&1 | grep -iE 'acme|challenge|error'
```

| Mensagem | Causa |
|---|---|
| `timeout during connect` | Porta 80 fechada — volte pra [Fase 1](bootstrap.md#fase-1--firewall-do-provedor-antes-de-tudo) |
| `DNS problem: NXDOMAIN` | DNS não aponta pro IP, ou ainda propagando |
| `too many certificates already issued` | Cota do Let's Encrypt (5/semana por domínio). Espere ou use outro subdomínio |
| *(nenhuma linha)* | O Traefik não está tentando → item 2 acima |

### 5. Recomeçar do zero (último recurso)

Apaga **todos** os certificados e força reemissão. Cuidado com a cota.

```bash
docker service rm traefik_traefik && docker volume rm traefik_volume_swarm_certificates
```

Depois redeploye o stack.

---

## Manutenção

Ver o que está roteado:

```bash
docker service logs traefik_traefik --tail 50 2>&1 | grep -i "configuration received" | tail -1
```

Renovação é automática (o Traefik checa 1×/dia e renova ~30 dias antes de expirar). O que **não** é automático
é emitir cert para router novo — veja o item 2.

> **Backup:** o `volume_swarm_certificates` guarda as chaves privadas. Perdê-lo significa reemitir tudo — e a
> cota do Let's Encrypt é de 5 certificados por domínio por semana.
