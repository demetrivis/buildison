# Referência — Convenções do Modelo C4

O C4 (Simon Brown) descreve a estrutura do **software** em quatro níveis de zoom. Cada
nível tem um público e um propósito; incluir detalhe demais no nível errado é o erro mais
comum. Esta skill usa os três primeiros níveis + a view de deployment.

## Nível 1 — System Context
- **Público:** qualquer pessoa, inclusive não-técnica.
- **Mostra:** o sistema como uma caixa única, as **pessoas** que o usam e os **sistemas
  externos** com que ele conversa.
- **Omite:** tecnologias, containers, componentes.

## Nível 2 — Container
- **Público:** técnico (devs, arquitetos, ops).
- **Mostra:** as unidades **implantáveis/executáveis** — app web, API, SPA, worker, banco,
  fila, cache — e como se comunicam (protocolo/porta).
- Regra prática: um "container" é algo que roda como processo separado e pode ser
  implantado independentemente. Um banco de dados É um container. Uma classe NÃO é.
- **Omite:** o interior de cada container.

## Nível 3 — Component
- **Público:** desenvolvedores daquele container.
- **Mostra:** os agrupamentos internos de um container por **responsabilidade** (ex.:
  Controller, Serviço de Domínio, Repositório), não arquivos individuais.
- Gere só para 1–2 containers-chave; componentizar tudo é ruído.

## Nível 4 — Code
- Normalmente gerado por ferramenta (diagrama de classes). Esta skill **não** o produz.

## View de Deployment (o foco de infra)
- **Mostra:** o mapeamento dos containers (do nível 2) para a **infraestrutura de runtime**:
  nós de deployment (VM, container Docker, pod k8s, região, servidor de banco) e quais
  **instâncias** de container rodam em cada nó.
- Capture o que os arquivos de infra revelam: réplicas/auto-scaling, réplicas de banco,
  balanceadores, ambientes (dev/staging/prod).
- Se a infra não estiver declarada no repo, **diga isso** — não invente uma topologia.

## Notação
- Setas indicam dependência/fluxo, com rótulo do propósito e da tecnologia
  ("Faz chamadas à API, JSON/HTTPS").
- Deixe cada diagrama legível de forma isolada: título, e legenda quando útil.
