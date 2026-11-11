# Deploy — Reembolso de vendas na UTMify

## Objetivo

Publicar o envio de reembolsos aprovados para a UTMify. A venda continuará sendo identificada pelo mesmo `orderId` já usado no envio original; o novo envio atualiza o pedido externo para `status: refunded`, preserva sua data de aprovação e informa a data do reembolso.

O fluxo afetado é exclusivamente assíncrono e não altera checkout, rotas HTTP, autenticação, banco de dados ou credenciais:

```text
Commerce V2: sales:events:refunded (com triggered_at)
-> Commerce V2: sales:integration:utmify
-> services-sale-integrations: UtmifySender
-> POST /api-credentials/orders da UTMify
```

## Componentes e referências

| Componente | Host de produção | Diretório de produção | Branch de deploy | Commit | Papel nesta entrega |
| --- | --- | --- | --- | --- | --- |
| `services-commerce-v2` | `144.126.149.57` | `/opt/lowify/services/service-commerce-v2` | `feat/utmify-refunded-events` | Pendente de commit e publicação da branch | Libera `refunded` na configuração de eventos da UTMify. |
| `services-sale-integrations` | `147.93.180.183` | `/opt/lowify/services/services-sale-integrations` | `feat/utmify-refunded-events` | Pendente de commit e publicação da branch | Transforma o evento no payload aceito pela UTMify. |

Os commits ainda não existem no remoto no momento da preparação deste documento. Não iniciar o deploy antes de criar os commits, enviar as duas branches a `origin` e registrar os SHAs aprovados nesta tabela.

## Alterações incluídas

- O Commerce V2 passa a despachar `refunded` para a fila `sales:integration:utmify`, quando houver integração UTMify válida para a venda.
- O `UtmifySender` converte o evento em `status: refunded`.
- Para o reembolso, o sender mantém `approvedDate` a partir de `sale.approved_at` e preenche `refundedAt` a partir de `triggered_at` do evento.
- Para os eventos já existentes (`pending` e `paid`), `refundedAt` é enviado como `null`.
- Há teste focado do sender para o payload de reembolso.

O produtor do reembolso já inclui `triggered_at` em `sales:events:refunded`; não há novo campo, migration ou mudança de schema no Commerce.

## Pré-requisitos

1. Criar e publicar as duas branches indicadas na tabela, registrar seus commits e atualizar esta documentação com os SHAs antes da execução.
2. Confirmar que as árvores Git na VPS estão limpas, que `origin` aponta para os repositórios oficiais e registrar os commits atualmente publicados para rollback.
3. Preservar as variáveis atuais `SALES_INTEGRATION_UTMIFY_QUEUE`, `SALE_INTEGRATIONS_UTMIFY_QUEUE`, `SALE_INTEGRATIONS_UTMIFY_PROCESS_ENABLED`, `SALE_INTEGRATIONS_UTMIFY_ENDPOINT` e o token de cada integração. Não imprimir nem alterar valores de segredos.
4. Confirmar que ambos os serviços usam o mesmo Redis configurado e que as duas variáveis de fila apontam para `sales:integration:utmify` (ou para o mesmo nome customizado aprovado).
5. Confirmar que há uma venda de teste paga, com integração UTMify ativa, que possa ser reembolsada de forma controlada.

## Banco de dados

Não há migration, DDL, DML ou alteração de schema.

## Sequência de deploy

Modo de rebuild: incremental.

Publicar primeiro o consumidor (`services-sale-integrations`) e, em seguida, o produtor/despachante (`services-commerce-v2`). Assim, quando o Commerce começar a liberar reembolsos para a fila UTMify, o consumidor já reconhecerá o evento.

### 1. Atualizar `services-sale-integrations` em `147.93.180.183`

```bash
cd /opt/lowify/services/services-sale-integrations
git status --short
git fetch origin --prune
git switch feat/utmify-refunded-events
git pull --ff-only origin feat/utmify-refunded-events
git rev-parse --short HEAD
docker compose up -d --build service-sale-integrations
docker compose ps
```

Confirmar que o SHA exibido corresponde ao commit aprovado e que o processo `sale_integrations_utmify` iniciou sem erro. Não consumir, apagar, reordenar ou reenfileirar mensagens da fila durante esta etapa.

### 2. Atualizar `services-commerce-v2` em `144.126.149.57`

```bash
cd /opt/lowify/services/service-commerce-v2
git status --short
git fetch origin --prune
git switch feat/utmify-refunded-events
git pull --ff-only origin feat/utmify-refunded-events
git rev-parse --short HEAD
docker compose up -d --build service-commerce-v2
docker compose ps
```

Confirmar que o SHA exibido corresponde ao commit aprovado e que o processo de eventos de venda iniciou sem falhas de Redis ou de configuração.

## Validação pós-deploy

1. No ambiente de teste aprovado, abra uma venda paga cujo produto tenha uma integração UTMify ativa e solicite um reembolso total pelo fluxo normal da plataforma.
   - Resultado esperado: o reembolso é concluído normalmente para a venda, sem erro visível ao operador.
2. Abra a mesma venda no painel da UTMify.
   - Resultado esperado: ela aparece como reembolsada; não é criado um segundo pedido.
3. Confira as datas exibidas na UTMify.
   - Resultado esperado: a aprovação permanece associada à data original de pagamento e a data de reembolso corresponde ao momento da confirmação do reembolso.
4. Faça uma venda Pix de teste e uma venda de cartão de teste com a mesma configuração UTMify, sem reembolso.
   - Resultado esperado: as vendas continuam chegando como pendente/paga e não são mostradas como reembolsadas.
5. Como conferência técnica opcional, verificar os logs dos dois serviços.
   - Resultado esperado: não há erro de evento não suportado nem resposta HTTP de validação da UTMify para `refundedAt`.
6. Se o reembolso não aparecer na UTMify, registrar o horário, `sale_id`, `order_id` e a resposta recebida; não apagar, consumir manualmente ou reenfileirar mensagens para forçar o resultado.

## Rollback

1. Reverter primeiro `services-commerce-v2` ao commit anterior registrado e reconstruir seu container. Isso interrompe a emissão de novos eventos `refunded` para a UTMify.

   ```bash
   cd /opt/lowify/services/service-commerce-v2
   git fetch origin --prune
   git switch main
   git pull --ff-only origin main
   docker compose up -d --build service-commerce-v2
   docker compose ps
   ```

2. Depois, reverter `services-sale-integrations` ao commit anterior registrado e reconstruir o consumidor.

   ```bash
   cd /opt/lowify/services/services-sale-integrations
   git fetch origin --prune
   git switch master
   git pull --ff-only origin master
   docker compose up -d --build service-sale-integrations
   docker compose ps
   ```

3. Não apagar vendas, registros de dispatch, configurações, tokens ou mensagens de Redis. O rollback somente restaura o comportamento do código para novos consumos.

## Fora de escopo

- Reenvio automático de reembolsos históricos.
- Alteração de endpoint, token, targets de integração ou configuração de Redis.
- Alteração do fluxo financeiro, status da venda, banco de dados ou refund parcial.
