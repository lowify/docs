# Feature — assinaturas PIX Automático

> Status: em evolução
> Última atualização: 2026-09-04
> Confiança: parcialmente confirmada

## Objetivo

Criar uma assinatura vinculada a uma venda com pagamento `pix_automatic` e compensar cada cobrança confirmada: ativar a primeira venda, registrar recorrências, avançar validade e executar os efeitos de venda paga.

Este mapa descreve o fluxo confirmado no código existente. A migração do consumidor para Commerce V2 está planejada, ainda não implementada.

## Fluxo principal atual

```text
Checkout Commerce V2
  -> Banking cria/processa assinatura no provedor
  -> Banking persiste cobrança e publica commerce:subscriptions:actions
  -> worker Commerce legado registra parcela/ativa ou clona venda
  -> commerce:sales:actions
  -> worker dashboard-seller executa compensação de venda
```

## Componentes e responsabilidades

| Componente | Responsabilidade | Entrada/saída relevante |
| --- | --- | --- |
| `services-commerce-v2` | Cria venda/assinatura PIX Automático no checkout. | `sales.subscription_id`, `subscriptions.correlation_id` |
| `services-banking` | Processa instruções do provedor, persiste status/cobrança e publica para Commerce legado. | `commerce:subscriptions:actions` |
| `services-commerce` | Consome instruções de assinatura/cobrança, registra parcelas e prepara aprovação. | `subscriptions_installments`, `commerce:sales:actions` |
| `dashboard-seller` | Consome ações de venda legadas. | `commerce:sales:actions` |

## Contratos e autorização

O checkout V2 permite `pix_automatic` para produtos `SUBSCRIPTION` e chama o Banking para criar a assinatura. O contrato assíncrono legado é um JSON com `instructions`; para cobrança paga, a instrução contém `type=charge`, `correlation_id`, `installment_number`, `end_to_end_id` e `updated_at`.

Não há endpoint público novo neste fluxo de compensação; a integração relevante é assíncrona via Redis.

## Dados e processamento assíncrono

- A primeira cobrança paga registra parcela e aciona aprovação da venda original.
- Cobranças posteriores atualizam `valid_until`, clonam uma venda com identificador derivado do E2E e acionam a aprovação dela.
- O publicador Banking evita reenfileirar cobrança `paid` quando não houve mudança de status nem de E2E, mas o consumidor legado não demonstra uma estratégia transacional completa de deduplicação para todos os efeitos posteriores.
- `services-commerce-v2` possui `subscriptions` e `sales.subscription_id`, mas não foi confirmada nele uma estrutura de parcelas equivalente à do Commerce legado.

## Operação e validação

O teste de homologação legado registrado em `docs/deploys/2026-08-31-pix-automatic-commerce-queue-homologation/` valida o caminho Banking -> Commerce legado. Ele não cobre Commerce V2 nem elimina a dependência do Dashboard.

Antes de mudar o fluxo, validar Redis compartilhado, formato das mensagens, idempotência e efeitos financeiros/integrações de venda paga.

## Limitações e pendências

- A cadeia atual cruza quatro componentes e duas filas; falhas intermediárias podem deixar compensação incompleta.
- A fila `commerce:subscriptions:actions` deverá permanecer em drain durante a migração, mas não receber novas publicações após o corte.
- A fila/contrato/processo alvo e a estratégia de retry/DLQ estão propostos no [plano de migração](../../plans/pix-automatic-commerce-v2/README.md), sujeitos à aprovação.

## Referências

- `services-commerce-v2/app/Application/UseCase/Product/ProcessProductCheckoutUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/CreateSaleUseCase.php`
- `services-banking/src/Queue/SubscriptionActionProcessor.php`
- `services-commerce/src/Application/Service/Subscription/SubscriptionActionsService.php`
- `services-commerce/src/Application/Service/Subscription/SalePaymentApprovedService.php`
- `dashboard-seller/scripts/queues/commerce_sales_actions_worker.php`
