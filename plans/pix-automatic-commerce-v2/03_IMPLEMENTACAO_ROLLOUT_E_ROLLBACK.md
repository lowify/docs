# Implementação, rollout e rollback

## Fase 0 — inventário e decisões

1. Localizar a estrutura de parcelas já existente no banco/repositórios do Commerce V2 e confirmar suas chaves e índices para reutilização.
2. Aprovar o envelope, as filas de retry/DLQ e a regra de deduplicação.
4. Criar a branch de trabalho no `services-commerce-v2` somente depois de este plano ser aprovado. O repositório `docs` permanece em `main`.

## Fase 1 — capacidade no Commerce V2, sem produção de eventos novos

1. Reutilizar a estrutura de parcelas existente e criar/adaptar modelo, repositório e DTOs de deduplicação necessários; criar migration aditiva apenas se os índices/garantias forem insuficientes.
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

## Fluxo legado

O worker e a fila legados permanecem fora do escopo. O corte no Banking impede novas publicações em `commerce:subscriptions:actions`, mas esta entrega não inventaria mensagens existentes, não executa drain, não monitora o legado como critério de aceite e não agenda sua retirada.

## Rollback

Se a nova compensação falhar, interromper a publicação nova no Banking e preservar mensagens não processadas na fila V2 para análise/reprocessamento idempotente. A reversão do produtor para a fila legada só pode ocorrer depois de verificar que não haverá processamento duplicado de uma mesma cobrança nos dois bancos. Migrations aditivas, tabelas de parcelas e chaves de deduplicação permanecem; não fazer rollback destrutivo automático.
