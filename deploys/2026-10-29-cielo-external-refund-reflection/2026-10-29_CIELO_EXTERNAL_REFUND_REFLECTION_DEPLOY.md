# Deploy — reflexo de reembolso externo Cielo

## Objetivo

Publicar o reflexo de um cancelamento ou estorno total iniciado no Portal Cielo para uma venda Lowify já paga. O webhook `ChangeType: 25` continua sendo apenas o gatilho: o Banking V2 consulta a Cielo e só aceita `Payment.Status` `10` ou `11` antes de persistir efeitos financeiros.

O fluxo publicado é:

```text
Cielo -> edge-webhook -> banking-v2:refunds:actions
-> Banking V2 consulta a Cielo e confirma o refund
-> commerce:refunds:actions
-> Commerce V2 cria/confirma sales_refund
-> sales:events:refunded -> efeitos Commerce V2 e Wallet
```

Refund parcial permanece fora de escopo. Um `ChangeType: 25` cuja consulta retorna `Payment.Status: 2` não altera cobrança, refund, extrato ou venda.

## Componentes publicados

| Repositório | Diretório na VPS | Branch de deploy | Commit | Papel nesta entrega |
| --- | --- | --- | --- | --- |
| `services-banking-v2` | `/opt/lowify/services/services-banking-v2` | `feat/cielo-external-refund-reflection` | `91266aa` | Confirma a Cielo, persiste o refund/alocações e publica a ação intermediária. |
| `service-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `feat/cielo-external-refund-reflection` | `a0c0d58` | Consome a ação externa, persiste `sales_refund`, publica o evento final e aciona o extrato já existente via Wallet. |
`edge-webhook` participa do fluxo já existente e não recebe código nesta entrega. O `service-commerce-v2` recebe o novo consumidor de `commerce:refunds:actions` e a migration de unicidade de IDs bancários reais em `sales_refund`.

## Alterações incluídas

- O Banking V2 localiza uma cobrança Cielo por `PaymentId`, valida provider, resolve a venda por `PaymentId` com fallback para `order_id`, cria ou conclui `refunds_charge`, cria/aprova as alocações e registra a mudança da cobrança para `refunded`.
- Para refund externo confirmado, o Banking não publica diretamente `sales:events:refunded`; ele publica `cielo_external_refund_confirmed` em `commerce:refunds:actions` depois da transação bancária.
- O Commerce V2 usa `banking_refund_id` para localizar ou criar o refund local, confirma-o em transação e só então publica `sales:events:refunded`. O extrato é responsabilidade do fluxo Wallet já consumido pelo Commerce V2.
- Reenvios após aprovação não repetem refund, extrato ou evento final.
- O Banking bloqueia a linha de `charges_card` do `PaymentId` durante a transação. Reentregas concorrentes do mesmo refund Cielo são serializadas, sem alterar dados legados de outros providers. A migration do Commerce V2 torna único apenas `banking_refund_id > 0`; o sentinela legado `0` continua repetível.

## Arquivos alterados

### `services-banking-v2`

- `app/Domain/Refund/Repository/RefundChargeRepository.php`
- `app/Domain/RefundAction/Handler/CieloEcommerce/CieloEcommerceRefundActionHandler.php`
- `app/Domain/ChargeCard/Repository/ChargeCardRepository.php`
- `app/Infrastructure/Services/CommerceRefundActionPublisher.php`

### `service-commerce-v2`

- `app/Application/Service/Queue/ReliableRedisQueue.php`
- `app/Application/Service/Queue/SaleRefundedEventPublisher.php`
- `app/Application/UseCase/Sale/ReflectExternalCieloRefundUseCase.php`
- `app/Process/RefundActionsProcess.php`
- `config/autoload/processes.php`
- `config/autoload/refund_actions.php`
- `migrations/20261029190000_add_sales_refund_banking_refund_unique_index.php`

### Documentação de deploy

- `docs/deploys/2026-10-29-cielo-external-refund-reflection/2026-10-29_CIELO_EXTERNAL_REFUND_REFLECTION_DEPLOY.md`
- `docs/deploys/2026-10-29-cielo-external-refund-reflection/sql/lowify/PRECHECK.sql`
- `docs/deploys/2026-10-29-cielo-external-refund-reflection/sql/lowify/DEPLOY.sql`
- `docs/deploys/2026-10-29-cielo-external-refund-reflection/sql/lowify/VALIDATE.sql`

Não há arquivo alterado em `edge-webhook` nem em `dashboard-seller` nesta feature.

## Alteração de banco nova

Executar o [precheck Lowify](sql/lowify/PRECHECK.sql). Ele deve retornar zero duplicidades para IDs bancários reais (`banking_refund_id > 0`) antes de executar a migration do Commerce V2. Valores legados `0` não representam um refund bancário e são excluídos da unicidade.

## Banco de dados

| Banco | Aplicação | Precheck | Validação |
| --- | --- | --- | --- |
| `services-banking` | Não há alteração de schema | — | — |
| `lowify` | migration do Commerce V2 | [PRECHECK.sql](sql/lowify/PRECHECK.sql) | [VALIDATE.sql](sql/lowify/VALIDATE.sql) |

O índice Lowify é aditivo e não deve ser removido no rollback.

## Sequência de deploy

Atualizar o Commerce V2 antes de iniciar o Banking, para que a nova ação intermediária seja consumida pelo processo que cria `sales_refund` externo.

### 1. Atualizar os dois componentes novos

No Banking e no Commerce V2:

```bash
git fetch origin --prune
git switch feat/cielo-external-refund-reflection
git pull --ff-only origin feat/cielo-external-refund-reflection
git rev-parse --short HEAD
```

### 2. Aplicar a migration do Commerce V2

Executar a migration `20261029190000_add_sales_refund_banking_refund_unique_index.php` no Commerce V2, somente se o precheck houver confirmado que não há duplicidades de IDs bancários reais. Ela cria `banking_refund_unique_id`, uma coluna gerada que converte o sentinela `0` em `NULL`, e aplica a chave única nessa coluna. Em seguida, executar o [VALIDATE.sql](sql/lowify/VALIDATE.sql).

### 3. Publicar o Commerce V2

O Commerce V2 deve estar atualizado antes do Banking começar a publicar `commerce:refunds:actions` externas.

```bash
cd /opt/lowify/services/service-commerce-v2
docker compose up -d --build service-commerce-v2
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

