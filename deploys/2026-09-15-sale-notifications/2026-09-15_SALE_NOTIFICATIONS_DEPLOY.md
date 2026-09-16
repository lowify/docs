# Deploy — Comunicações de venda

## Objetivo

Disponibilizar as comunicações oficiais de venda da Lowify:

- entrega pós-pagamento por e-mail e, quando configurado, WhatsApp Meta;
- recuperação de venda pendente (RDC) por e-mail e WhatsApp Meta;
- cobrança por créditos de comunicação, com fallback opcional para saldo disponível fora do Checkout Transparente;
- compra de créditos por PIX ou saldo da Wallet;
- visualização, reenvio e histórico no Dashboard Seller;
- descontinuação da integração legada de WhatsApp/Evolution no Dashboard.

Este é um deploy coordenado: schema, consumidores, callbacks e interfaces entram como uma única entrega.

## Repositórios, branches e containers

Todos os repositórios abaixo devem apontar para `feat/sale-notifications`, salvo decisão explícita de integrar a feature em outra branch de release. Registrar o SHA real antes do deploy; não use commits fixos deste documento como fonte de verdade.

| Repositório | Diretório na VPS | Container/efeito | Build necessário |
| --- | --- | --- | --- |
| `services-account` | `/opt/lowify/services/services-account` | Account | Sim |
| `services-wallet` | `/opt/lowify/services/services-wallet` | Wallet | Sim |
| `services-banking-v2` | `/opt/lowify/services/services-banking-v2` | Banking V2 e consumer PIX | Sim |
| `services-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | Commerce V2 e processos de entrega/RDC | Sim |
| `services-notification` | `/opt/lowify/services/services-notification` | Notification, sender Meta/e-mail | Sim |
| `edge-webhook` | `/opt/lowify/edge/edge-webhook` | Webhooks Meta, SendGrid e Mailtrap | Sim |
| `edge-public-api` | `/opt/lowify/edge/edge-public-api` | API pública e autorização | Sim |
| `edge-gateway` | `/opt/lowify/edge/edge-gateway` | Proxy autenticado do Dashboard | Sim |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | telas, modais e integração Evolution desativada | Não; apenas pull/PHP-FPM conforme operação atual |

`services-banking` legado não participa da criação de créditos de comunicação. Não alterá-lo neste deploy sem uma necessidade independente.

## Ordem segura de disponibilização

```text
SQL manual
  → schema manual lowify
  → SQL manual de Banking V2 e Notification
  → consumidores: Wallet, Banking V2, Notification, Commerce V2
  → edges: webhook, public-api, gateway
  → Dashboard Seller
  → configurações já preparadas no ambiente
  → validação controlada
  → desativação/limpeza da Evolution
