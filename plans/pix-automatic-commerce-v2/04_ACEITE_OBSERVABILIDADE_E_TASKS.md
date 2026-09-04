# Aceite, observabilidade e tasks

## Casos de aceite

| Caso | Resultado esperado |
| --- | --- |
| Assinatura criada no checkout V2 | Venda pendente e assinatura V2 compartilham `correlation_id`; nenhuma compensação ocorre antes da cobrança paga. |
| Primeira cobrança paga | Uma parcela é registrada, E2E é associado à venda quando ausente, a venda original vira `paid` e os efeitos internos de venda paga são disparados uma vez. |
| Cobrança recorrente paga | Uma única parcela é registrada, `valid_until` avança corretamente, uma única venda recorrente é criada/encontrada e aprovada, e os efeitos internos ocorrem uma vez. |
| Reentrega do mesmo evento | Não duplica parcela, venda, transferência, entrega, integração nem notificação. |
| Mesmo pagamento com E2E corrigido | A regra aprovada de correção é aplicada sem criar segunda parcela/venda. |
| Evento inválido | Não altera dados; registra falha estruturada e segue a política de descarte/DLQ. |
| Falha transitória | Mensagem pode ser rastreada e reprocessada sem perda nem duplicidade. |
| Transição | Depois do corte, o Banking não aumenta `commerce:subscriptions:actions`; mensagens prévias continuam processáveis pelo legado até a drenagem. |
| Isolamento do Dashboard | Nenhum evento novo deste fluxo é publicado em `commerce:sales:actions` e o worker do Dashboard não é requisito de sucesso. |

## Observabilidade mínima

- Contadores por fila: recebidas, válidas, concluídas, duplicadas, descartadas, retry e DLQ.
- Logs correlacionáveis por `event_id`, `correlation_id`, `end_to_end_id`, número da parcela e `sale_id`.
- Alerta para mensagens em retry/DLQ, crescimento contínuo da fila e idade acima do SLA acordado.
- Auditoria no Banking do evento publicado e no Commerce V2 do resultado aplicado, sem conteúdo sensível completo.

## Tasks executáveis

1. Aprovar este plano e as decisões pendentes de Redis, parcela, retry/DLQ e financeiro.
2. Criar branch no `services-commerce-v2`; manter `docs/main` como fonte deste plano.
3. Implementar schema, repositórios, DTOs e testes unitários de idempotência/cálculo de validade.
4. Implementar processo/configuração e testes de integração com Redis/banco.
5. Implementar publicador Banking, contrato compartilhado por testes de payload e auditoria.
6. Preparar documentação de deploy e teste de compatibilidade de homologação antes de qualquer alteração em VPS.
7. Executar homologação com dados sintéticos, acompanhando produtor, nova fila, compensação V2 e ausência de dependência do Dashboard.
8. Fazer o corte, observar, drenar a fila legada e planejar sua desativação em mudança separada.

## Referências de descoberta

- `services-banking/src/Queue/SubscriptionActionProcessor.php`
- `services-commerce/bin/subscriptions-queue-worker.php`
- `services-commerce/src/Application/Service/Subscription/SubscriptionActionsService.php`
- `services-commerce/src/Application/Service/Subscription/SalePaymentApprovedService.php`
- `services-commerce-v2/config/autoload/processes.php`
- `services-commerce-v2/app/Process/SaleEventsProcess.php`
- `services-commerce-v2/app/Application/UseCase/Sale/ProcessPaidSaleEventUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/CreateSaleUseCase.php`
- `docs/deploys/2026-08-31-pix-automatic-commerce-queue-homologation/2026-08-31_PIX_AUTOMATIC_COMMERCE_QUEUE_HOMOLOGATION.md`
