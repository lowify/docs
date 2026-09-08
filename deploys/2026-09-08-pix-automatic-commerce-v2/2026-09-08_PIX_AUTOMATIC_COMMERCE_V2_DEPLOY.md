# Deploy — migração de assinaturas PIX Automático para Commerce V2

## Objetivo

Transferir o processamento assíncrono de cobranças PIX Automático confirmadas do Commerce legado para o `services-commerce-v2`.

Após o corte, o `services-banking` publica eventos de assinatura na lista Redis `sales:subscriptions:actions`. O novo processo `commerce_subscription_actions_queue` do Commerce V2 registra a parcela, atualiza a assinatura e usa o fluxo interno de venda paga para a venda original ou recorrente. Não há rota pública, JWT ou alteração de checkout nesta entrega.

Ficam fora do escopo: migrar dados históricos, drenar ou remover `commerce:subscriptions:actions`, alterar o worker do `services-commerce` ou o `dashboard-seller`, e reprocessar mensagens já existentes.

## Componentes e referências

| Componente | Branch de deploy | Commit obrigatório |
| --- | --- | --- |
| `services-commerce-v2` | `feat/pix-automatic-commerce-v2` | `bb50aa0` — `feat: process pix automatic subscription actions` |
| `services-banking` | `feat/pix-automatic-commerce-v2` | `3f9f549` — `feat: publish pix automatic events to commerce v2` |

As referências acima são locais no momento da preparação deste documento: nenhuma contém uma branch remota `origin/feat/pix-automatic-commerce-v2`. Não iniciar o deploy antes de publicar as duas referências remotas, conferir que seus `HEAD`s correspondem aos commits da tabela e obter aprovação para os riscos listados abaixo.

## Alterações incluídas

```text
Provedor PIX Automático
  -> services-banking: SubscriptionActionProcessor
  -> Redis: sales:subscriptions:actions
  -> services-commerce-v2: commerce_subscription_actions_queue
  -> assinatura, subscriptions_installments e venda
  -> ProcessPaidSaleEventUseCase e seus efeitos internos
```

- O Banking deixa de publicar novas ações na fila legada `commerce:subscriptions:actions` para as mudanças de status e cobranças pagas desta branch.
- O novo contrato possui um evento por mensagem, com `event_id`, `event`, `occurred_at` e dados de correlação. Os eventos implementados são `subscription.status.updated` e `subscription.charge.paid`.
- Para `subscription.charge.paid`, o payload contém `correlation_id`, `installment_number`, `end_to_end_id` e `paid_at` em ISO 8601.
- O Commerce V2 registra `SubscriptionActionsProcess` como processo Hyperf. Para cobrança paga, cria a parcela identificada por assinatura + número de parcela, atualiza `valid_until`, associa/cria a venda correspondente e chama `ProcessPaidSaleEventUseCase`.
- A fila usa Redis compartilhado entre Banking e Commerce V2. O processo é configurado por `SUBSCRIPTION_ACTIONS_PROCESS_ENABLED`, `SUBSCRIPTION_ACTIONS_QUEUE` e `SUBSCRIPTION_ACTIONS_TIMEOUT_SECONDS`.

## Banco de dados

Não há migration, DDL ou DML nesta entrega.

## Sequência de deploy

Publicar primeiro o consumidor do Commerce V2 e somente depois o produtor Banking. Assim, nenhum evento novo é encaminhado para o caminho V2 antes de o processo estar disponível.

1. No diretório oficial de produção do `services-commerce-v2` (`/opt/lowify/services/service-commerce-v2`), atualizar a branch de deploy:

   ```bash
   cd /opt/lowify/services/service-commerce-v2
   git fetch origin --prune
   git switch feat/pix-automatic-commerce-v2
   git pull --ff-only origin feat/pix-automatic-commerce-v2
   git rev-parse HEAD
   docker compose up -d --build
   docker compose ps
   ```

   Como conferência técnica, verificar somente se o container iniciou sem erro de configuração:

   ```bash
   docker compose logs --tail=200 service-commerce-v2
   ```

2. O processo `commerce_subscription_actions_queue` não registra uma mensagem própria na abertura. Ele só escreve `Event processed` ao consumir um evento ou `Failed to process event` em caso de falha. A confirmação funcional do consumidor ocorre no teste de compatibilidade; não inserir nem consumir mensagens manualmente nesta etapa.

3. No diretório oficial de produção do `services-banking` (`/opt/lowify/services/services-banking`), atualizar a branch de deploy:

   ```bash
   cd /opt/lowify/services/services-banking
   git fetch origin --prune
   git switch feat/pix-automatic-commerce-v2
   git pull --ff-only origin feat/pix-automatic-commerce-v2
   git rev-parse HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=200 services-banking-subscriptions-queue-worker
   ```

