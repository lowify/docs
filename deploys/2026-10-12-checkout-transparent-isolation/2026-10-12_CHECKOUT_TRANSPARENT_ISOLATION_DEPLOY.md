# Deploy — Isolamento de e-mails e identidade do Checkout Transparente

## Objetivo

Publicar o fluxo isolado do Checkout Transparente (CT): a compra continua em `checkout.<domínio>`, enquanto os e-mails de entrega e recuperação podem usar templates, assunto e remetente próprios via Resend. A Área de Membros mantém os canais de atendimento do seller e oculta somente o Chat Lowify em acessos CT.

Ficam fora deste deploy: novo domínio, nova zona Cloudflare, alteração de banco do Commerce e alteração do CT API/worker.

## Componentes e referências

| Repositório | Diretório de produção | Branch |
| --- | --- | --- |
| `services-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `feat/checkout-transparent-isolation` |
| `services-notification` | `/opt/lowify/services/services-notifications` | `feat/checkout-transparent-isolation` |
| `edge-webhook` | `/opt/lowify/edge/edge-webhook` | `feat/checkout-transparent-isolation` |
| `front-checkout` | `/opt/lowify/front/front-checkout` | `feat/checkout-transparent-isolation` |
| `front-member-area` | `/opt/lowify/front/front-member-area` | `feat/checkout-transparent-isolation` |

Todos os demais repositórios permanecem como estão.

## Alterações incluídas

- O Commerce identifica venda CT e publica `delivery_email_mode=transparent`; não escolhe provider, template ou assunto CT.
- O Notifications aplica opcionalmente overrides de provider, template e assunto para eventos com esse modo. Se os overrides estiverem vazios, preserva o provider, template e assunto padrão.
- `resend_transparent` usa as credenciais SMTP do Resend e um remetente exclusivo para CT.
- Entrega, reenvio, timeout e recuperação carregam o marcador CT; recuperação usa a URL de recuperação do host `checkout`.
- O Checkout remove elementos públicos não desejados do CT sem criar novo site.
- A Área de Membros preserva e-mail, WhatsApp, Instagram e Telegram do seller; somente o link para Chat Lowify não aparece em CT.

Contrato assíncrono: Commerce publica e-mails em `stream:notifications:email_single`; Notifications cria o `EmailSingle` e o envia. O webhook Resend já publicado converte os retornos de entrega para o fluxo normal de status. Não limpar nem consumir manualmente filas/streams durante a operação.

## Pré-requisitos

1. Confirmar que o sender do domínio de produção destinado ao CT está verificado no painel Resend.
2. Confirmar que `https://webhook.lowify.com.br/api/resend` está cadastrado nas duas contas Resend, com eventos de entrega, abertura, falha, bounce e supressão.
3. Antes de ativar o override CT, registrar no `.env` de `/opt/lowify/services/services-notifications` as credenciais SMTP Resend já aprovadas e o remetente CT. Nunca registrar os valores dos segredos neste documento.
4. Para este deploy inicial, copiar os valores vazios de [`env/services-notifications/DEPLOY_DEFAULT.env`](env/services-notifications/DEPLOY_DEFAULT.env) para o `.env` de `services-notifications`. Isso preserva o provider, template, assunto e URL padrão para CT.

5. As variáveis SMTP e de sender abaixo podem ser provisionadas no mesmo momento, mas não ativam o CT isolado enquanto os `CHECKOUT_TRANSPARENT_*` permanecerem vazios.

```dotenv
RESEND_MAIL_DRIVER=smtp
RESEND_MAIL_HOST=smtp.resend.com
RESEND_MAIL_PORT=465
RESEND_MAIL_USERNAME=resend
RESEND_MAIL_PASSWORD=<segredo-existente>
RESEND_MAIL_SMTP_SECURE=ssl
RESEND_TRANSPARENT_MAIL_PASSWORD=<segredo-resend-ct>
RESEND_TRANSPARENT_MAIL_FROM=<sender-ct-verificado>
RESEND_TRANSPARENT_MAIL_FROM_NAME=Lowify

```

6. No `.env` do `edge-webhook`, configurar uma chave de assinatura por conta Resend:

```dotenv
RESEND_WEBHOOK_SIGNING_SECRET=<segredo-de-assinatura-do-webhook>
RESEND_TRANSPARENT_WEBHOOK_SIGNING_SECRET=<segredo-de-assinatura-do-webhook-ct>
RESEND_WEBHOOK_SIGNATURE_ACTIVE=true
```

7. Confirmar que as migrations anteriores do Notifications estão aplicadas e que os templates CT poderão ser criados pela migration listada abaixo.

## Banco de dados

Não há migration no Commerce ou nos fronts. Em `services-notifications`, aplicar uma vez a migration `2026_10_07_000058_seed_checkout_transparent_buyer_email_templates.php`, que registra os templates de entrega e recuperação CT. Ela não altera dados de venda nem remove templates existentes.

## Sequência de deploy

