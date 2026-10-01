# Deploy — Administração de comunicações e Cashflow do Checkout Transparente

## Objetivo

Publicar a administração de templates de e-mail e fluxos WhatsApp Meta, o relatório de volumes de comunicação e a etapa **Cash In CT** do Relatório Cashflow. Esta entrega é exclusivamente administrativa; não altera o checkout, a criação de cobranças nem o processamento de pagamentos.

## Servidores e diretórios

| Servidor | Host | Repositório | Diretório |
| --- | --- | --- | --- |
| Checkout Transparente | `80.190.72.228` | `services-checkout-transparent-billing` | `/opt/lowify-ct/services/services-checkout-transparent-billing` |
| Checkout Transparente | `80.190.72.228` | `services-checkout-transparent-api` | `/opt/lowify-ct/services/services-checkout-transparent-api` |
| Principal | `144.126.149.57` | `services-notification` | `/opt/lowify/services/services-notifications` |
| Principal | `144.126.149.57` | `services-account` | `/opt/lowify/services/services-account` |
| Principal | `144.126.149.57` | `edge-public-api` | `/opt/lowify/edge/edge-public-api` |
| Principal | `144.126.149.57` | `edge-gateway` | `/opt/lowify/edge/edge-gateway` |
| Principal | `144.126.149.57` | `edge-webhook` | `/opt/lowify/edge/edge-webhook` |
| Principal | `144.126.149.57` | `dashboard-seller` | `/opt/lowify/front/dashboard-seller` |

## Componentes e referências

Todos os repositórios usam a branch `feat/checkout-transparent-billing-whatsapp-audit`.

| Repositório | Escopo |
| --- | --- |
| `services-checkout-transparent-billing` | Consulta interna de pagamentos quitados por período e índice de banco. |
| `services-checkout-transparent-api` | Proxy administrativo para o Billing. |
| `services-notification` | Configuração de providers, relatório de volumes agregado por data de envio e índice de `sent_at`. |
| `services-account` | Configurações de fluxo WhatsApp Meta ativas por padrão. |
| `edge-public-api` | Autorização e proxy do relatório CT e das rotas de comunicação. |
| `edge-gateway` | Roteamento administrativo ao Public API. |
| `edge-webhook` | Recebe os webhooks de status de entrega do Resend e os publica na fila de notificações. |
| `dashboard-seller` | Telas administrativas, relatório de comunicações e Cash In CT. |

## Alterações incluídas

- A aba administrativa de e-mail permite escolher provider por correlação ou manter `null`, que usa o provider padrão configurado.
- O relatório de comunicações exibe volumes diários de e-mail e WhatsApp, providers, templates e falhas. Os volumes são apurados pela data de envio (`sent_at`); mensagens que falharam antes de serem enviadas não entram no relatório.
- O relatório abre com os últimos 7 dias. Dias encerrados (até D-2) ficam em cache no Redis; uma consulta com mais de 31 dias ainda sem cache é recusada com a mensagem "Período muito grande", em vez de expirar.
- O `edge-webhook` passa a receber em `POST /api/resend` os eventos de entrega do Resend, valida a assinatura (Svix) e publica o evento na fila `notifications:email_delivery_status`, consumida pelo `EmailDeliveryStatusQueueProcess` do serviço de notificações, que atualiza o status de entrega do e-mail.
- O Cashflow busca pagamentos quitados do Billing CT por `paid_at`, separa-os em **Cash In CT** e incorpora seu lucro líquido aos cards consolidados.
- O fluxo administrativo é: Dashboard Seller → Gateway → Public API → CT API → CT Billing. O JWT é validado no Public API, que limita o relatório a permissões administrativas 1 e 2.

## Pré-requisitos

- As oito branches devem existir no remoto e estar aprovadas para produção.
- Os providers de e-mail estão configurados apenas em homologação; é obrigatório configurá-los em produção conforme a seção abaixo **antes da Etapa 1**, porque o `.env` é copiado para a imagem no build.

## Configuração de variáveis

Registre apenas os nomes aqui; os valores ficam no `.env` de cada servidor e nunca devem ser copiados para este documento.

### Painel do Resend

Antes de preencher as variáveis, no painel do Resend de produção:

1. Confirme que o domínio remetente de produção está verificado; ele será usado em `RESEND_MAIL_FROM`.
2. Crie uma API key de envio; ela será usada em `RESEND_MAIL_PASSWORD`.
3. Cadastre como endpoint de webhook a URL `https://webhook.lowify.com.br/api/resend`, marcando os eventos de e-mail (enviado, entregue, falha, bounce e reclamação). Copie o *signing secret* gerado para `RESEND_WEBHOOK_SIGNING_SECRET`.

