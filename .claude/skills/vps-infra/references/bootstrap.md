# Bootstrap — Ubuntu → Docker → Swarm

Fases 1 a 4. Rode por SSH. Cada bloco tem verificação; **não avance com a anterior quebrada**.

## Fase 1 — Firewall do provedor (antes de tudo)

Faça isto **primeiro**. Subir o Traefik com as portas fechadas gera um certificado inválido que fica em cache e
confunde o diagnóstico depois.

### Oracle Cloud

São **dois** bloqueios independentes — abrir num só não resolve.

**a) VCN Security List** (console web): Networking → Virtual Cloud Networks → sua VCN → Security Lists →
Default Security List → Add Ingress Rules.

| Source CIDR | Protocolo | Porta |
|---|---|---|
| `0.0.0.0/0` | TCP | 80 |
| `0.0.0.0/0` | TCP | 443 |

**b) iptables da instância** — a imagem Ubuntu da Oracle vem com `REJECT all` no fim da chain INPUT:

```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
```

```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
```

Persista (senão some no reboot):

```bash
sudo netfilter-persistent save
```

> Se o `netfilter-persistent` não existir: `sudo apt install -y iptables-persistent` (ele pergunta se quer
> salvar as regras atuais — diga sim).

### Hetzner / DigitalOcean / Vultr

Costumam vir com tudo aberto e sem iptables restritivo. Se usar `ufw`:

```bash
sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
```

### Verificação — obrigatória, e **de fora** da VPS

```bash
nc -z -G 5 <IP> 80 && echo "80 aberto" || echo "80 FECHADO"
```

Rode isso da sua máquina, não da VPS. De dentro sempre parece aberto.

---

## Fase 2 — Ubuntu

```bash
sudo apt update && sudo apt upgrade -y
```

Hostname legível (aparece no prompt e nos logs):

```bash
sudo hostnamectl set-hostname <nome-do-host>
```

Timezone (deixa os logs em horário local):

```bash
sudo timedatectl set-timezone America/Sao_Paulo
```

> **Reboot** se o upgrade tocou no kernel (`ls /var/run/reboot-required`). Faça agora, não depois de subir os
> serviços.

### Swap — se a VPS tiver pouca RAM

Instância de 1 vCPU / ~6 GB aguenta o stack, mas builds e o Qdrant podem espremer. Swap de 2 GB é barato:

```bash
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile
```

Persistir:

```bash
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

## Fase 3 — Docker (repo oficial)

Não use o `docker.io` do Ubuntu — é antigo e não traz o plugin `compose` v2.

```bash
curl -fsSL https://get.docker.com | sudo sh
```

> O `get.docker.com` configura o repo oficial e instala `docker-ce`, `docker-ce-cli`, `containerd.io` e os
> plugins `compose`/`buildx`. Funciona em **amd64 e arm64** — não precisa de nada especial em Ampere/Graviton.

Rodar docker sem `sudo`:

```bash
sudo usermod -aG docker $USER && newgrp docker
```

### Verificação

```bash
docker --version && docker compose version && docker run --rm hello-world
```

---

## Fase 4 — Swarm + redes overlay

### ⚠️ `--advertise-addr` é obrigatório em cloud

Em Oracle/AWS/GCP a instância **não conhece o próprio IP público** — o `hostname -I` mostra só o privado
(`10.0.0.5`). Sem o flag, o Swarm anuncia o IP errado. No nó único parece funcionar, e o problema só aparece
quando você tenta juntar um segundo nó.

```bash
sudo docker swarm init --advertise-addr <IP_PUBLICO>
```

Confira o que ficou anunciado:

```bash
docker info | grep -A2 "Manager Addresses"
```

Tem que mostrar `<IP_PUBLICO>:2377`. Se mostrar o privado, refaça:

```bash
docker swarm leave --force
```

### Redes overlay

Duas redes, com papéis distintos:

```bash
docker network create --driver=overlay --attachable network_public
```

```bash
docker network create --driver=overlay --attachable network_dev_data
```

| Rede | Papel |
|---|---|
| `network_public` | Onde o Traefik enxerga os serviços. Só entra aqui o que é para ser exposto. |
| `network_dev_data` | Interna — Postgres, Redis, Qdrant. O Traefik **não** participa dela. |

O `--attachable` permite anexar containers avulsos (`docker run --network`), útil para debug.

> Um serviço de banco fica **nas duas** só se precisar ser exposto por HTTPS (é o caso do Qdrant). O padrão é
> ficar só na `network_dev_data`.

### Verificação

```bash
docker network ls --filter driver=overlay
```

Deve listar `ingress`, `network_public` e `network_dev_data`.

---

## Estado esperado ao fim do bootstrap

```bash
docker info | grep -iE "Swarm:|Managers:|Nodes:" && docker network ls --filter driver=overlay
```

- Swarm: `active`, 1 manager, 1 node
- Três redes overlay
- Portas 80/443 abertas e verificadas **de fora**

Só então vá para [`traefik.md`](traefik.md).
