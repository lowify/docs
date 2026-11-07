# Validações — taxa de serviço do cliente e rateio de reembolso

Ambiente: homologação. Este relatório reúne as validações manuais e os testes internos executados após o deploy descrito no [documento operacional](2026-11-06_END_CUSTOMER_SERVICE_FEE_DEPLOY.md).

## Resultado consolidado

| Cenário | Resultado |
| --- | --- |
| Cotação do checkout | A configuração global de `R$ 0,94` foi exibida no checkout público. |
| Cobrança e compensação Lowify | Pix, cartão e Pix Automático persistiram produtos, taxa e total cobrado; a carteira do seller recebeu somente o valor comercial. |
| Checkout Transparente | Cobrança usou taxa zero. O reembolso revelou lançamento indevido na carteira do Commerce; permanece pendente de correção. |
| Reembolso Lowify | Pix, cartão e Pix Automático reembolsaram somente o valor comercial, sem devolver ou debitar a taxa de serviço. |
| Afiliado | O ciclo correto `pending → held → released → refunded` foi validado, com comissão e débito na carteira do afiliado. |
| Overrides por seller | O override prevaleceu sobre a configuração global; `R$ 0,00` é um override explícito. |
| Formulários administrativos | Taxas comerciais, MDR e taxa de serviço foram validados em formulários/actions independentes; padrão da plataforma e override zero funcionaram. |

## Cobrança e compensação

As vendas `9901495` (Pix), `9901496` (cartão) e `9901497` (Pix Automático) tiveram valor comercial de `R$ 2,00`, taxa de serviço de `R$ 0,94` e total de `R$ 2,94`. Cada uma criou extrato comercial de `+R$ 2,00`, taxa do seller de `-R$ 0,99` e saldo líquido de `R$ 1,01`; a taxa de serviço não entrou no extrato do seller.

A venda transparente `9901498` teve valor comercial e total cobrado de `R$ 5,00`, sem taxa de serviço.

## Reembolsos

As vendas Lowify acima receberam reembolso interno aprovado de `R$ 2,00` cada. Os eventos foram consumidos pela carteira e não incluíram os `R$ 0,94` de taxa de serviço.

O reembolso interno da venda transparente `9901498` gerou indevidamente um `refund_approved` na carteira do seller. A regra esperada é não criar lançamento do Commerce para Checkout Transparente. Esse cenário não está aprovado.

## Afiliado

A primeira simulação (`9901507`) foi invalidada: o vínculo de afiliado foi inserido manualmente com destinatário incorreto. Ela não representa o fluxo publicado.

A validação válida foi a venda `9901508`, criada com `affiliate_id=61` antes do evento `pending`:

- comissão criada para o afiliado `900030`: `R$ 4,71`;
- pagamento moveu a comissão para `held` por um dia;
- liberação creditou `900030`;
- reembolso comercial de `R$ 19,00`: seller `900026` debitado em `R$ 14,29` e afiliado `900030` em `R$ 4,71`;
- taxa de serviço de `R$ 0,94` permaneceu fora da comissão e do reembolso.

## Overrides e administração

A configuração global `system_vars.checkout_service_fee_default=0.94` foi persistida na homologação e usada na cotação pública quando o seller não tinha override.

Para o seller `4801`, `checkout_service_fee_fixed=0.01` foi resolvido pelo Commerce com origem `user`, prevalecendo sobre o global de `R$ 0,94`. Em seguida, `0.00` foi resolvido como override explícito, também com origem `user`.

No Dashboard, o commit `c79e43ea` separou taxa comercial, MDR e taxa de serviço em formulários/actions distintos. A validação manual confirmou o uso do padrão da plataforma, valores fixos e o valor zero para MDR e taxa de serviço.

## Roteiro de validação

1. No Admin, abra as configurações de pagamento, defina temporariamente `R$ 0,00` e salve. Reabra a tela e confirme que o valor persistiu.
2. Crie uma venda Pix de teste para seller sem override. Confirme que o comprador vê somente o valor dos produtos e que o total cobrado é igual a ele.
3. Defina um override piloto maior que zero no seller. Crie uma nova venda Pix e uma nova venda de cartão. Confirme que a interface mostra taxa e total, e que o valor do Pix/parcelas corresponde ao total cobrado.
4. Abra o detalhe administrativo da venda e confirme produtos, taxa do cliente e total. O detalhe no contexto do seller não deve exibir essa taxa.
5. Abra o RDC de uma venda pendente e a compra Pix da Área de Membros. Confirme que ambos mostram o mesmo total registrado na venda, sem recotar um Pix pendente.
6. Para uma venda de carteira com afiliado e comissão liberada, solicite reembolso total em ambiente de homologação. Confirme que seller e afiliado recebem débitos proporcionais cuja soma é o valor comercial da venda.
7. Para uma venda de cartão Cielo/Pagar.me com split, solicite reembolso no sandbox. Confirme que não há débito na carteira Lowify de seller ou afiliado; a reversão deve aparecer no gateway.
8. Reenvie uma confirmação de reembolso de teste e confirme que não há lançamento duplicado para seller nem afiliado.

Se qualquer valor ficar duplicado, ausente ou incluir a taxa indevidamente, interrompa a ativação global e preserve IDs de venda/reembolso para conciliação. Não ajuste saldos manualmente.
