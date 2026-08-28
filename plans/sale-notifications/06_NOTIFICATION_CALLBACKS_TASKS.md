# Fase 6 — Notification: envio, callbacks e alertas

## Fila genérica de resultado

Evoluir `SaleDeliveryResultQueueService` para publicar em `sales:notification:results`:

```json
{
  "context": "sale_delivery | sale_recovery",
  "subject_id": 123,
  "channel": "email | whatsapp",
  "reference_type": "email_single | whatsapp_meta",
  "reference_id": 456,
  "status": "sent_to_provider | success | fail | read",
  "error": null
}
```

`subject_id` é `sales_delivery.id` na entrega e `sale_recovery_dispatches.id` no RDC.

## Arquivos e pendências

| Arquivo/camada | Pendência |
| --- | --- |
| `EmailSenderService` | Aceitar contexto/correlação de entrega e RDC; publicar envio/falha sem preço. |
| `WhatsappMetaSenderService` | Receber `sales_delivery.id` ou dispatch nos params; publicar resultado sem aplicar fallback próprio. |
| `WhatsappMetaDeliveryStatusQueueProcess` | Publicar callback genérico pelo subject; não reenviar secondary em confirmação tardia. |
| `WhatsappMetaDeliveryEmailService` | Substituir constantes SendGrid/Mailtrap por providers `primary`/`secondary` recebidos do fluxo. |
| Processos de e-mail | Publicar resultado sem duplicar e-mail de timeout. |
| Migrations/templates | Criar Twig RDC, templates Meta e ajustar schema de correlation se necessário. |
| Alerta de créditos | Consumir pedido idempotente da Wallet e enviar e-mail + WhatsApp ao owner. |

## Regras

- Notification não consulta Wallet, preço ou saldo.
- Admin gratuito é definido por Commerce; Notification apenas envia os canais solicitados.
- Reenvio admin não possui fallback automático.
- Para entrega automática/seller/colaborador, Commerce escolhe primary/secondary pelo status Meta.
- RDC continua sem retry/fallback automático.

## Testes

- Callback Meta repetido, fora de ordem e tardio.
- Correlação de entrega por `sales_delivery.id` e de RDC por dispatch.
- Falha do sender antes de ID externo.
- Alerta de crédito deduplicado recebido mais de uma vez.
