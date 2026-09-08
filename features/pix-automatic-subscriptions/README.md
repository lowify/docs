# Feature — assinaturas PIX Automático

> Status: em evolução
> Última atualização: 2026-09-08
> Confiança: parcialmente confirmada no código; pendente de homologação

## Objetivo

Criar uma assinatura vinculada a uma venda com pagamento `pix_automatic` e compensar cada cobrança confirmada: ativar a primeira venda, registrar recorrências, avançar validade e executar os efeitos de venda paga.

Este mapa descreve o fluxo confirmado no código das branches de implementação. A migração ainda não foi homologada nem liberada para produção.

## Fluxo implementado para corte

```text
Checkout Commerce V2
  -> Banking cria/processa assinatura no provedor
  -> Banking persiste cobrança e publica sales:subscriptions:actions
  -> Commerce V2: SubscriptionActionsProcess
  -> parcela, vigência e venda original/recorrente
  -> ProcessPaidSaleEventUseCase e efeitos internos do Commerce V2
```

## Componentes e responsabilidades

| Componente | Responsabilidade | Entrada/saída relevante |
| --- | --- | --- |
| `services-commerce-v2` | Cria venda/assinatura PIX Automático no checkout. | `sales.subscription_id`, `subscriptions.correlation_id` |
| `services-banking` | Processa instruções do provedor, persiste status/cobrança e publica os eventos V2. | `sales:subscriptions:actions` |
| `services-commerce-v2` | Consome eventos, registra parcelas, atualiza vigência, prepara a venda e dispara o fluxo interno de venda paga. | `subscriptions_installments`, `ProcessPaidSaleEventUseCase` |
| `services-commerce` | Continua responsável somente pelo estoque já existente do fluxo legado. | `commerce:subscriptions:actions` |
| `dashboard-seller` | Não participa de eventos novos deste fluxo; o worker legado permanece fora do escopo. | `commerce:sales:actions` |

## Contratos e autorização

O checkout V2 permite `pix_automatic` para produtos `SUBSCRIPTION` e chama o Banking para criar a assinatura. O contrato assíncrono novo é um evento por JSON: `event_id`, `event`, `occurred_at` e seus campos de domínio. Para cobrança paga, `event=subscription.charge.paid` contém `correlation_id`, `installment_number`, `end_to_end_id` e `paid_at`; para status, `event=subscription.status.updated` contém `correlation_id` e `status`.

Não há endpoint público novo neste fluxo de compensação; a integração relevante é assíncrona via Redis.

## Dados e processamento assíncrono

- A primeira cobrança paga registra parcela e aciona o fluxo de venda paga da venda original.
- Cobranças posteriores atualizam `valid_until`, clonam/localizam uma venda com identificador derivado do E2E e acionam o fluxo de venda paga dela.
- O publicador Banking só publica a cobrança quando há uma mudança relevante de status. A parcela é buscada por assinatura + número de parcela antes da criação, mas a implementação ainda precisa de validação integrada de todas as reentregas e efeitos posteriores.
- `SubscriptionActionsProcess` consome uma Redis list com `BLPOP`. Uma exceção após a retirada apenas é registrada em log: não há retry ou DLQ implementados.

## Operação e validação

O teste de homologação legado registrado em `docs/deploys/2026-08-31-pix-automatic-commerce-queue-homologation/` valida o caminho Banking -> Commerce legado. A preparação do corte V2 e seu roteiro de compatibilidade estão em [deploy da migração](../../deploys/2026-09-08-pix-automatic-commerce-v2/2026-09-08_PIX_AUTOMATIC_COMMERCE_V2_DEPLOY.md).

## Limitações e pendências

- A estratégia de retry/DLQ prevista no [plano de migração](../../plans/pix-automatic-commerce-v2/README.md) não está implementada; esse é um bloqueio de decisão para produção.
- Após o corte, a fila `commerce:subscriptions:actions` não deve receber novas publicações. Seu estoque e sua desativação ficam fora do escopo desta migração.
- As branches de implementação ainda precisam ser publicadas no remoto e homologadas antes de qualquer deploy.

## Referências

- `services-commerce-v2/app/Application/UseCase/Product/ProcessProductCheckoutUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/CreateSaleUseCase.php`
- `services-banking/src/Queue/SubscriptionActionProcessor.php`
- `services-commerce/src/Application/Service/Subscription/SubscriptionActionsService.php`
- `services-commerce/src/Application/Service/Subscription/SalePaymentApprovedService.php`
- `dashboard-seller/scripts/queues/commerce_sales_actions_worker.php`
