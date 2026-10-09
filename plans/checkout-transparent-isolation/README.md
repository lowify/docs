# Checkout Transparente — escopo atual

## Ambiente

`*.statuslive.site` é TST/homologação. Toda alteração de código, migration, Resend e tela deve ser validada nele antes de produção.

## Objetivo

O checkout transparente continua em `checkout.<domínio-do-ambiente>` e o normal em `pay.<domínio-do-ambiente>`. Não haverá novo domínio, namespace, Cloudflare zone ou site independente.

No CT, o comprador vê somente o logo Lowify. Rodapé textual, chat, links para páginas Lowify e chamadas para suporte/contato sem canal apresentado devem ficar ocultos. APIs, gateway, nomes internos, mídia existente e dados vistos apenas no DevTools permanecem como estão.

## E-mail CT

Entrega, recuperação e notificações de billing CT usam o provider `resend_transparent`. Ele reaproveita somente as credenciais SMTP do Resend, mas exige remetente próprio. Em TST, o remetente precisa ser uma caixa do domínio `statuslive` verificada no Resend. Produção recebe seu remetente próprio depois da aprovação em TST.

```dotenv
SALE_DELIVERY_TRANSPARENT_EMAIL_ENABLED=false
SALE_RECOVERY_TRANSPARENT_EMAIL_ENABLED=false
SALE_DELIVERY_EMAIL_PROVIDER_TRANSPARENT=resend_transparent
SALE_RECOVERY_EMAIL_TRANSPARENT_PROVIDER=resend_transparent
```

```dotenv
RESEND_MAIL_DRIVER=smtp
RESEND_MAIL_HOST=smtp.resend.com
RESEND_MAIL_PORT=465
RESEND_MAIL_USERNAME=resend
RESEND_MAIL_PASSWORD=<chave Resend no secret>
RESEND_MAIL_FROM=<remetente statuslive verificado>
RESEND_MAIL_FROM_NAME=Lowify
RESEND_MAIL_SMTP_SECURE=ssl
RESEND_TRANSPARENT_MAIL_FROM=<remetente statuslive verificado>
RESEND_TRANSPARENT_MAIL_FROM_NAME=
```

Não versionar a chave. Em 07/10/2026, a API do Resend respondeu HTTP 403/1010 deste servidor; confirmar o domínio/sender no painel Resend ou em rede permitida antes de ativar.

## Ativação em TST

1. Confirmar o sender `statuslive` no Resend e preencher o secret de TST.
2. Aplicar a migration `2026_10_07_000058_seed_checkout_transparent_buyer_email_templates.php`.
3. Definir `SALE_RECOVERY_TRANSPARENT_RDC_BASE_URL=https://checkout.statuslive.site`.
4. Ativar as flags CT.
5. Validar compra, Pix, pendência, sucesso, recuperação, upsell, erros e e-mails no Mailpit.
6. Repetir em produção somente depois da aprovação em TST.
