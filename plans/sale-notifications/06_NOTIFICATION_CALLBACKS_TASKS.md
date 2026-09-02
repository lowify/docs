# Fase 6 — Notification: envio, callbacks e alertas

## Fila única de resultado

Evoluir `SaleDeliveryResultQueueService` para publicar o envelope novo na fila existente `sales:delivery:actions`:

```json
{
  "event_type": "notification_outcome",
  "reference_type": "sale_delivery | sale_recovery_dispatch",
  "reference_id": 123,
  "sale_id": 456,
  "channel": "email | whatsapp",
  "notification_reference_id": 789,
  "status": "sent_to_provider | sent_pending | delivered | success | fail | read",
  "error": null
}
```

`reference_id` é `sales_delivery.id` na entrega e `sale_recovery_dispatches.id` no RDC. O parser antigo permanece apenas enquanto houver mensagens pendentes no formato legado.

## Arquivos e pendências

| Arquivo/camada | Pendência |
| --- | --- |
| `EmailSenderService` | Aceitar contexto/correlação de entrega e RDC; publicar envio/falha sem preço. |
| `WhatsappMetaSenderService` | Remover metadados internos antes da chamada Meta e publicar resultado pelo subject comercial. |
| `WhatsappMetaDeliveryStatusQueueProcess` | Publicar callback genérico pelo subject; não reenviar secondary em confirmação tardia. |
| `WhatsappMetaDeliveryEmailService` | Receber o modo `primary`/`secondary` do Commerce e resolvê-lo pela env. |
| `config/autoload/sale_delivery.php` | Mapear `SALE_DELIVERY_EMAIL_PROVIDER_PRIMARY` (SendGrid) e `SALE_DELIVERY_EMAIL_PROVIDER_SECONDARY` (Mailtrap), sem nomes de provider fixos no serviço. |
| Processos de e-mail | Publicar resultado sem duplicar e-mail de timeout. |
| Migrations/templates | Criar Twig RDC, templates Meta e ajustar schema de correlation se necessário. |
| Alerta de créditos | Consumir pedido idempotente da Wallet e enviar e-mail + WhatsApp ao owner. |

## Regras

- Notification não consulta Wallet, preço ou saldo.
- Admin gratuito é definido por Commerce; Notification apenas envia os canais solicitados.
- Reenvio admin não possui fallback automático.
- Para entrega automática/seller/colaborador, Commerce escolhe primary/secondary pelo status Meta; Notification apenas mapeia o modo pela env e envia.
- RDC continua sem retry/fallback automático.
- RDC Meta usa dois templates oficiais, um por etapa, configurados por `SALE_RECOVERY_WHATSAPP_META_STAGE_1_EVENT` e `SALE_RECOVERY_WHATSAPP_META_STAGE_2_EVENT`.
- Meta: `sent_to_provider` é o aceite da API; webhook `sent` vira `sent_pending`; `delivered` ou `read` consome o crédito WhatsApp de forma idempotente; `fail` libera o hold.

## Testes

- Callback Meta repetido, fora de ordem e tardio.
- Correlação de entrega por `sales_delivery.id` e de RDC por dispatch.
- Falha do sender antes de ID externo.
- Alerta de crédito deduplicado recebido mais de uma vez.
