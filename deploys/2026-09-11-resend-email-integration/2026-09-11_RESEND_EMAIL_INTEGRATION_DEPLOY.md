# Deploy — integração de e-mail Resend

## Objetivo

Disponibilizar o Resend como provider SMTP do `services-notifications` e receber seus eventos de ciclo de vida no `edge-webhook`.

```text
Evento de e-mail -> services-notifications -> SMTP Resend
Resend -> POST /api/resend -> edge-webhook -> Redis
-> notifications:email_delivery_status -> services-notifications -> email_single
```

O envio usa SMTP. O callback é assinado por Svix e usa o corpo bruto da requisição.

## Componentes alterados

| Componente | Branch de deploy | Entrega |
| --- | --- | --- |
| `services-notifications` | `feat/resend-integration` | Provider SMTP `resend`, configuração e correlação pelo RFC `Message-ID`. |
| `edge-webhook` | `feat/resend-integration` | Endpoint, validação Svix, persistência, idempotência e normalização de eventos Resend. |

Não há migration, DDL, seed ou alteração de schema nesta entrega.

## Pré-requisitos

1. Criar uma API key de envio no Resend. A senha SMTP é a API key real; o texto `apikey` não é uma credencial válida.
2. Verificar no Resend o domínio do remetente configurado em `RESEND_MAIL_FROM` no arquivo `/opt/lowify/services/services-notifications/.env`.
3. Criar o webhook de saída do Resend para:

   ```text
   https://webhook.lowify.com.br/api/resend
   ```
4. Configurar o signing secret do webhook no arquivo `/opt/lowify/edge/edge-webhook/.env`. O valor começa com `whsec_`.
5. Configurar as variáveis abaixo nos arquivos indicados:

   ```dotenv
   # /opt/lowify/services/services-notifications/.env
   RESEND_MAIL_DRIVER=smtp
   RESEND_MAIL_HOST=smtp.resend.com
   RESEND_MAIL_PORT=465
   RESEND_MAIL_USERNAME=resend
   RESEND_MAIL_PASSWORD=<API key do Resend>
   RESEND_MAIL_FROM=<remetente de domínio verificado>
   RESEND_MAIL_FROM_NAME=<nome exibido>
   RESEND_MAIL_SMTP_SECURE=ssl

   # /opt/lowify/edge/edge-webhook/.env
   RESEND_WEBHOOK_SIGNING_SECRET=<secret Svix whsec_...>
   RESEND_WEBHOOK_SIGNATURE_ACTIVE=true
   ```

6. Configurar no painel do Resend os eventos `email.delivered`, `email.opened`, `email.bounced`, `email.failed` e `email.suppressed`. Os demais eventos recebidos permanecem auditáveis no raw webhook, mas não alteram o status de entrega.

## Sequência de deploy

Publicar primeiro o `edge-webhook` para que callbacks possam ser recebidos antes de ativar envios pelo novo provider.

### edge-webhook

```bash
cd /opt/lowify/edge/edge-webhook
git status --porcelain=v1
git fetch origin --prune
git switch feat/resend-integration
git pull --ff-only origin feat/resend-integration
docker compose up -d --build
docker compose ps
docker compose logs --tail=200 edge-webhook
```

Confirmar que `POST /api/resend` está registrado e que os dois workers de `webhook-processing` estão ativos.

### services-notifications

```bash
cd /opt/lowify/services/services-notifications
git status --porcelain=v1
git fetch origin --prune
git switch feat/resend-integration
git pull --ff-only origin feat/resend-integration
docker compose up -d --build
docker compose ps
docker compose logs --tail=200 services-notifications
```

Confirmar que os processos `email_single_stream`, `email_single_sender` e `email_delivery_status_queue` iniciaram.

Para selecionar o Resend em um envio específico, o produtor deve informar `data.provider = "resend"`. `MAIL_PROVIDER` continua sendo apenas o fallback quando o evento e o template não informam provider.

## Dados e filas

| Etapa | Persistência/fila | Regra |
| --- | --- | --- |
| Registro do envio | `services-notification.email_single` | O `external_id` guarda o RFC `Message-ID` retornado pelo SMTP. |
| Entrada do callback | `services-webhook.webhook_raws` | O `svix-id` é salvo como `external_event_id` e impede reprocessamento de retries. |
| Processamento no `edge-webhook` | `webhook-processing` | Dois workers consomem o job e publicam o status normalizado. |
| Retorno para `services-notifications` | `notifications:email_delivery_status` | O consumidor localiza `email_single.external_id`. |

Mapeamento aplicado:

| Evento Resend | Status interno | Erro, quando aplicável |
| --- | --- | --- |
| `email.delivered` | `SUCCESS` | — |
| `email.opened` | `READ` | — |
| `email.bounced` | `FAILED` | Classificado a partir do payload de bounce. |
| `email.failed` | `FAILED` | Classificado a partir de `failed.reason`. |
| `email.suppressed` | `FAILED` | `provider_suspended`. |

## Validação pós-deploy

1. Confirmar `GET /api/health` no `edge-webhook` com resposta de sucesso.
2. No painel Resend, usar o teste de webhook e confirmar `HTTP 200` no endpoint.
3. Enviar uma comunicação de homologação por meio do producer normal com `data.provider = "resend"`; não usar inserção manual direta como validação de produção.
4. Confirmar no `email_single` que o envio foi aceito e recebeu `external_id`.
5. Confirmar em `webhook_raws` que o callback tem `identifier = resend` e `status = success`.
6. Confirmar a atualização posterior de `delivery_status` no mesmo `email_single`.
7. Reexecutar o mesmo callback no painel Resend e confirmar que o `svix-id` existente é reconhecido como duplicado, sem criar nova linha raw ou novo efeito na fila.
8. Verificar logs e filas sem consumir, limpar ou reprocessar mensagens de produção.

## Rollback

1. Desativar o webhook Resend antes de retornar o `edge-webhook`, para não acumular retries em endpoint incompatível.
2. Retornar `services-notifications` e `edge-webhook` juntos à revisão anterior aprovada e recriar os dois containers.
3. Não apagar `webhook_raws`, `email_single`, tentativas de envio ou mensagens Redis como procedimento de rollback; esses dados são evidência operacional e podem ser necessários para auditoria.
4. Não usar `git reset --hard`, `push --force` ou limpeza de filas para desfazer a entrega.