Modo de rebuild: incremental. Interromper se qualquer repositório participante tiver árvore Git suja, origem diferente ou se o commit final não corresponder à tabela.

1. Atualizar e construir o `edge-webhook` primeiro, para que a mesma URL aceite callbacks das duas contas Resend:

```bash
cd /opt/lowify/edge/edge-webhook
git fetch origin --prune
git switch feat/checkout-transparent-isolation
git pull --ff-only origin feat/checkout-transparent-isolation
docker compose up -d --build
docker compose ps
```

2. Atualizar e construir o Notifications, pois ele passa a entender os overrides e contém a migration:

```bash
cd /opt/lowify/services/services-notifications
git switch feat/checkout-transparent-isolation
git pull --ff-only origin feat/checkout-transparent-isolation
git rev-parse HEAD
docker compose run --rm services-notifications php bin/hyperf.php migrate --force
docker compose up -d --build
docker compose ps
```

3. Atualizar e construir o Commerce V2:

```bash
cd /opt/lowify/services/service-commerce-v2
git switch feat/checkout-transparent-isolation
git pull --ff-only origin feat/checkout-transparent-isolation
git rev-parse HEAD
docker compose up -d --build
docker compose ps
```

4. Atualizar o Checkout. O código é montado no container, portanto não exige rebuild ou restart:

```bash
cd /opt/lowify/front/front-checkout
git switch feat/checkout-transparent-isolation
git pull --ff-only origin feat/checkout-transparent-isolation
git rev-parse HEAD
```

5. Atualizar a Área de Membros. O código é montado no container, portanto não exige rebuild ou restart:

```bash
cd /opt/lowify/front/front-member-area
git switch feat/checkout-transparent-isolation
git pull --ff-only origin feat/checkout-transparent-isolation
git rev-parse HEAD
```

6. Confirmar que os cinco repositórios estão na branch declarada. Não ativar os `CHECKOUT_TRANSPARENT_*` nesta publicação inicial.

## Ativação posterior do override CT

Depois de validar sender, chave SMTP e templates no Resend, preencher no `.env` de `services-notifications`:

```dotenv
CHECKOUT_TRANSPARENT_EMAIL_PROVIDER=resend_transparent
CHECKOUT_TRANSPARENT_DELIVERY_EMAIL_CORRELATION_TYPE=sale_delivery_email_transparent
CHECKOUT_TRANSPARENT_DELIVERY_EMAIL_TITLE=Acesso ao seu conteúdo
CHECKOUT_TRANSPARENT_RECOVERY_EMAIL_CORRELATION_TYPE=sale_recovery_dispatch_transparent
CHECKOUT_TRANSPARENT_RECOVERY_EMAIL_TITLE=Finalize sua compra
CHECKOUT_TRANSPARENT_RECOVERY_RDC_BASE_URL=https://checkout.lowify.com.br
```

Em seguida, executar somente em `/opt/lowify/services/services-notifications`:

```bash
docker compose up -d --build
```

## Validação pós-deploy

1. Abra uma oferta CT em janela anônima. A página deve continuar no endereço `checkout` e exibir somente a identidade prevista do CT.
2. Faça uma compra Pix de teste com e-mail acessível. Confirme que o e-mail de entrega chega com o remetente CT e o conteúdo de acesso esperado.
3. Abra a Área de Membros pelo link entregue. Confirme que os canais do seller continuam disponíveis e que não há opção “Chat Lowify”.
4. Inicie uma recuperação de compra CT com um e-mail de teste. O link recebido deve abrir o checkout CT, não o host `pay`.
5. Faça uma compra normal equivalente. Ela deve continuar com provider, template, assunto e canais de atendimento padrão.
6. Como conferência técnica opcional, verifique no painel Resend que o evento de entrega foi aceito e no `edge-webhook` que o retorno foi recebido. Se o e-mail não chegar, desative somente os `CHECKOUT_TRANSPARENT_*` no Notifications e reconstrua esse serviço antes de investigar o sender.

## Rollback

1. Desativar primeiro os overrides CT no `.env` de `services-notifications` (deixar `CHECKOUT_TRANSPARENT_*` vazios) e reconstruir o serviço. Novos eventos CT voltam ao fluxo padrão sem apagar eventos já registrados.
2. Retornar os repositórios para a referência `main` aprovada, usando `git switch main` e `git pull --ff-only origin main`, na ordem: Checkout, Área de Membros, Commerce, Notifications e edge-webhook. Executar `docker compose up -d --build` no Commerce, Notifications e edge-webhook.
3. Não apagar `email_single`, templates, eventos de entrega, mensagens de Redis ou dados de venda. A migration de templates não exige rollback de dados para reverter o código.

## Riscos e decisão necessária

- A ativação depende de sender CT verificado no Resend. Sem isso, manter os overrides vazios e o fluxo padrão continuará ativo.
- As duas contas Resend devem usar a mesma URL de webhook, cada uma com seu próprio signing secret.
