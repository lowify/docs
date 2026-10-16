# Deploy — Resumo do extrato de comunicações

> Status: preparação local. Não iniciar o deploy enquanto as alterações dos quatro repositórios não tiverem commits aprovados e os hashes forem registrados nesta seção.

## Objetivo

Publicar quatro cards no **Extrato de comunicações** do Dashboard Seller: investimento em comunicação, vendas comunicadas, eficiência por venda e recuperação de vendas. A listagem continua sendo carregada imediatamente; o resumo é consultado em paralelo e permanece em skeleton até receber resposta.

Os cards respeitam os filtros atuais de tipo, canal, status e período. A operação não envia mensagens, não cria cobranças, não altera créditos, não consome filas e não expõe dados de destinatários.

## Componentes e referências

| Repositório | Branch de deploy | Commit |
| --- | --- | --- |
| `services-commerce-v2` | `feat/service-monitoring-checkout-preview` | pendente de aprovação/commit |
| `edge-public-api` | `feat/service-monitoring-checkout-preview` | pendente de aprovação/commit |
| `edge-gateway` | `feat/service-monitoring-checkout-preview` | pendente de aprovação/commit |
| `dashboard-seller` | `feat/service-monitoring-checkout-preview` | pendente de aprovação/commit |

Não há alteração em Wallet, Notification, Account, Webhook, Redis ou infraestrutura. O Commerce V2 consulta somente dados já persistidos em `sales`, `sales_delivery` e `sale_recovery_dispatches`.

## Alterações incluídas

- Dashboard Seller renderiza os cards com `StatCard`/`StatCardGrid` e skeleton. A paginação atualiza apenas a tabela; uma nova filtragem também atualiza os cards.
- Dashboard chama `GET /sale-notifications/summary` pelo caminho autenticado `dashboard-seller → edge-gateway → edge-public-api → services-commerce-v2`.
- O Public API extrai a identidade no JWT e preserva a autorização do extrato, inclusive para colaboradores. O identificador do vendedor não é aceito do navegador.
- Commerce V2 calcula gasto somente para registros com `funding_status = consumed`; vendas comunicadas excluem itens somente agendados, cancelados ou ignorados.
- A recuperação considera dispatches enviados (`sent`, `sent_to_provider` ou `confirmed`) e vendas pagas após o horário de criação do dispatch. A métrica financeira é **receita recuperada**, não lucro líquido.

## Pré-requisitos

1. Os quatro repositórios precisam ter commits aprovados na branch declarada acima. Atualizar esta documentação com os hashes antes da execução.
2. Confirmar que o operador possui acesso ao banco usado pelo `services-commerce-v2` e que a conta usada para o SQL tem permissão para `ALTER TABLE`.
3. Confirmar que os containers atuais estão saudáveis antes de começar. Não executar migration automática: o ajuste de banco desta entrega é exclusivamente manual.

## Ajuste de banco manual

Executar o arquivo [DEPLOY.sql](sql/commerce-v2/DEPLOY.sql) **uma única vez** no banco do Commerce V2. Ele adiciona índices para consultas de resumo por proprietário e período; não cria nem modifica dados de vendas, dispatches, créditos ou comunicações.

Antes de executar, conferir se os índices ainda não existem:

```sql
SELECT TABLE_NAME, INDEX_NAME, COLUMN_NAME, SEQ_IN_INDEX
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
  AND INDEX_NAME IN ('idx_sales_delivery_owner_created', 'idx_sale_recovery_owner_created')
ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX;
```

Resultado esperado antes da primeira execução: zero linhas. Se qualquer índice já existir, não executar novamente a respectiva instrução; registrar o estado e validar se a composição de colunas é a mesma do arquivo SQL.

Após a execução, repetir a consulta. Resultado esperado: cada índice listado com três colunas, na ordem `owner_user_id`, `created_at`, `id`.

## Sequência de deploy

Os diretórios abaixo seguem o padrão do servidor principal. Confirmar host, diretório e remoto antes da execução. Eles não são caminhos de homologação.