Confirmar que `commerce_refund_actions_queue` iniciou e não há erro de banco ou Redis.

### 4. Publicar o Banking V2

```bash
cd /opt/lowify/services/services-banking-v2
docker compose up -d --build services-banking-v2
docker compose ps
docker compose logs --tail=100 services-banking-v2
```

Confirmar que `refund_actions_queue` iniciou sem erro e está ouvindo `banking-v2:refunds:actions`.

## Validação pós-deploy

Usar somente uma venda de homologação conhecida e registrar `PaymentId`, `sale_id`, `refund_charge_id` e horário; não registrar PAN, CVV, tokens ou segredos.

1. Fazer refund total no Portal Cielo e aguardar `ChangeType: 25`.
2. Confirmar em `services-webhook.webhook_raws` que o webhook foi persistido e que a ação alcançou `banking-v2:refunds:actions`.
3. Confirmar que o Banking consultou a Cielo e, para status `10` ou `11`, criou ou concluiu exatamente um `refunds_charge`, criou/aprovou o plano de alocações, atualizou `charges_card.status` para `refunded` e gravou um evento de cobrança com origem `webhook`.
4. Confirmar que há exatamente uma instrução `cielo_external_refund_confirmed` em `commerce:refunds:actions` e que o Commerce V2 criou/atualizou exatamente um `sales_refund` aprovado com o mesmo `banking_refund_id`.
5. Confirmar um único lançamento de extrato tipo `12` e, quando aplicável, um lançamento de taxa tipo `13`; então confirmar que `sales:events:refunded` foi publicado e o Commerce V2 consumiu seus efeitos normais.
6. Reenviar o mesmo callback Cielo duas vezes. Não pode haver duplicação em `refunds_charge`, alocações, evento da cobrança, `sales_refund`, extrato, evento final ou efeitos do Commerce.
7. Fazer um cenário controlado em que a consulta responda status `2` após `ChangeType: 25`. A cobrança deve continuar paga e não pode existir novo refund, extrato ou evento de venda.
8. Verificar logs do Banking e de `commerce_refund_actions_queue`; registrar erro de conciliação, venda ausente, provider incompatível ou falha de fila.

## Rollback

1. Retornar Banking e Commerce V2 às revisões anteriores aprovadas, reconstruindo/reiniciando somente os containers atualizados.
2. Não remover o índice Lowify e não apagar dados financeiros ou mensagens de fila. O rollback só restaura o código.

## Fora de escopo

- Refund parcial Cielo e qualquer caso que permaneça em `Payment.Status: 2`.
- Pix, boleto, outros adquirentes, chargeback e cancelamento de assinatura.
