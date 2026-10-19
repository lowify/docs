# Implementação, rollout e aceite

## Fase 0 — confirmação e contrato externo

1. Obter da Cielo confirmação escrita de Recorrência Programada, Split recorrente, Cartão Protegido/tokenização e política de CVV para a nova conta Master.
2. Confirmar em sandbox o payload de criação, retorno de `RecurrentPaymentId`, geração de uma parcela futura, `ChangeType: 2`, consulta por `PaymentId` e Split pós-transacional.
3. Definir o tratamento de `PaymentToken`/`CardToken` com a Cielo e Segurança; não reutilizar o token atual sem confirmação explícita.
4. Fechar com Produto/Financeiro a regra de preço recorrente: produto principal, desconto, bump, afiliado, MDR, tarifa e política para falha de Split.
5. Só depois criar branches de implementação; `docs/main` continua sendo a fonte deste plano.

## Fase 1 — dados e disponibilidade sem cobrança recorrente ativa

1. Mapear e ajustar o vínculo entre as assinaturas Banking e Commerce V2 para o `RecurrentPaymentId`.
2. Criar migrations estritamente aditivas para estado/evidência do Split recorrente ou chave de transação Cielo, apenas se os campos existentes não preservarem a semântica corretamente.
3. Disponibilizar `card` para produto `SUBSCRIPTION` somente atrás de uma flag e apenas para `cielo_ecommerce` elegível.
4. Criar validação de integração: conta ativa/aprovada, credenciais presentes e habilitações exigidas confirmadas.
5. Criar uma configuração e um processo exclusivos no Commerce V2, inicialmente desligados:

```text
CIELO_SUBSCRIPTION_ACTIONS_PROCESS_ENABLED=false
CIELO_SUBSCRIPTION_ACTIONS_QUEUE=commerce:cielo:subscriptions:actions
```

6. Criar no Banking V2 um publicador Cielo que escreva somente nessa fila e não em `sales:subscriptions:actions` ou outra fila de assinatura existente.
7. Preparar logs, métricas, retry e DLQ antes de publicar eventos financeiros novos.

## Fase 2 — criação e processamento da série

1. Estender o cliente Cielo para criar Recorrência Programada sem alterar o fluxo `ONE_TIME` existente.
2. Persistir a assinatura provisoriamente, criar a série de forma idempotente e salvar `RecurrentPaymentId`/estado retornado.
3. Incluir `ChangeType: 2` no Edge, preservando a deduplicação de webhook e encaminhando o evento para Banking.
4. No Banking, consultar o `PaymentId`, persistir a parcela e aplicar o Split pós-transacional idempotente.
5. Publicar `subscription.charge.paid` somente uma vez para a fila exclusiva, quando a parcela estiver efetivamente paga e com o estado financeiro aprovado.
6. No consumidor exclusivo do Commerce V2, reutilizar `ProcessSubscriptionChargePaidUseCase` e `ProcessPaidSaleEventUseCase`; não duplicar entrega, integração, notificação, saldo ou comissão.

## Fase 3 — ciclo de vida e recuperação

1. Implementar consulta por `RecurrentPaymentId`, cancelamento e atualização de estado da série.
2. Criar reconciliação limitada para assinaturas ativas sem callback recente, com lock por série e janela configurável.
3. Implementar recuperação de Split pendente e uma visão operacional para parcelas que exigem ação.
4. Manter refund por `PaymentId`; testar refund de primeira e de parcela posterior sem cancelar indevidamente a série.

## Rollout e rollback

1. Publicar schema e consumidores com a flag desligada.
2. Homologar uma série Cielo de teste completa: criação, primeira cobrança, próxima cobrança, webhook, consulta, Split, venda, entrega e cancelamento.
3. Habilitar inicialmente para um seller de teste e uma periodicidade mensal.
4. Observar as métricas e conciliar cada valor antes de ampliar para outros sellers.
5. Para pausar novas adesões, desligar a flag de disponibilidade. Não apagar séries, parcelas ou mensagens pendentes.
6. Em falha, preservar `PaymentId`, `RecurrentPaymentId`, evidências e retry/DLQ. Não fazer rollback destrutivo de migrations ou compensação financeira automática.

## Casos de aceite

| Caso | Resultado esperado |
| --- | --- |
| Produto avulso Cielo | Continua criando cartão parcelado/à vista sem campos de recorrência. |
| Produto `SUBSCRIPTION` elegível | Exibe cartão apenas quando a integração Cielo estiver aprovada e a flag ativa. |
| Criação inicial | Cria uma única série Cielo e persiste um único `RecurrentPaymentId`. |
| Primeira parcela paga | Registra uma parcela, aprova a venda original e executa seus efeitos uma vez. |
| Parcela futura paga | Registra uma parcela, cria/localiza uma venda recorrente e executa seus efeitos uma vez. |
| Reentrega de `ChangeType: 2` | Não duplica Split, parcela, venda, saldo, entrega, comissão ou notificação. |
| Isolamento de fila | O publicador Cielo escreve somente em `commerce:cielo:subscriptions:actions`; workers Banking V1 não recebem a mensagem e o consumidor Cielo não lê filas antigas. |
| Webhook perdido | Reconciliação localiza a cobrança e produz o mesmo resultado idempotente. |
| Split pós-transacional falha | Estado fica observável e recuperável; não há repasse duplicado. |
| Cancelamento | Impede próximas cobranças, preserva histórico e não reverte parcelas anteriores. |
| Refund de uma parcela | Opera pelo `PaymentId` correto, atualiza somente aquela parcela/venda e não presume cancelamento da série. |
| Dados sensíveis | Nenhum PAN, CVV, token ou segredo aparece em banco de eventos, logs ou mensagens. |

## Referências

- [Recorrência no Split](https://docs.cielo.com.br/split/docs/recorr%C3%AAncia)
- [Recorrência API E-commerce Cielo](https://docs.cielo.com.br/ecommerce-cielo/reference/recorr%C3%AAncia)
- [Agendar uma autorização no Split](https://docs.cielo.com.br/split/reference/agendar-uma-autorizacao)
- [Salvar cartão durante autorização](https://docs.cielo.com.br/split/reference/apiecommerce-criar-cardtoken)
- [Códigos de retorno do Split](https://docs.cielo.com.br/split/reference/c%C3%B3digos-de-erros-da-api)