### 1. Aplicar os índices manualmente no banco do Commerce V2

1. Abrir uma sessão no banco de dados do `services-commerce-v2` usando o acesso operacional aprovado.
2. Conferir o precheck da seção anterior.
3. Executar, uma única vez, o conteúdo de `sql/commerce-v2/DEPLOY.sql`.
4. Repetir a consulta de validação e confirmar os dois índices.

Não executar `php bin/hyperf.php migrate`, `migrate --force` ou qualquer outro comando de migration nesta entrega.

### 2. `services-commerce-v2`

```bash
cd /opt/lowify/services/services-commerce-v2
git fetch origin --prune
git switch feat/service-monitoring-checkout-preview
git pull --ff-only origin feat/service-monitoring-checkout-preview
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=80 service-commerce-v2
```

Resultado esperado: container saudável e rota interna `GET /sale-notifications/summary` disponível para o Public API.

### 3. `edge-public-api`

```bash
cd /opt/lowify/edge/edge-public-api
git fetch origin --prune
git switch feat/service-monitoring-checkout-preview
git pull --ff-only origin feat/service-monitoring-checkout-preview
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=80 edge-public-api
```

Resultado esperado: container saudável e rota autenticada `GET /sale-notifications/summary` encaminhando o contexto do JWT ao Commerce V2.

### 4. `edge-gateway`

```bash
cd /opt/lowify/edge/edge-gateway
git fetch origin --prune
git switch feat/service-monitoring-checkout-preview
git pull --ff-only origin feat/service-monitoring-checkout-preview
git rev-parse --short HEAD
docker compose up -d --build
docker compose ps
docker compose logs --tail=80 edge-gateway
```

Resultado esperado: container saudável e a rota do resumo encaminhada ao Public API.

### 5. `dashboard-seller`

```bash
cd /opt/lowify/front/dashboard-seller
git fetch origin --prune
git switch feat/service-monitoring-checkout-preview
git pull --ff-only origin feat/service-monitoring-checkout-preview
git rev-parse --short HEAD
docker compose ps
```

O compose do Dashboard monta o diretório do repositório no container. Para esta entrega, não é necessário rebuild ou restart após a atualização por Git.

Resultado esperado: Dashboard Seller saudável, com os quatro cards em skeleton na abertura do extrato e valores após a resposta do resumo.

## Validação pós-deploy

1. Faça login no Dashboard Seller com uma conta que possua comunicações de entrega ou recuperação.
2. Abra **Créditos de comunicação → Extrato**. Confirme que a tabela começa a carregar sem esperar pelos cards e que os cards exibem skeleton enquanto o resumo é consultado.
3. Confirme que aparecem os quatro cards: **Investimento em comunicação**, **Vendas comunicadas**, **Eficiência por venda** e **Recuperação de vendas**.
4. Filtre por período, canal e tipo. Confirme que a tabela e os cards refletem a mesma seleção.
5. Vá para a próxima página da tabela. Confirme que somente a tabela é atualizada; os valores dos cards permanecem visíveis.
6. Para um período sem comunicação, confirme valores zerados e `—` nos custos sem divisor, sem erro na tela.
7. Se um card não carregar, confirme que a tabela ainda continua utilizável. Registre o horário, usuário de teste e filtros usados; não limpe filas, Redis ou dados para forçar resultado.

## Rollback

1. Reverter `dashboard-seller` à referência aprovada anterior e reconstruir o container.
2. Reverter `edge-gateway`, depois `edge-public-api`, reconstruindo cada container.
3. Reverter `services-commerce-v2` por último e reconstruir o container. Essa ordem evita que o Dashboard chame uma rota removida enquanto os edges ainda a expõem.
4. Não remover os índices criados pelo SQL durante o rollback normal: eles são compatíveis com o código anterior e não alteram dados. Qualquer remoção de índice deve ser uma operação separada, aprovada e executada apenas após análise de desempenho.

