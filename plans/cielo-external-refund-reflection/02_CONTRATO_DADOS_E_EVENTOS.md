# Contrato, dados e eventos

## Evento externo

A Cielo envia para a URL cadastrada um corpo reduzido:

    {
      "PaymentId": "uuid-da-cobranca",
      "ChangeType": 25
    }

O Edge responde ao protocolo da Cielo, persiste o recebimento e publica uma instrução interna. Ele não tenta decidir valor, venda ou situação financeira a partir do webhook.

    {
      "provider": "cielo_ecommerce",
      "event": "refund_status_changed",
      "instructions": {
        "type": "refund_status_changed",
        "payment_id": "uuid-da-cobranca",
        "change_type": 25
      }
    }

O Banking consulta `GET /1/sales/{PaymentId}` no ambiente Cielo correspondente e utiliza a resposta como fonte de verdade. Do retorno são necessários, no mínimo, `PaymentId`, `Payment.Status`, `Payment.Amount`, tipo de pagamento e `MerchantOrderId`.

## Persistência no Banking V2

| Destino | Registro esperado |
| --- | --- |
| `charges_card` | A cobrança Cielo correspondente passa a `refunded` somente após estorno total confirmado. |
| `charge_card_events` | Um evento de origem `webhook` registra o status Cielo, a transição para `refunded` e referências de diagnóstico não sensíveis. |
| `refunds_charge` | Um refund aprovado representa a operação externa, com provider Cielo, venda, `PaymentId` como correlação e valor efetivamente estornado. |
| `refund_charge_card_installment_allocations` | Plano de alocação criado e aprovado para refletir o valor nas parcelas e participantes. |
| Alocações de parcelas | `refunded_amount` e status são atualizados pelo plano aprovado; a cobrança só é marcada reembolsada depois da baixa completa. |

Se já existir um `refunds_charge` pendente da solicitação iniciada pela Lowify, a notificação externa conclui esse mesmo registro. Se não existir, o Banking cria o registro de origem externa e aplica o mesmo plano de alocação. Não pode haver dois refunds aprovados para a mesma operação total.

O valor deve vir da consulta Cielo, em centavos, e ser normalizado antes da criação do plano. Se o valor não puder ser conciliado com o saldo reembolsável das alocações locais, o processamento falha de forma recuperável e não publica evento comercial.

## Garantias de unicidade

As garantias devem existir no banco, não apenas no consumidor de fila:

| Tabela | Chave de idempotência |
| --- | --- |
| `refunds_charge` | `provider_id + correlation_id + sale_id` para o refund total Cielo. |
| `sales_refund` | `banking_refund_id`. |
| `charge_card_events` | A transição de refund é inserida apenas uma vez para a cobrança e o estado final tratado. |

Antes de adicionar índices únicos, a migration deve auditar e tratar registros legados duplicados ou nulos. A operação não deve criar uma restrição que impeça o processamento de refunds existentes sem uma estratégia de compatibilidade.

## Evento Banking para Lowify

Depois de persistir o refund aprovado, o Banking publica uma instrução na fila intermediária `commerce:refunds:actions`:

    {
      "sale_id": 123,
      "event": "cielo_external_refund_confirmed",
      "status": "approved",
      "banking_refund_id": 456,
      "amount": 199.90,
      "fee": 0,
      "triggered_at": "2026-10-29 12:00:00"
    }

O `banking_refund_id` é a chave de idempotência entre Banking e Lowify. A publicação ocorre somente após a transação do Banking ter concluído os registros financeiros.

## Reflexo na Lowify

O consumidor de `commerce:refunds:actions` deve ser a fronteira de persistência na Lowify. Ele recebe a instrução, valida o vínculo da venda e faz upsert de `sales_refund` por `banking_refund_id`:

| Situação | Ação |
| --- | --- |
| Registro pendente criado por solicitação Lowify | Atualizar para `approved`, preservando valor, taxa e vínculo da venda. |
| Sem registro local, pois o refund veio da Cielo | Criar o registro `sales_refund` na tabela existente da Lowify, com venda, seller, valor, taxa, status aprovado e identificador do Banking. |
| Registro aprovado | Não repetir efeitos. |

Após a transação Lowify confirmar o `sales_refund`, o próprio consumidor publica `sales:events:refunded`. Só então o fluxo de `sale:refunded` executa extrato, afiliados, recompensas e integrações. Nenhum efeito é executado antes de o registro Lowify existir e estar aprovado.

## Falhas, repetição e observabilidade

- Webhook inválido, sem `PaymentId` ou duplicado não altera cobrança nem venda.
- Falha de consulta Cielo ou de persistência na Lowify deve reencaminhar a mensagem conforme a política da fila; nenhuma confirmação parcial é persistida.
- Cobrança sem venda correspondente, provider incompatível ou valor não conciliável gera erro observável e não cria refund artificial.
- Repetição após sucesso encontra os registros aprovados e termina sem novos efeitos.
- Logs, métricas e alertas carregam `PaymentId`, `charge_card_id`, `sale_id`, `banking_refund_id`, status Cielo e resultado. Nunca registram cartão, token, credenciais ou payload sensível além do necessário.
