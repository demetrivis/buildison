# Referência — Structurizr DSL (cheat sheet)

O Structurizr DSL descreve o modelo C4 uma vez e gera múltiplas views. Estrutura:
`workspace { model {...} views {...} }`. Definam-se elementos no `model`, e escolhe-se o
que renderizar em `views`. Abaixo, o esqueleto mínimo que valida no Structurizr Lite.

```dsl
workspace "Nome do Sistema" "Descrição curta." {

    model {
        // Pessoas
        usuario = person "Usuário" "Quem usa o sistema."

        // Sistemas externos
        gatewayPagto = softwareSystem "Gateway de Pagamento" "Externo." "Externo"

        // O sistema em foco, com seus containers
        sistema = softwareSystem "Sistema X" {
            spa       = container "SPA"        "Interface web."          "React"
            api       = container "API"        "Regras de negócio."      "Node.js"
            worker    = container "Worker"     "Processa jobs async."    "Node.js"
            bd        = container "Banco"      "Estado da aplicação."    "PostgreSQL" "Banco"
            fila      = container "Fila"       "Mensageria."             "RabbitMQ"   "Banco"

            // Componentes (só de containers-chave)
            api -> bd "Lê/escreve" "SQL/TCP"
            api -> fila "Publica eventos" "AMQP"
            worker -> fila "Consome eventos" "AMQP"
            worker -> bd "Atualiza" "SQL/TCP"
            spa -> api "Chama" "JSON/HTTPS"
        }

        // Relações de alto nível
        usuario -> spa "Usa" "HTTPS"
        api -> gatewayPagto "Cobra" "JSON/HTTPS"

        // Ambiente de deployment (mapeia containers -> infra)
        producao = deploymentEnvironment "Produção" {
            deploymentNode "Cloud" {
                deploymentNode "Cluster k8s" {
                    deploymentNode "Pod: api" "" "" {
                        apiInst = containerInstance api
                        instances 3          // réplicas / auto-scaling
                    }
                    deploymentNode "Pod: worker" {
                        containerInstance worker
                    }
                }
                deploymentNode "PostgreSQL gerenciado" {
                    primaria = deploymentNode "Primária" {
                        containerInstance bd
                    }
                    deploymentNode "Réplica de leitura" {
                        containerInstance bd
                    }
                }
            }
        }
    }

    views {
        systemContext sistema "Contexto" { include *; autolayout lr }
        container     sistema "Containers" { include *; autolayout lr }
        // component  api "ComponentesApi" { include *; autolayout lr }  // se houver componentes
        deployment    sistema "Produção" "Deployment" { include *; autolayout lr }

        styles {
            element "Person"   { shape person }
            element "Banco"    { shape cylinder }
            element "Externo"  { background #999999 }
        }
    }
}
```

## Notas
- Identificadores (`api`, `bd`, ...) são referências; mantenha-os únicos.
- Tags (o último string, ex.: `"Banco"`, `"Externo"`) alimentam os `styles`.
- `containerInstance <id>` no deployment **precisa** referenciar um container existente.
- `instances N` e nós aninhados são como você expressa réplicas, réplicas de banco,
  balanceadores e regiões.
- Structurizr Lite lê `workspace.dsl` do diretório e renderiza no navegador; o arquivo é
  versionável junto do código.
