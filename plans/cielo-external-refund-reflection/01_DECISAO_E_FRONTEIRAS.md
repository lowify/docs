# Decisão e fronteiras

## Decisão

O webhook da Cielo não é tratado como prova suficiente por si só. Ele apenas desperta o processamento. O Banking V2 consulta a transação pelo `PaymentId` e somente uma resposta final da Cielo autoriza alterações financeiras e comerciais.

A entrega cobre o estorno total de uma cobrança de cartão Cielo associada a uma venda Lowify. Para esse caso, o Banking reconstrói o registro de refund que não existe quando a operação foi iniciada fora da plataforma e publica o evento comercial já adotado pela Lowify.

## Estado alvo

| Camada | Responsabilidade |
| --- | --- |
| Cielo | Informa `PaymentId` e `ChangeType 25`; a consulta posterior informa o estado real da cobrança. |
| Edge Webhook | Persiste o webhook bruto, aplica a deduplicação de entrega e envia a instrução para a fila de refunds do Banking V2. |
| Banking V2 | Consulta a Cielo, resolve a venda, registra ou conclui o refund, atualiza a cobrança e publica o evento `refunded`. |
| Commerce V2 | Cria ou atualiza `sales_refund` e executa os efeitos existentes de `sale:refunded`. |

## Estados Cielo aceitos

| Situação consultada | Tratamento |
| --- | --- |
| `Payment.Status 10 — Voided` | Cancelamento total confirmado; refletir o reembolso. |
| `Payment.Status 11 — Refunded` | Estorno total confirmado; refletir o reembolso. |
| `Payment.Status 2 — PaymentConfirmed` após `ChangeType 25` | Pode representar cancelamento parcial; não alterar a venda nem publicar `sale:refunded` nesta entrega. |
| Qualquer outro estado | Não há confirmação final de reembolso; não gerar registros financeiros ou comerciais. |

## Vínculo entre cobrança e venda

O `PaymentId` é a chave de entrada. O Banking localiza primeiro a cobrança em `charges_card.provider_transaction_id` e valida que ela pertence ao provider `cielo_ecommerce`. A venda é resolvida pelo identificador de transação no Commerce V2; se necessário, o `MerchantOrderId`/`order_id` da cobrança serve como recuperação controlada.

Não é permitido criar refund para cobrança, provider ou venda que não possam ser correlacionados de forma única. Esses casos devem ser registrados para tratamento operacional, sem atualizar tabelas de venda.

## Reembolso total e parcial

A Cielo usa o mesmo `ChangeType 25` para cancelamento e estorno parcial. Em Split, um cancelamento parcial mantém a transação com status pago e informa valores por participante; portanto, converter todo `ChangeType 25` em venda reembolsada corromperia saldo, relatórios e integrações.

Esta entrega considera total somente os estados finais 10 e 11. A implementação deve registrar métrica para notificação parcial ignorada e manter evidência suficiente para uma entrega futura de reembolso parcial, que precisará de chave própria da operação e valor acumulado.

## Idempotência

A Cielo pode reenviar notificações e o Edge pode reprocessar uma mensagem. A unidade de idempotência do reembolso total é:

`cielo_ecommerce + PaymentId + sale_id`.

Uma repetição não pode criar novos registros de refund, repetir a baixa de alocações, atualizar novamente a cobrança, duplicar `sales_refund` nem reenviar efeitos de `sale:refunded`.

## Referências externas

- [Cielo — Post de Notificação](https://docs.cielo.com.br/ecommerce-cielo/docs/webhook)
- [Cielo — Status da transação](https://docs.cielo.com.br/ecommerce-cielo/reference/payment-status)
- [Cielo — Cancelamento](https://docs.cielo.com.br/ecommerce-cielo/docs/cancelamento)
- [Cielo Split — cancelamento parcial](https://docs.cielo.com.br/split/reference/cancela-valor-parcial-ecommerce)
- [Cielo Split — cancelamento total](https://docs.cielo.com.br/split/reference/cancelar-valor-total-1)