```

O ponto crítico é disponibilizar consumidores antes de produtores:

1. Wallet antes de Commerce, pois recebe holds/consume/release.
2. Banking V2 antes de liberar compra PIX no Dashboard, pois consome `banking:communication-credit-purchases:create`.
3. Notification e Commerce antes de ativar regras de produto, pois Commerce publica e consome outcomes.
4. Edge Webhook antes de tráfego Meta/SendGrid/Mailtrap, para que callbacks não sejam perdidos.

## 1. SQL manual

Todos os SQLs necessários acompanham este documento, na mesma pasta. Não usar mais os SQLs incrementais do plano: os arquivos abaixo são a fonte operacional única deste deploy.

| Banco | Aplicação | Conferência posterior | Seed |
| --- | --- | --- | --- |
| `lowify` | `LOWIFY_DEPLOY.sql` | `LOWIFY_CHECK.sql` | `LOWIFY_SEEDS.sql` |
| Banking V2 | `BANKING_V2_DEPLOY.sql` | `BANKING_V2_CHECK.sql` | — |

Executar nesta ordem: `LOWIFY_DEPLOY.sql`, `LOWIFY_SEEDS.sql`, `LOWIFY_CHECK.sql`, `BANKING_V2_DEPLOY.sql` e `BANKING_V2_CHECK.sql`. Cada arquivo deve ser executado integralmente, no banco indicado, e sua saída anexada à evidência do deploy.

### 1.1 Conteúdo do banco `lowify`

Aplicar, se ainda ausentes:

- `product_sale_delivery_rules`;
- `product_sale_recovery_rules`;
- `product_sale_recovery_rule_steps`;
- `product_sale_recovery_rule_step_channels`;
- `sale_delivery_attempts`;
- ampliação de `sale_recovery_dispatches`, inclusive `channel`, owner e funding;
- `sale_recovery_dispatch_events`;
- ampliação de `sales_delivery`, inclusive tentativa, owner, deadlines e funding.

Não criar seed ou regra individual para produtos/afiliações existentes neste deploy. A ausência de regra faz todos começarem com o mesmo comportamento efetivo definido pela configuração global; as regras relacionais passam a existir somente quando o produtor ou afiliado salvar uma configuração própria.

### 1.2 Account

`user_system_vars` é uma tabela legada e não recebe alteração de schema neste deploy. `LOWIFY_SEEDS.sql` insere as quatro chaves em `system_vars`:

- `sale_notifications_feature_enabled`;
- `sale_delivery_whatsapp_enabled`;
- `sale_delivery_whatsapp_unit_price`;
- `sale_recovery_unit_price`.

`sale_notifications_allow_seller_balance` **não** deve ser incluída em `system_vars`: ela é preferência por usuário e o default efetivo no Account é `true`.

As quatro chaves globais entram habilitadas, com custo unitário R$ 0,35, em `LOWIFY_SEEDS.sql`. Todo seller começa com o uso de saldo disponível permitido: não criar override em `user_system_vars`.

### 1.3 Wallet

Aplicar, se ainda ausentes:

- `seller_balance_holds`;
- tipos `extract_types` 35 e 36;
- `communication_credit_packages`;
- `communication_credit_balances`;
- `communication_credit_purchases`;
- `communication_credit_entries`;
- `communication_credit_alerts`;
- `communication_credit_outbox`.

`LOWIFY_SEEDS.sql` cadastra os pacotes comerciais aprovados:

| Valor pago | Bônus |
| --- | --- |
| R$ 50,00 | R$ 0,00 |
| R$ 100,00 | R$ 0,00 |
| R$ 500,00 | R$ 20,00 |
| R$ 1.000,00 | R$ 40,00 |

O seed é idempotente. Pacotes fora da lista não são removidos para preservar histórico; podem ser desativados posteriormente com uma decisão comercial explícita.

### 1.4 Banking V2 e Notification

Executar manualmente apenas o DDL de Banking V2 disponibilizado neste pacote. Notification continua usando o processo normal de migrations do próprio container.

**Banking V2**

O conteúdo executável está em `BANKING_V2_DEPLOY.sql`.

O Banking V2 se comunica com a Wallet a partir deste update. O consumer lê `banking:communication-credit-purchases:create`, valida a assinatura, cria ou reaproveita o PIX com `purpose = communication_credit_topup` e chama a Wallet para:

1. registrar `payment_reference_id` e dados do PIX criado, mudando a compra para `pending`;
2. registrar `pix_creation_failed` após erro terminal;
3. confirmar o PIX pago, para que a Wallet credite `amount + bonus` de forma idempotente.

**Notification**

- executar a migration usual do próprio container após subir a atualização; ela inclui correlation types, templates, tracking de e-mail/WhatsApp e os status `SENT_PENDING` e `DELIVERED`.

## 2. Variáveis de ambiente

Esta seção relaciona **somente envs novas ou cujo valor precisa mudar neste deploy**. Tokens, segredos, URLs internas e credenciais já existentes não devem ser recriados nem repetidos no roteiro: o deploy apenas os reutiliza.

Com os defaults abaixo aplicados no código, não há nova env obrigatória para Wallet, Banking V2, Commerce V2, Notification, Edge Webhook, Public API ou Gateway.

| Área | Default de código desta feature |
| --- | --- |
| Wallet | outbox, expiração e filas operacionais |
| Banking V2 | consumer PIX habilitado; fila `banking:communication-credit-purchases:create`; provider `efi_bank`; PIX válido por `7200` segundos |
| Commerce V2 | timeout de status `180` segundos; hold de `600` segundos; filas `sales:notification:results`, `sales:recovery:schedule` e `sales:recovery:dispatch` |
| Notification | fila `sales:notification:results`; `sendgrid` como provider primário e `mailtrap` como secundário |

O link de recuperação usa, por default, `https://pay.lowify.com.br`, resultando em `/rdc?cod={order}`. Portanto, `SALE_RECOVERY_RDC_BASE_URL` não precisa ser declarada na env.

### 2.1 Única conferência de env

No `services-banking-v2`, confirmar a presença dos três valores já usados pelo cliente interno da Wallet:

- `SERVICES_WALLET_URL`;
- `WALLET_SERVICE_AUTHORIZATION`;
- `WALLET_SIGNATURE_SECRET`.