### `services-notification` — `/opt/lowify/services/services-notifications/.env`

| Variável | Valor esperado |
| --- | --- |
| `RESEND_MAIL_DRIVER` | `smtp` |
| `RESEND_MAIL_HOST` | `smtp.resend.com` |
| `RESEND_MAIL_PORT` | `465` |
| `RESEND_MAIL_USERNAME` | `resend` |
| `RESEND_MAIL_PASSWORD` | API key de produção criada no Resend (`re_...`). |
| `RESEND_MAIL_FROM` | Endereço de um domínio verificado no Resend. |
| `RESEND_MAIL_FROM_NAME` | `Lowify` |
| `RESEND_MAIL_SMTP_SECURE` | `ssl` (porta 465) |

`MAIL_PROVIDER` define o provider padrão usado quando o template está como “Padrão configurado”. Mantenha o valor atual de produção; só altere para `resend` mediante decisão explícita de tornar o Resend o provider padrão.

### `edge-webhook` — `/opt/lowify/edge/edge-webhook/.env`

| Variável | Valor esperado |
| --- | --- |
| `RESEND_WEBHOOK_SIGNING_SECRET` | *Signing secret* (`whsec_...`) do endpoint cadastrado no painel do Resend. |
| `RESEND_WEBHOOK_SIGNATURE_ACTIVE` | `true` |

## Banco de dados

| Serviço | Alteração | Forma de aplicação |
| --- | --- | --- |
| `services-checkout-transparent-billing` | Migration `20260925000000_add_paid_period_index_to_billing_payments`: cria o índice `idx_billing_payments_status_paid_at`. | `migrate` na Etapa 2. |
| `services-notification` | Migration `2026_09_30_000059_add_sent_at_indexes_to_communication_tables`: cria `email_single_sent_at_index` e `whatsapp_meta_sent_at_index`. | `migrate` na Etapa 2. |
| `services-account` | Seed das chaves de fluxo WhatsApp Meta em `lowify.system_vars` (banco compartilhado), com valor `1` (ativas). | `INSERT` manual abaixo. |

1. As migrations são executadas depois de subir o container do respectivo serviço (o código da migration vem na imagem nova) e antes de validar as telas.
2. A criação dos índices em `email_single` e `whatsapp_meta` pode levar alguns instantes em tabelas grandes; execute em horário de menor volume de envios.
3. Não executar rollback automático. Os índices podem permanecer caso seja necessário reverter apenas a aplicação.

### Seed manual de `services-account`

Executar no banco compartilhado `lowify` (usado pelo `services-account` e pelos demais serviços principais), depois da Etapa 2. As chaves são novas nesta entrega e ainda não existem em produção.

1. Conferir antes: a consulta deve retornar **0 linhas**. Se retornar alguma, não execute o `INSERT` e registre o resultado.

   ```sql
   SELECT var_key, var_value
   FROM lowify.system_vars
   WHERE var_key IN (
       'whatsapp_account_review_approved_enabled',
       'whatsapp_account_review_resubmission_enabled',
       'whatsapp_cielo_card_approved_enabled',
       'whatsapp_cielo_card_rejected_enabled',
       'whatsapp_cielo_card_canceled_enabled',
       'whatsapp_credit_insufficient_enabled',
       'whatsapp_ct_billing_payment_available_enabled',
       'whatsapp_ct_billing_access_suspended_enabled',
       'whatsapp_audio_request_enabled'
   );
   ```

2. Inserir as chaves ativas:

   ```sql
   INSERT INTO lowify.system_vars (var_key, var_value, updated_at) VALUES
       ('whatsapp_account_review_approved_enabled', '1', NOW()),
       ('whatsapp_account_review_resubmission_enabled', '1', NOW()),
       ('whatsapp_cielo_card_approved_enabled', '1', NOW()),
       ('whatsapp_cielo_card_rejected_enabled', '1', NOW()),
       ('whatsapp_cielo_card_canceled_enabled', '1', NOW()),
       ('whatsapp_credit_insufficient_enabled', '1', NOW()),
       ('whatsapp_ct_billing_payment_available_enabled', '1', NOW()),
       ('whatsapp_ct_billing_access_suspended_enabled', '1', NOW()),
       ('whatsapp_audio_request_enabled', '1', NOW());
   ```

3. Repetir a consulta do passo 1: agora ela deve retornar **9 linhas**, todas com `var_value = '1'`.

## Sequência de deploy

Para cada repositório, executar `git status --porcelain=v1` antes de alterar a branch; se houver mudanças locais, interromper e preservar o estado.

### Etapa 1 — Atualizar código e construir imagens

Antes de começar, confirme que as variáveis da seção **Configuração de variáveis** já estão no `.env` de `services-notifications` e `edge-webhook`. Nesta etapa nenhum container é recriado. Executar em cada diretório abaixo:

