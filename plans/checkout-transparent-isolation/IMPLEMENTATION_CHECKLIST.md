# Checklist — Checkout Transparente

## Feito no código

- [x] CT permanece no host `checkout`; checkout normal permanece em `pay`.
- [x] CT mantém somente o logo Lowify no rodapé.
- [x] CT não apresenta suporte, WhatsApp, e-mail ou chamada para contato sem canal disponível.
- [x] Erros não pedem contato sem canal.
- [x] E-mails CT selecionam `resend` quando ativados.
- [x] Flags CT ficam desligadas até validação em TST.

## TST / statuslive

- [ ] Confirmar domínio e sender `statuslive` verificados no Resend.
- [ ] Configurar `RESEND_MAIL_FROM` e o secret no TST.
- [ ] Definir `SALE_RECOVERY_TRANSPARENT_RDC_BASE_URL=https://checkout.statuslive.site`.
- [ ] Aplicar a migration dos templates CT.
- [ ] Ativar as flags CT e validar no Mailpit.
- [ ] Validar checkout, Pix, pendência, sucesso, recuperação, upsell e erros.

## Produção

- [ ] Repetir apenas após aprovação completa em TST, com sender de produção verificado.