Se algum estiver ausente, declará-lo no arquivo de ambiente do Banking V2 com o endpoint interno, token e segredo já aceitos pela Wallet. Não criar valores novos: reutilizar os valores definidos para a integração interna Wallet. Todas as demais envs desta feature usam inicialmente os defaults de código.

## 3. Atualização dos containers

Em cada etapa, registrar o SHA retornado por `git rev-parse --short HEAD`, a saída de `docker compose ps` e as últimas linhas de `docker compose logs --tail=50`. Só avançar se o container estiver `Up` e não houver erro de inicialização.

1. **Wallet**

   ```bash
   cd /opt/lowify/services/services-wallet
   git fetch origin --prune
   git switch feat/sale-notifications
   git pull --ff-only origin feat/sale-notifications
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=50
   ```

   Resultado esperado: API e processos de outbox/expiração iniciados, sem erro de schema ou Redis.

2. **Banking V2** — executar antes `BANKING_V2_DEPLOY.sql` e confirmar a env Wallet da seção 2.1.

   ```bash
   cd /opt/lowify/services/services-banking-v2
   git fetch origin --prune
   git switch feat/sale-notifications
   git pull --ff-only origin feat/sale-notifications
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=50
   ```

   Resultado esperado: consumer de recarga inicia sem erro de assinatura/Wallet e fica apto a consumir `banking:communication-credit-purchases:create`.

3. **Notification** — após a atualização, rodar a migration usual do container.

   ```bash
   cd /opt/lowify/services/services-notification
   git fetch origin --prune
   git switch feat/sale-notifications
   git pull --ff-only origin feat/sale-notifications
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose exec services-notifications php bin/hyperf.php migrate
   docker compose ps
   docker compose logs --tail=50
   ```

   Resultado esperado: migrations concluídas e sender/processos de outcome iniciados sem falha de template ou provider.

4. **Commerce V2**

   ```bash
   cd /opt/lowify/services/service-commerce-v2
   git fetch origin --prune
   git switch feat/sale-notifications
   git pull --ff-only origin feat/sale-notifications
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=50
   ```

   Resultado esperado: scheduler RDC, dispatch e consumidor de outcomes iniciados sem erro de contrato com Wallet/Notification.

5. **Account**

   ```bash
   cd /opt/lowify/services/services-account
   git fetch origin --prune
   git switch feat/sale-notifications
   git pull --ff-only origin feat/sale-notifications
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=50
   ```

   Resultado esperado: leitura de `system_vars` e preferências por usuário sem erro.

6. **Edge Webhook**

   ```bash
   cd /opt/lowify/edge/edge-webhook
   git fetch origin --prune
   git switch feat/sale-notifications
   git pull --ff-only origin feat/sale-notifications
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=50
   ```

   Resultado esperado: container `Up` e callbacks de Meta, SendGrid e Mailtrap aptos a registrar outcomes.

7. **Edge Public API**

   ```bash
   cd /opt/lowify/edge/edge-public-api
   git fetch origin --prune
   git switch feat/sale-notifications
   git pull --ff-only origin feat/sale-notifications
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=50
   ```

   Resultado esperado: container `Up` e rotas autenticadas de produto, crédito, recarga, status e reenvio disponíveis para o Gateway.

8. **Edge Gateway**

   ```bash
   cd /opt/lowify/edge/edge-gateway
   git fetch origin --prune
   git switch feat/sale-notifications
   git pull --ff-only origin feat/sale-notifications
   git rev-parse --short HEAD
   docker compose up -d --build
   docker compose ps
   docker compose logs --tail=50
   ```

   Resultado esperado: container `Up` e Dashboard apto a acessar as novas rotas sem falha de autenticação.

9. **Dashboard Seller** — não executar build.

   ```bash
   cd /opt/lowify/front/dashboard-seller
   git fetch origin --prune
   git switch feat/sale-notifications
   git pull --ff-only origin feat/sale-notifications
   git rev-parse --short HEAD
   ```

   Resultado esperado: páginas de produto, créditos, extrato, detalhes de venda e notificações carregam sem erro PHP/JavaScript.

## 4. Ativação e validação funcional

As quatro `system_vars` já entram configuradas pelo SQL manual: feature e entrega WhatsApp habilitadas e ambos os preços em R$ 0,35.

Executar em homologação, com um seller de teste, na ordem:

1. **Entrega cobrada do saldo disponível**

   Deixar o seller sem créditos de comunicação, manter a preferência de usar saldo disponível habilitada e confirmar uma venda própria com entrega WhatsApp ativa. A mensagem deve ser aceita pelo provider, o valor deve ser bloqueado no saldo disponível e consumido uma única vez em `sent_to_provider`.

