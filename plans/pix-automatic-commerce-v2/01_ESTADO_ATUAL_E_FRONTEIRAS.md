# Estado atual e fronteiras

## Fluxo confirmado no código

1. O Commerce V2 cria uma venda `pix_automatic`, cria a assinatura local e associa `sales.subscription_id` durante o checkout.
2. O Banking recebe/processa eventos de assinatura e cobrança, persiste `subscriptions`/`subscriptions_charge` e, quando uma cobrança se torna `paid`, publica uma instrução `charge` em `commerce:subscriptions:actions`.
3. O worker do Commerce legado registra a parcela em `subscriptions_installments`. Na primeira parcela, encaminha aprovação; nas seguintes, atualiza a validade, clona a venda e também encaminha aprovação.
4. Esse encaminhamento usa `commerce:sales:actions`, que é consumida por um script do `dashboard-seller`. Portanto, o efeito final depende de outro container e de uma fila diferente da fila de assinaturas.

## Problema de arquitetura

O fluxo mistura o estado originado no Banking, o banco do Commerce legado, uma fila de ações de vendas e um worker do Dashboard. Uma falha ou indisponibilidade em qualquer elo deixa a compensação incompleta e torna a rastreabilidade distribuída. O Commerce V2 já possui processos Hyperf e casos de uso para ativação de venda paga e seus efeitos posteriores, portanto deve ser o dono da nova compensação para vendas que ele criou.

## Contrato legado a preservar durante a transição

| Item | Comportamento atual confirmado |
| --- | --- |
| Fila de entrada legada | `commerce:subscriptions:actions` |
| Formato | Objeto com `instructions`; cada instrução é `subscriptions` ou `charge` |
| Cobrança paga | `charge` com `correlation_id`, `installment_number`, `end_to_end_id` e `updated_at` |
| Primeira parcela | Registra parcela, vincula E2E quando ausente e aprova a venda original |
| Parcela recorrente | Atualiza validade, clona venda com ID determinístico a partir do E2E e aprova a venda clonada |

O consumidor legado não deve receber novas mensagens depois do corte. Ele permanece ativo somente até a fila estar vazia e a retenção operacional definida ter expirado.

## Fronteiras e dependências

| Componente | Responsabilidade após a migração |
| --- | --- |
| `services-banking` | Persistir o estado vindo do provedor e publicar evento compatível para a fila V2. Não compensar vendas. |
| `services-commerce-v2` | Consumir, validar/idempotir e compensar assinatura, venda e efeitos de venda paga. |
| `services-commerce` | Somente consumir/drainar a fila legada durante a transição. |
| `dashboard-seller` | Fora do novo caminho; seu worker de `commerce:sales:actions` não recebe eventos novos de assinatura. |

## Lacunas a resolver antes do código

- Confirmar que Banking e Commerce V2 usam a mesma instância lógica de Redis no ambiente de destino; a fila não pode ser criada em um Redis isolado do produtor.
- Confirmar se o banco do Commerce V2 já tem uma tabela de parcelas em outro componente. A árvore atual contém `subscriptions` e `sales`, mas não uma migration/model de `subscriptions_installments`.
- Confirmar qual regra financeira deve ser aplicada a uma venda recorrente: reutilizar integralmente `ProcessPaidSaleEventUseCase` ou introduzir uma variação explícita para PIX Automático.
- Inventariar mensagens pendentes da fila legada e definir o critério temporal de encerramento do drain.
