# Contrato, dados e eventos

## Criação da assinatura

Após confirmação comercial da Cielo, o primeiro checkout de cartão de um produto `SUBSCRIPTION` cria uma Recorrência Programada no mesmo `POST /1/sales` já usado pela integração. A requisição deve ter uma única parcela (`Installments=1`) e os campos recorrentes documentados pela Cielo:

```text
Payment.RecurrentPayment.AuthorizeNow
Payment.RecurrentPayment.StartDate, quando a primeira cobrança for futura
Payment.RecurrentPayment.EndDate
Payment.RecurrentPayment.Interval ou DailyInterval
```

O contrato final de cartão — PAN, `PaymentToken`, `CardToken`, `CardOnFile`, 3DS e CVV — não deve ser decidido por inferência. Ele depende da resposta da Cielo sobre o modelo contratado. Dados brutos de cartão e CVV nunca são persistidos pela Lowify.

Uma criação bem-sucedida retorna `RecurrentPaymentId`, que deve ser persistido antes de tratar callbacks futuros. A venda inicial continua pendente até a Cielo confirmar a primeira parcela como paga.

## Modelo de dados proposto

Reutilizar as entidades de assinatura existentes, sem criar uma nova tabela para o identificador da Cielo:

| Dado | Destino | Regra |
| --- | --- | --- |
| Série Cielo | `subscriptions.correlation_id` | `RecurrentPaymentId`, único por assinatura. |
| Provider | `subscriptions.provider_id` | Provider `cielo_ecommerce`. |
| Conta que iniciou a série | `subscriptions.account_id` | Conta BaaS/integração Cielo do seller. |
| Periodicidade e valor | `subscriptions.frequency`, `value`, `next_charge_due_date` | Normalizados a partir do produto e da resposta da Cielo. |
| Cobrança individual | `subscriptions_charge.identifier_id` | `PaymentId`, único. |
| Parcela Commerce | `subscriptions_installments` | Parcela, data paga e chave idempotente do pagamento. |
| Divisão pós-transacional | novo registro/metadata aditivo, se necessário | Deve registrar `PaymentId`, composição, status, tentativas e resposta sanitizada. |

Não reaproveitar `MerchantOrderId` como identificador de série. Ele identifica uma requisição/venda; `RecurrentPaymentId` identifica o conjunto de cobranças futuras.

## Eventos e filas

```text
Cielo ChangeType 2
-> edge-webhook grava raw e envia banking:charge:events
-> Banking V2 consulta /1/sales/{PaymentId}
-> persiste parcela e executa/recupera Split pós-transacional
-> publica commerce:cielo:subscriptions:actions
-> Commerce V2 processa assinatura e venda
```

`commerce:cielo:subscriptions:actions` é exclusiva desta feature. Não usar `sales:subscriptions:actions`, publicada pelo Banking V1, nem reutilizar uma fila genérica sem um consumidor Cielo separado. O envelope permanece um evento JSON por mensagem, com versão/`event` explícitos, para que o consumidor possa rejeitar dados fora do contrato sem tocar em venda ou financeiro.

O evento interno de parcela paga mantém o formato consolidado:

```json
{
  "event_id": "uuid-da-entrega",
  "event": "subscription.charge.paid",
  "occurred_at": "2026-10-19T12:00:00+00:00",
  "correlation_id": "RecurrentPaymentId",
  "installment_number": 2,
  "payment_id": "PaymentId",
  "paid_at": "2026-10-19T12:00:00+00:00"
}
```

Na adaptação ao consumidor atual, `payment_id` deve ser a chave idempotente que chega ao `ProcessSubscriptionChargePaidUseCase`. A escolha entre preencher o campo atual ou criar um campo de provedor explícito será validada com migration e teste de compatibilidade, sem perder a origem Cielo.

## Webhook, consulta e reconciliação

O webhook da Cielo é o caminho imediato, não a única prova de pagamento:

1. Edge aceita `ChangeType: 2`, exige `PaymentId` e preserva também `RecurrentPaymentId` para auditoria.
2. Banking consulta o pagamento na API de consultas Cielo usando `PaymentId`.
3. Só pagamento no status final pago cria/publica a parcela.
4. Status recusado, agendado ou pendente atualiza o estado sem confirmar venda.
5. Uma reconciliação consulta séries ativas ou sem atualização recente por `RecurrentPaymentId`; ela recupera callback atrasado, mas não substitui o webhook.

Cada etapa deve ser idempotente por `PaymentId`; webhook e poll da mesma cobrança não podem criar duas parcelas, vendas, entregas, transferências ou notificações.

## Split pós-transacional

Na cobrança avulsa, a Lowify já monta `SplitPayments` dentro da criação. Para recorrência, a documentação da Cielo Split diz que a divisão deve ser solicitada no momento pós-transacional. O adaptador precisa:

1. recuperar a composição original da assinatura — seller, afiliados, MDR e tarifa;
2. validar que a soma confere com o valor efetivamente pago;
3. enviar uma única solicitação de divisão para aquele `PaymentId`;
4. tratar resposta de sucesso, duplicidade/estado já dividido e falha transitória de modo explícito;
5. manter evidência sanitizada e fila de retry/DLQ para erro recuperável.

A regra financeira exata — principalmente se a confirmação de venda deve aguardar o Split bem-sucedido — precisa de aprovação de Produto/Financeiro. A recomendação é não liberar saldo/repasse ao seller antes de a divisão estar confirmada, mas não reverter uma venda que já tenha sido autorizada pelo comprador sem um fluxo de compensação definido.

## Cancelamento e reembolso

- Cancelar uma assinatura atua sobre `RecurrentPaymentId` e impede futuras cobranças; não desfaz automaticamente parcelas já liquidadas.
- Reembolsar atua sobre um `PaymentId` já pago e segue o fluxo atual de refund Cielo por cobrança.
- Cancelamento, reembolso e webhook podem chegar em ordem diferente. Cada transição precisa ser idempotente e manter histórico.

## Segurança e observabilidade

- Não registrar PAN, CVV, Bearer token, `CardToken` ou `PaymentToken` em logs, fila ou payload de evento.
- Registrar `RecurrentPaymentId`, `PaymentId`, `subscription_id`, `sale_id`, número da parcela, status Cielo, resultado do Split e `event_id`.
- Monitorar: séries criadas, callbacks recebidos, consultas falhas, parcelas confirmadas, Split pendente/falho, retries e mensagens em DLQ.
- Alertar para série ativa sem evento dentro da janela esperada e para cobrança paga sem Split confirmado.
