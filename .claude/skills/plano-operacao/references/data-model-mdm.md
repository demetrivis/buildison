# Referência — Modelo de dados & MDM

## Onde extrair as entidades (em ordem de confiabilidade)
1. **Schema / migrations** — a fonte de verdade real (DDL, arquivos de migration).
2. **Models de ORM** — classes de entidade (SQLAlchemy, Prisma, TypeORM, Eloquent, ActiveRecord, JPA).
3. **DTOs / schemas de API** — pistas quando não há ORM/DDL visível.
Se as três divergirem, confie no schema e registre a divergência como lacuna.

## O que capturar por entidade
- Nome, chave primária, chaves estrangeiras (relacionamentos).
- Cardinalidade (1–1, 1–N, N–N via tabela de junção).
- Atributos que revelem o papel de negócio (não precisa listar todas as colunas).

## Classificação master vs. transacional
Para cada entidade, decida:

| Sinal | Aponta para… |
|---|---|
| Referenciada por muitas outras entidades/módulos | **master data** |
| Plausivelmente existe também no ERP/marketing/suporte | **master data** |
| Muda pouco; representa uma "coisa" do mundo real (pessoa, produto, org) | **master data** |
| Nasce e morre dentro de um fluxo; representa um evento/transação | **transacional** |
| Alto volume, append-only (logs, eventos, itens de pedido) | **transacional** |

Exemplos típicos de CRM/ERP: **master** = Cliente/Conta, Contato, Produto, Fornecedor.
**transacional** = Pedido, Fatura, Oportunidade, Atividade, Log.

## Checklist de MDM (para cada candidato a master)
- **Golden record:** existe (ou deveria existir) uma fonte única de verdade dessa entidade?
- **Duplicação:** há risco de o mesmo "Cliente" existir duplicado entre módulos/sistemas?
- **Chave de correlação:** existe um identificador estável para casar registros entre sistemas
  (documento, e-mail, código externo)?
- **Propriedade:** quem é o dono do dado (este sistema, ou ele só espelha o ERP)?
Registre essas respostas como **recomendações**, não como fatos, quando inferidas.

## Notação do ERD (Mermaid)
Use `erDiagram`. Marque relacionamentos com a notação de pé-de-galinha do Mermaid:
`||--o{` (um-para-muitos), `}o--o{` (muitos-para-muitos), `||--||` (um-para-um).
Destaque master data no texto/legenda (o Mermaid não colore por classe nativamente; use a
tabela de classificação ao lado do diagrama).

## Ligação com o C4
O modelo de dados é **ortogonal** ao C4: o C4 mostra a estrutura do software; o modelo de
dados mostra a estrutura da informação. Amarre-os citando em qual **container** (tipicamente
o banco) cada grupo de entidades reside, e quais containers são donos de quais master data.