4. Registrar os SHAs efetivamente publicados. Se a atualização do Banking falhar, não gerar manualmente eventos na fila nova e não alterar a fila legada. Restaurar somente conforme o plano de rollback abaixo, depois de avaliar se algum evento novo foi publicado.

## Testes de compatibilidade em homologação

Executar antes da produção, no `services-commerce-v2` e `services-banking` atualizados com as mesmas referências desta entrega. O executor é o processo Hyperf `commerce_subscription_actions_queue`; o worker Banking é `services-banking-subscriptions-queue-worker`.

Pré-condições: Redis compartilhado, `SUBSCRIPTION_ACTIONS_PROCESS_ENABLED=true`, tabela confirmada e uma assinatura/venda inteiramente sintética. Não usar dados, E2E, correlação, seller ou comprador de produção. Anotar os identificadores sintéticos para auditoria e limpeza controlada.

1. Criar uma assinatura PIX Automático de teste pelo checkout V2 e conservar o `correlation_id` e a venda inicial.
2. Confirmar uma primeira cobrança de teste pelo caminho suportado pelo provedor/Banking. Não inserir JSON diretamente no Redis.
3. Confirmar que o Banking publicou `subscription.charge.paid` em `sales:subscriptions:actions` e que o Commerce V2 registrou uma parcela, vinculou o E2E à venda inicial quando necessário e deixou a venda como paga.
4. Confirmar que os efeitos visíveis de venda paga (por exemplo, entrega e integração aplicáveis ao produto de teste) ocorreram uma única vez.
5. Confirmar uma cobrança recorrente sintética com E2E distinto. Conferir uma única parcela adicional, avanço de `valid_until`, uma única venda recorrente e os efeitos de venda paga uma única vez.
6. Repetir a confirmação do mesmo pagamento somente se o ambiente suportar reentrega segura. O resultado deve ser ausência de parcela e venda duplicadas.
7. Conferir tecnicamente os logs dos dois serviços por `event_id`, `correlation_id` e E2E. Como o processo não possui retry/DLQ, qualquer erro de processamento é reprovação do teste e exige decisão/ajuste antes do corte.

Limpeza: remover ou reverter exclusivamente os dados sintéticos anotados, segundo procedimento aprovado para o ambiente. Não apagar listas Redis, registros de outras assinaturas nem dados operacionais para "limpar" o teste.

## Validação pós-deploy

1. Em uma assinatura PIX Automático de teste previamente aprovada para produção, realize uma cobrança de valor controlado. Confirme no produto/área de vendas que a primeira venda passa a paga e que a entrega ou acesso esperado é liberado uma única vez. Se não ocorrer, suspenda novas cobranças de teste e acione a operação.
2. Realize uma cobrança recorrente de teste. Confirme que aparece apenas uma nova venda/parcela e que a vigência da assinatura avançou. Se houver duplicidade, interrompa o corte e não tente compensar apagando vendas ou parcelas.
3. Como conferência técnica complementar, a equipe técnica pode observar os logs do Banking e do Commerce V2 para o identificador de correlação e confirmar que o evento foi processado. Não consumir, limpar, mover ou reenfileirar mensagens Redis durante a validação.

## Rollback

1. Antes de reverter o Banking, identificar se algum evento no novo formato foi publicado ou processado. Uma mesma cobrança não pode ser encaminhada aos caminhos V2 e legado sem análise, pois pode duplicar parcela, venda e efeitos financeiros.
2. Se o Commerce V2 falhar antes de qualquer evento V2 ser publicado, retornar o Commerce V2 à revisão anterior registrada, reconstruir o container e manter o Banking na revisão anterior.
3. Se o Banking já publicou eventos V2, preservar `sales:subscriptions:actions` e os logs. Não limpar, drenar, reenfileirar manualmente nem apagar registros de parcela/venda. Registrar correlação, E2E e estado de cada caso para decisão de reprocessamento idempotente.
4. Só retornar o Banking ao produtor legado depois de confirmar que nenhum evento V2 pendente ou processado será compensado também no Commerce legado. Essa decisão exige aprovação operacional explícita.
5. Reverter os repositórios à revisão anterior conhecida e aprovada, em ordem segura: Banking (interrompe novas publicações V2), depois Commerce V2. Não executar rollback de banco: não há DDL desta entrega e dados criados durante o processamento são evidência operacional.

O worker e a fila do Commerce legado permanecem preservados e fora deste rollback. Não usar `git reset --hard`, `push --force` nem exclusão de chaves Redis.
