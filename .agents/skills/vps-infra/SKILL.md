---
name: vps-infra
description: "Provisiona uma VPS do zero com o stack padrão: Ubuntu atualizado, Docker, Swarm inicializado, redes overlay, Traefik com HTTPS automático (Let's Encrypt) e Portainer opcional. Use quando o usuário criar uma VPS nova (Oracle Cloud, Hetzner, DigitalOcean...) e pedir 'sobe a infra padrão', 'setup inicial da VPS', 'instala docker e swarm', 'coloca o traefik', ou quando precisar de um reverse proxy com certificado automático num servidor novo. É o par remoto da skill local-infra."
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# VPS Infra — Ubuntu + Docker Swarm + Traefik

Receita para transformar uma VPS Ubuntu recém-criada no host padrão: Docker Swarm de nó único, rede overlay
pública, Traefik como reverse proxy com HTTPS automático, e Portainer opcional.

**Derivada de uma instalação em produção** (Oracle Cloud Ampere, Ubuntu 22.04, Docker 28.5, Traefik v3.4) — não
de teoria. Os detalhes que só aparecem na prática estão marcados como ⚠️.

> **Par local:** a skill `local-infra` faz o equivalente na máquina de desenvolvimento (Docker Desktop). Esta
> aqui é para servidor remoto.

## Antes de começar — pergunte ao usuário

Não assuma. Colete:

1. **IP e usuário SSH** — e qual chave (`~/.ssh/<nome>`). Confirme que conecta antes de qualquer coisa.
2. **Domínio** — o Traefik só emite certificado se houver DNS apontando pro IP. Sem domínio, pule o HTTPS e
   exponha por porta.
3. **E-mail do Let's Encrypt** — vai nos avisos de expiração.
4. **Portainer, sim ou não?** Pergunte explicitamente:
   - **Com Portainer** — UI web pra gerenciar stacks, logs e containers. Custa ~100 MB de RAM e mais um
     subdomínio exposto. Bom se você vai mexer com frequência ou não é o único a administrar.
   - **Só terminal** — nada além do Traefik. Stacks via `docker stack deploy` por SSH. Menos superfície
     exposta, menos RAM. Bom pra host enxuto ou quando você é o único operador.

   Não há caminho errado — o Portainer é adicionável depois sem refazer nada. Se o usuário não tiver
   preferência, sugira **só terminal** num host de 1 vCPU e **com Portainer** se ele mencionou que quer ver
   as coisas pela web.
5. **Provedor** — muda o passo de firewall (veja ⚠️ Oracle abaixo).

## Fases

Execute em ordem. Cada fase tem verificação — **não avance com a anterior quebrada**.

| # | Fase | Referência |
|---|---|---|
| 1 | Firewall do provedor (antes de tudo) | [`references/bootstrap.md`](references/bootstrap.md) |
| 2 | Ubuntu: update, hostname, timezone | [`references/bootstrap.md`](references/bootstrap.md) |
| 3 | Docker (repo oficial) | [`references/bootstrap.md`](references/bootstrap.md) |
| 4 | Swarm init + redes overlay | [`references/bootstrap.md`](references/bootstrap.md) |
| 5 | Traefik + HTTPS | [`references/traefik.md`](references/traefik.md) |
| 6 | Portainer *(se o usuário quiser)* | [`references/portainer.md`](references/portainer.md) |

## ⚠️ Os três erros que custam horas

Estes não dão erro claro — eles falham em silêncio ou com mensagem enganosa.

### 1. Portas 80/443 fechadas no provedor

Na **Oracle Cloud** a instância nasce com **só a 22 aberta**, em dois lugares independentes:

- **VCN → Security List / NSG** (console web) — precisa de regra de ingress para 80 e 443.
- **iptables da instância** — a imagem Ubuntu da Oracle vem com `REJECT all` no final da chain INPUT.

Abrir num só não basta. Verifique de fora **antes** de subir o Traefik:

```bash
nc -z -G 5 <IP> 80 && echo aberto || echo FECHADO
```

Se estiver fechado, o Let's Encrypt falha no challenge HTTP-01 e o Traefik serve o `TRAEFIK DEFAULT CERT`
— e a mensagem que você vê no cliente é `SSL certificate problem: unable to get local issuer certificate`,
que não diz nada sobre firewall.

### 2. `swarm init` sem `--advertise-addr`

Em cloud com IP flutuante (Oracle, AWS, GCP) a instância **não conhece o próprio IP público**. O `hostname -I`
devolve só o privado (`10.0.0.5`). Sem `--advertise-addr`, o Swarm anuncia o IP errado — funciona no nó único,
mas quebra ao adicionar o segundo nó, e aí você já esqueceu que foi isso.

Sempre explícito:

```bash
sudo docker swarm init --advertise-addr <IP_PUBLICO>
```

### 3. Traefik não pede certificado para router criado depois

O Traefik só solicita certificado para routers que ele conhece **no momento em que constrói a config TLS**. Um
serviço publicado depois, com labels corretas, pode nunca receber cert — e o log só mostra o
`Testing certificate renew...` diário dos que já existem, sem nenhum erro.

Sintoma: labels certas, DNS certo, porta 80 aberta, e mesmo assim `TRAEFIK DEFAULT CERT`.

Correção: forçar reavaliação.

```bash
sudo docker service update --force traefik_traefik
```

Detalhes e diagnóstico em [`references/traefik.md`](references/traefik.md).

## Convenções do stack padrão

Mantenha estes nomes — o `/portainer` e os stacks de aplicação dependem deles.

| Recurso | Nome | Por quê |
|---|---|---|
| Rede pública | `network_public` | Onde o Traefik enxerga os serviços. Overlay, `--attachable`. |
| Rede de dados | `network_dev_data` | Interna, para banco/cache. **Não** exposta ao Traefik. |
| Volume de certs | `volume_swarm_certificates` | Monta em `/etc/traefik/letsencrypt`. Perdê-lo = reemitir tudo. |
| Cert resolver | `letsencryptresolver` | Nome referenciado pelas labels de todo serviço. |
| Entrypoints | `web` (80) e `websecure` (443) | `web` redireciona pra `websecure`. |

Um serviço só é exposto se tiver `traefik.enable=true` — o Traefik roda com `exposedByDefault=false`.

## Ao terminar

1. Valide o HTTPS de fora, **sem** `-k`:

   ```bash
   echo | openssl s_client -connect <dominio>:443 -servername <dominio> 2>/dev/null | grep -E '^(subject|issuer)'
   ```

   O `issuer` tem que ser Let's Encrypt. Se for `TRAEFIK DEFAULT CERT`, veja os três erros acima.

2. Registre em `docs/agent/decisions.md`: IP, domínio, o que foi instalado e se tem Portainer.
3. Se a VPS for hospedar a memória vetorial dos agentes, siga
   [`docs/infra/qdrant-vps-template.md`](../../../docs/infra/qdrant-vps-template.md) para o Qdrant.

> ⚠️ **Nunca** commite IP, chave SSH ou senha num arquivo versionado. O doc real da sua VPS vai gitignored —
> veja como o `docs/infra/qdrant-vps-setup.md` é tratado.
