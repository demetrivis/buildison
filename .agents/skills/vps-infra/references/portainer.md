# Portainer — opcional

Fase 6. **Só execute se o usuário quiser.** Pergunte antes; não instale por padrão.

## Decidir: Portainer ou só terminal

| | Com Portainer | Só terminal |
|---|---|---|
| Deploy de stack | Cola o YAML na UI, clica em Deploy | `docker stack deploy -c arquivo.yml nome` |
| Ver logs | Clica no serviço | `docker service logs <nome> --tail 50` |
| Custo | ~100 MB RAM + 1 subdomínio exposto | Zero |
| Superfície de ataque | UI com login exposta na internet | Só o SSH |
| Quando compensa | Você mexe com frequência, ou não é o único operador | Host enxuto, você é o único operador |

**Não é decisão definitiva:** dá pra adicionar depois sem refazer nada, e dá pra remover com um
`docker stack rm portainer` sem afetar os outros stacks.

Num host de 1 vCPU com poucos serviços, o terminal costuma bastar. Se o usuário não tiver preferência clara,
sugira começar sem — e adicionar se sentir falta.

---

## Caminho A — Sem Portainer (só terminal)

Nada a instalar. As operações do dia a dia:

Deployar/atualizar um stack:

```bash
docker stack deploy -c <arquivo>.yml <nome-do-stack>
```

Listar serviços:

```bash
docker service ls
```

Ver logs:

```bash
docker service logs <stack>_<servico> --tail 50 -f
```

Por que uma task não sobe:

```bash
docker service ps <stack>_<servico> --no-trunc
```

Forçar recriação (relê imagem e config):

```bash
docker service update --force <stack>_<servico>
```

Remover um stack:

```bash
docker stack rm <nome-do-stack>
```

> Guarde os `.yml` num repo versionado, não soltos na VPS. Foi o que faltou na wp3: os stacks foram criados
> pela UI e ficaram só no banco do Portainer — não há arquivo no disco para consultar ou versionar.

---

## Caminho B — Com Portainer

Requer o [Traefik](traefik.md) rodando e um subdomínio com DNS apontando pro IP.

Crie `portainer-stack.yml`:

```yaml
version: "3.8"

services:
  agent:
    image: portainer/agent:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - network_public
    deploy:
      mode: global          # um agent por nó
      placement:
        constraints:
          - node.platform.os == linux

  portainer:
    image: portainer/portainer-ce:latest
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data:/data
    networks:
      - network_public
    deploy:
      placement:
        constraints:
          - node.role == manager
      labels:
        - traefik.enable=true
        - traefik.docker.network=network_public
        - traefik.http.routers.portainer.rule=Host(`<SUBDOMINIO>`)
        - traefik.http.routers.portainer.entrypoints=websecure
        - traefik.http.routers.portainer.tls.certresolver=letsencryptresolver
        - traefik.http.routers.portainer.priority=1
        - traefik.http.routers.portainer.service=portainer
        - traefik.http.services.portainer.loadbalancer.server.port=9000

volumes:
  portainer_data:
    external: false

networks:
  network_public:
    external: true
```

Troque `<SUBDOMINIO>`. Depois:

```bash
docker stack deploy -c portainer-stack.yml portainer
```

### ⚠️ Primeiro acesso tem prazo

O Portainer só deixa criar o usuário admin nos **primeiros minutos** após subir. Passou disso, ele trava com
*"instance timed out for security purposes"* e a única saída é reiniciar o serviço:

```bash
docker service update --force portainer_portainer
```

Acesse `https://<SUBDOMINIO>` **logo após o deploy** e crie o admin com senha forte.

### Verificação

```bash
docker service ls --filter name=portainer
```

`portainer_portainer` em `1/1` e `portainer_agent` em `1/1` (global, 1 por nó).

Se o HTTPS não subir, o problema é do Traefik, não do Portainer — veja o
[diagnóstico de certificado](traefik.md#diagnóstico-traefik-default-cert). Lembre que o router do Portainer
foi criado **depois** do Traefik, que é exatamente o caso que exige o `--force`.

### Notas

- **`priority=1`** deixa o router do Portainer com prioridade baixa, para não capturar requests de outros
  serviços caso alguma regra seja ampla demais.
- **`traefik.docker.network`** é necessário quando o serviço está em mais de uma rede — sem ela o Traefik pode
  escolher a errada e o backend fica inalcançável.
- O agent monta o socket do Docker: quem tem acesso ao Portainer tem, na prática, **root no host**. Senha
  forte, e considere restringir por IP no Traefik se for host sensível.