2. **Compra de pacote de créditos**

   No Dashboard, abrir Créditos de comunicação, selecionar um pacote e gerar o PIX. Após o pagamento, a compra deve mudar de `creating` para `pending` e depois `paid`; o saldo de créditos deve receber `amount + bonus`.

3. **Configuração de RDC em produto**

   Na edição de um produto, ativar uma ou duas etapas de recuperação, selecionar e-mail e/ou WhatsApp e salvar. Ao reabrir o produto, a configuração e os custos de R$ 0,35 por envio devem permanecer visíveis.

4. **Disparo do RDC configurado**

   Criar uma venda `pending` para o produto configurado. Confirmar que o RDC é agendado dentro da janela máxima de duas horas e que a etapa configurada é enviada no horário escolhido, com link `/rdc?cod={order}`. Quando o envio for aceito pelo provider, validar o bloqueio/consumo da fonte financeira aplicável e o registro no extrato e timeline da venda.

## 5. Corte da Evolution

O Dashboard Seller já remove o card/atalho e devolve `410` nos endpoints legados:

- `integracoes_whatsapp.php`;
- `integracoes_whatsapp_ajax.php`;
- `integracoes_whatsapp_process.php`;
- `api/integrations/whatsapp/instance_configs_update.php`.

Depois de validar o caminho oficial, executar primeiro em modo de inspeção:

```bash
cd /opt/lowify/front/dashboard-seller
docker compose exec front-dashboard-seller php scripts/evolution/disconnect_all_lowify_instances.php
```

Com a lista aprovada, executar a limpeza irreversível das instâncias `lowify-*`:

```bash
cd /opt/lowify/front/dashboard-seller
docker compose exec front-dashboard-seller php scripts/evolution/disconnect_all_lowify_instances.php --execute
```

O script deve rodar dentro de `front-dashboard-seller`: ele faz logout, remove a instância na Evolution e somente então apaga o registro correspondente em `tbl_instancia`. Não executar antes da validação oficial e não executar contra instâncias que não tenham prefixo `lowify-`.

## Observabilidade e consultas pós-deploy

Registrar e monitorar por `sale_delivery.id`, `sale_delivery_attempt_id`, dispatch RDC, `owner_user_id` e UUID de recarga.

```sql
SELECT id, sale_id, type, status, funding_source, funding_status, unit_price, error, created_at, updated_at
FROM sales_delivery
ORDER BY id DESC
LIMIT 50;

SELECT id, sale_id, stage, channel, status, funding_source, funding_status, unit_price, skip_reason, scheduled_for
FROM sale_recovery_dispatches
ORDER BY id DESC
LIMIT 50;

SELECT owner_user_id, balance, blocked_amount, balance - blocked_amount AS available
FROM communication_credit_balances
ORDER BY updated_at DESC
LIMIT 50;

SELECT id, uuid, owner_user_id, amount_snapshot, bonus_snapshot, payment_method, status, error_code, created_at, paid_at
FROM communication_credit_purchases
ORDER BY id DESC
LIMIT 50;
```

Monitorar especialmente:

- `pix_creation_failed` (provider/configuração Banking);
- `communication_credit_unavailable` e `communication_funding_unavailable`;
- holds em estado `held` após o prazo;
- `timed_out` somente em entregas que nunca foram aceitas pelo provider;
- callbacks Meta/e-mail rejeitados por assinatura;
- falhas de correlação entre Notification, Webhook e Commerce.

## Rollback

1. **Interromper novas ativações:** alterar `sale_notifications_feature_enabled` e `sale_delivery_whatsapp_enabled` para `0` em `system_vars`.
2. Preservar dados, compras PIX, holds, eventos e filas como evidência. Não apagar linhas nem limpar Redis.
3. Se um consumidor falhar, parar o componente produtor correspondente antes de reverter código. Exemplo: interromper Wallet/Banking antes de expor nova recarga PIX; interromper Commerce antes de ativar novas regras.
4. Reverter código para a revisão anterior aprovada e reconstruir somente o container afetado.
5. Não executar rollback de DDL automático. Para qualquer reversão de schema, preparar plano específico após avaliar dados criados e FKs.
6. A desconexão Evolution não é automaticamente reversível: após executar `--execute`, uma eventual reativação exigirá novo provisionamento de instâncias e não deve ser feita como parte do rollback desta feature.