```bash
git fetch origin --prune
git switch feat/checkout-transparent-billing-whatsapp-audit
git pull --ff-only origin feat/checkout-transparent-billing-whatsapp-audit
docker compose build
```

1. `80.190.72.228` — `/opt/lowify-ct/services/services-checkout-transparent-billing`
2. `80.190.72.228` — `/opt/lowify-ct/services/services-checkout-transparent-api`
3. `144.126.149.57` — `/opt/lowify/services/services-notifications`
4. `144.126.149.57` — `/opt/lowify/services/services-account`
5. `144.126.149.57` — `/opt/lowify/edge/edge-public-api`
6. `144.126.149.57` — `/opt/lowify/edge/edge-gateway`
7. `144.126.149.57` — `/opt/lowify/edge/edge-webhook`

Se algum build falhar, interrompa antes da Etapa 2; nenhum serviço em execução foi alterado.

### Etapa 2 — Subir os containers e executar migrations

Com todas as imagens construídas, subir na ordem abaixo.

1. `80.190.72.228` — Billing CT:

   ```bash
   cd /opt/lowify-ct/services/services-checkout-transparent-billing
   docker compose up -d
   docker compose exec -T app php bin/hyperf.php migrate --force
   ```

2. `80.190.72.228` — API CT:

   ```bash
   cd /opt/lowify-ct/services/services-checkout-transparent-api
   docker compose up -d
   ```

3. `144.126.149.57` — Notificações:

   ```bash
   cd /opt/lowify/services/services-notifications
   docker compose up -d
   docker compose exec -T services-notifications php bin/hyperf.php migrate --force
   ```

4. `144.126.149.57` — Contas:

   ```bash
   cd /opt/lowify/services/services-account
   docker compose up -d
   ```

   Em seguida, executar o **Seed manual de `services-account`** da seção Banco de dados.

5. `144.126.149.57` — Public API:

   ```bash
   cd /opt/lowify/edge/edge-public-api
   docker compose up -d
   ```

6. `144.126.149.57` — Gateway:

   ```bash
   cd /opt/lowify/edge/edge-gateway
   docker compose up -d
   ```

7. `144.126.149.57` — Webhook:

   ```bash
   cd /opt/lowify/edge/edge-webhook
   docker compose up -d
   ```

### Etapa 3 — Dashboard Seller

Por último, somente atualizar o código; não é necessário build nem recriar containers.

```bash
cd /opt/lowify/front/dashboard-seller
git fetch origin --prune
git switch feat/checkout-transparent-billing-whatsapp-audit
git pull --ff-only origin feat/checkout-transparent-billing-whatsapp-audit
```

## Validação pós-deploy

1. Faça login com um administrador e abra **Configurações → E-mail**. Confirme que a lista mostra apenas Correlação, provider e ação de salvar; selecione “Padrão configurado”, salve e recarregue a página. O valor escolhido deve continuar selecionado.
2. Abra **Relatório de comunicações**. A tela deve abrir com os últimos 7 dias e mostrar cards, gráfico diário, provider padrão, templates e falhas sem mensagem de erro.
3. Ainda no relatório, escolha um período de até 31 dias e clique em pesquisar. Os dados devem aparecer; a primeira consulta de um período pode demorar alguns segundos a mais que as seguintes.
4. Faça uma ação que envie um e-mail por um template configurado com o Resend (por exemplo, uma recuperação de senha para um e-mail de teste). Aguarde alguns minutos, abra o **Relatório de comunicações** com o dia de hoje e confirme que o envio aparece como entregue, e não apenas como enviado. Se ficar sem status de entrega, registre o horário; o webhook do Resend pode não estar chegando.
5. Abra **Relatório Cashflow**, pesquise um mês que tenha faturas CT quitadas e confirme a aba **Cash In CT**, com provider, método, quantidade, valor, taxas e lucro líquido.
6. Caso a tela mostre erro, interrompa a validação e registre horário, URL e mensagem apresentada; não limpe filas, cache ou dados para forçar o resultado.

## Rollback

1. Reverter em ordem de borda para origem: Dashboard, Webhook, Gateway, Public API, CT API, Billing, Notifications e Account.
2. Em cada repositório, selecionar a branch de produção anterior aprovada e reconstruir o respectivo container (no Dashboard, apenas trocar a branch).
3. Não fazer rollback das migrations nem remover os índices de Billing e Notifications durante uma reversão de aplicação. As chaves de WhatsApp gravadas em `system_vars` e as variáveis do Resend também devem ser preservadas; para parar de usar o Resend, basta voltar os templates para “Padrão configurado”. Dados de envio, cache e filas devem ser preservados.
