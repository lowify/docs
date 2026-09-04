# Implementação, rollout e rollback

## Fase 0 — inventário e decisões

1. Medir volume, idade e payloads pendentes em `commerce:subscriptions:actions` sem remover mensagens.
2. Confirmar Redis compartilhado, tabelas/índices do Commerce V2 e a origem da compensação financeira de vendas PIX Automático.
3. Aprovar o envelope, as filas de retry/DLQ e a regra de deduplicação.
4. Criar a branch de trabalho no `services-commerce-v2` somente depois de este plano ser aprovado. O repositório `docs` permanece em `main`.

## Fase 1 — capacidade no Commerce V2, sem produção de eventos novos

1. Criar migration aditiva, modelo/repositório e DTOs para parcelas/deduplicação necessários.
2. Implementar casos de uso de status e de cobrança paga, incluindo cálculo de validade para `WEEKLY`, `MONTHLY`, `SEMIANNUALLY` e `ANNUALLY`.
3. Implementar criação/localização idempotente de venda recorrente, com transação determinística derivada do E2E apenas após validar colisões.
4. Implementar o `SubscriptionActionsProcess`, a configuração e logs com `event_id`, fila, `correlation_id`, parcela, E2E e `sale_id`; nunca registrar payloads sensíveis completos.
5. Reutilizar o fluxo interno de venda paga e testar seus efeitos para primeira parcela e recorrências.

## Fase 2 — produtor Banking e corte controlado

1. Criar no Banking um publicador isolado para `sales:subscriptions:actions`, com serialização e auditoria equivalentes às atuais.
2. Manter a decisão de publicação baseada na mesma transição que hoje evita repetir cobrança `paid` sem mudança de E2E.
3. Publicar primeiro o Commerce V2 com processo desabilitado ou sem produtor apontando para ele; validar health, configuração e logs.
4. Habilitar o processo do Commerce V2 e executar um caso sintético de ponta a ponta em homologação.
5. Alterar o Banking para publicar exclusivamente a nova fila. Não fazer dual-write por padrão: duas compensações em bancos distintos criariam risco de duplicidade financeira. Se dual-write for inevitável para observação, ele deve ser shadow-only, sem efeitos no consumidor secundário.

## Fase 3 — drenagem e encerramento do legado

1. Manter o worker do Commerce legado ativo para consumir apenas o estoque anterior em `commerce:subscriptions:actions`.
2. Monitorar tamanho, idade da última mensagem, erros e efeitos das duas filas de forma separada.
3. Quando a fila legada permanecer vazia pelo período aprovado e não houver produtor ativo, desabilitar seu worker em mudança posterior e documentar a retirada.
4. Não apagar filas nem mensagens durante o rollout sem autorização operacional explícita.

## Rollback

Se a nova compensação falhar, interromper a publicação nova no Banking e preservar mensagens não processadas na fila V2 para análise/reprocessamento idempotente. A reversão do produtor para a fila legada só pode ocorrer depois de verificar que não haverá processamento duplicado de uma mesma cobrança nos dois bancos. Migrations aditivas, tabelas de parcelas e chaves de deduplicação permanecem; não fazer rollback destrutivo automático.
