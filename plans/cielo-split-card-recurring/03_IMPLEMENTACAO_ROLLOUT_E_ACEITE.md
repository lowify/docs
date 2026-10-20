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
3. Disponibilizar `card` para produto `SUBSCRIPTION` somente atrás da chave por seller `cielo_recurring_card_enabled`, apenas para `cielo_ecommerce` elegível e sempre em `1x`.
4. Criar no Dashboard a edição triestado da chave: `1` liberado, `0` negado explicitamente e ausência da linha como `null`/não configurado; os dois últimos estados não habilitam a feature.
5. Criar validação de integração: conta ativa/aprovada, credenciais presentes e habilitações exigidas confirmadas.
6. Criar uma configuração e um processo exclusivos no Commerce V2, inicialmente desligados:

```text
CIELO_SUBSCRIPTION_ACTIONS_PROCESS_ENABLED=false
CIELO_SUBSCRIPTION_ACTIONS_QUEUE=commerce:cielo:subscriptions:actions
```

7. Criar no Banking V2 um publicador Cielo que escreva somente nessa fila e não em `sales:subscriptions:actions` ou outra fila de assinatura existente.
8. Preparar logs, métricas, retry e DLQ antes de publicar eventos financeiros novos.

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

A reconciliação inicia automaticamente no Banking e só processa séries Cielo recorrentes já existentes. Ela não habilita cartão para todos os sellers: a permissão de criar novas séries continua sendo exclusivamente `cielo_recurring_card_enabled=1` no seller. Antes de liberar o primeiro seller em produção, o consumidor exclusivo do Commerce precisa estar habilitado.

### Limites identificados na implementação

- A Cielo confirmou a consulta por `RecurrentPaymentId`: a lista `RecurrentTransactions` traz o `TransactionId`, que é o `PaymentId` de cada cobrança recorrente. A recuperação consulta cada um deles e, para uma parcela paga, executa o Split pós-transacional pelo `PaymentId`. A API mantém consulta por até três meses; após isso, a fonte operacional é o histórico local e o portal Cielo.
- No Commerce V2, a mensagem é reservada no Redis até a confirmação. Reservas expiradas voltam para a fila; parcela e tarefa de venda são persistidas juntas, e as etapas concluídas da venda não voltam a ser executadas.
- Cada etapa concluída fica registrada. Se o worker parar, o evento volta automaticamente para `pending`, retoma apenas da etapa incompleta e aplica espera crescente quando houver falha. Transferência, recompensa, acesso, entrega, contador e push usam as chaves idempotentes já existentes ou adicionadas para que essa retomada não replique o efeito local.

### Evidência de homologação — 2026-10-20

- Compra manual feita no checkout público de homologação `pay.statuslive.site`, para produto `SUBSCRIPTION` Cielo habilitado por flag de seller.
- O mock HTTP local retornou uma série Cielo válida; Banking persistiu cobrança de cartão paga, `RecurrentPaymentId`, assinatura ativa e parcela inicial pendente.
- A reconciliação pelo `RecurrentPaymentId` localizou o `PaymentId`, aplicou o Split pós-transacional e publicou a ação na fila exclusiva.
- Commerce V2 marcou a venda como paga, manteve a assinatura ativa e concluiu o evento durável com as nove etapas registradas, sem erro.
- Uma segunda cobrança futura simulada para a mesma série produziu uma parcela `2` paga, um novo Split aplicado e uma nova venda recorrente paga, preservando a assinatura original.
- Com a reconciliação periódica habilitada em homologação, uma terceira cobrança futura foi localizada automaticamente, sem executar comando manual; a parcela `3`, o Split, a venda recorrente e o evento durável também concluíram com sucesso.
- O `PUT /subscription/pix/cancel` chamou a desativação da série no mock com `RecurrentPaymentId`, gravou `canceled_seller` localmente e uma nova tentativa de gerar parcela foi recusada pelo mock. Cobranças já criadas antes do cancelamento continuaram recuperáveis, preservando o histórico.
- No cenário de resposta perdida, o mock aplicou o Split e encerrou a conexão antes da resposta. A cobrança permaneceu `pending` com Split `processing` e sem venda; a reconciliação consultou a evidência remota, reconheceu o Split aplicado e concluiu uma única parcela/venda, sem repetir a divisão.
- Limite do teste: o mock não dispara `ChangeType: 2` automaticamente. O caminho exercitado foi a recuperação por reconciliação, não a entrega HTTP do webhook. O aceite antes de produção ainda exige testar o callback real da Cielo e as credenciais/habilitações da conta Master.

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
| Produto `SUBSCRIPTION` com flag `null` ou `0` | Não exibe nem aceita cartão, mesmo que o request seja adulterado. |
| Assinatura com parcelas maiores que `1` | Dashboard não oferece parcelamento; Commerce V2 rejeita a gravação e o checkout rejeita a tentativa. |
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
