# Implementação, rollout e aceite

## Etapa 1 — Contratos e proteção de dados

1. Registrar a URL de notificação no portal Cielo para a integração correta, com HTTPS, headers de autenticação e evento de cancelamento selecionado.
2. Confirmar em homologação a entrega de `ChangeType 7` com `Data.PaymentId`, a consulta de disputa e a consulta por `PaymentId`.
3. Definir a chave idempotente `provider + PaymentId + sale_id` no Banking e `banking_refund_id` na Lowify.
4. Definir o tratamento explícito de status 10, 11, 2 e não finais.
5. Garantir que dados da consulta e do webhook sejam sanitizados em logs e filas.

**Saída:** contrato Cielo validado e regras inequívocas para não confundir estorno total com cancelamento parcial.

## Etapa 2 — Edge e Banking V2

1. Reutilizar o endpoint Cielo e a persistência de webhook bruto; para `ChangeType 7`, extrair `Data.PaymentId` e enviar a atualização ao Banking.
2. Manter a consulta Cielo como verificação obrigatória antes de qualquer mutação.
3. Estender o tratador Cielo para resolver cobrança e venda quando não houver refund pendente iniciado pela Lowify.
4. Criar ou concluir `refunds_charge` de forma idempotente.
5. Criar e aprovar o plano de alocação de parcelas para o valor confirmado.
6. Atualizar `charges_card` e registrar `charge_card_events` apenas quando a baixa total estiver concluída.
7. Publicar `commerce:refunds:external:actions` somente depois de persistir o refund aprovado.
8. Classificar reembolso parcial como não suportado nesta entrega, sem publicar evento de venda reembolsada.

**Saída:** um refund total externo Cielo deixa Banking V2 no mesmo estado financeiro de um refund aprovado iniciado pela Lowify.

## Etapa 3 — Lowify e ação da venda

1. Auditar `sales_refund` na base Lowify e criar a migration do índice único de `banking_refund_id`, sem recriar a tabela existente.
2. Adicionar o consumidor do Commerce V2 em `commerce:refunds:external:actions` para reconhecer a instrução de refund externo Cielo.
3. Atualizar `sales_refund` pendente quando o refund já tiver sido solicitado pela Lowify.
4. Criar `sales_refund` aprovado quando o Banking sinalizar um refund externo ainda não conhecido pela Lowify.
5. Publicar `sales:events:refunded` somente após o commit do upsert na Lowify.
6. Executar extrato, afiliados, recompensas e integrações somente após a publicação da ação de venda.
7. Manter a venda e os relatórios coerentes com a existência de reembolso aprovado.

**Saída:** a Lowify cria o reembolso antes de disparar a ação da venda, sem registros duplicados ou efeitos comerciais antes da confirmação financeira.

## Homologação

| Cenário | Critério de aceite |
| --- | --- |
| Estorno total externo | `ChangeType 7` seguido de consulta sem disputa e status 10 ou 11 cria/conclui `refunds_charge`, baixa alocações, atualiza cobrança, publica a fila intermediária e cria/aprova `sales_refund` na Lowify. |
| Refund solicitado pela Lowify | O mesmo webhook conclui os registros pendentes existentes, sem criar segunda linha. |
| Duplicidade Cielo | Reenvios do mesmo webhook não duplicam refund, evento de cobrança, alocação, `sales_refund`, extrato ou integrações. |
| Duplicidade legada | A migration de unicidade é aplicada somente após auditar registros legados e preservar a capacidade de consulta. |
| Consulta indisponível | Nenhuma alteração financeira ou comercial é confirmada; a mensagem é reprocessável e observável. |
| Cobrança sem venda | Nenhuma venda é alterada; há diagnóstico com `PaymentId`. |
| Provider incompatível | Nenhuma tabela é alterada. |
| Valor incompatível | Nenhuma baixa ou evento comercial é publicado até conciliação segura. |
| Atualização sem refund final | Status 2 após `ChangeType 7` não muda `charges_card` para `refunded` e não dispara `sale:refunded`. |
| Ordem dos efeitos | `sales_refund` é criado e confirmado na Lowify antes de `sales:events:refunded`, extrato, afiliados, recompensas e integrações. |

## Liberação

1. Validar endpoint e headers no sandbox Cielo.
2. Executar transação de cartão paga e estorno total diretamente no ambiente de homologação Cielo.
3. Conferir banco, filas e efeitos Commerce para uma única execução e para reenvio.
4. Habilitar o evento de cancelamento na URL de produção da Cielo.
5. Acompanhar os primeiros refunds com painel de filas, erros de consulta, divergência de valor e duplicidade.

## Reversão

Em incidente, desabilitar temporariamente o consumo da instrução Cielo de refund ou a seleção do evento no portal, preservando o webhook bruto para reprocessamento. Não apagar mensagens, refunds ou eventos já gravados. A retomada deve reprocessar somente mensagens ainda sem confirmação financeira/comercial.
