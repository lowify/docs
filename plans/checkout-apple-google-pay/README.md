# Plano — Apple Pay e Google Pay no Checkout

> Status: planejamento
>
> Escopo: checkout normal de pagamento único

## Objetivo

Disponibilizar Apple Pay e Google Pay como formas de autorizar pagamentos por cartão no checkout, utilizando as integrações de cartão já habilitadas. A mudança amplia a etapa de pagamento; não cria uma nova modalidade comercial, novo adquirente ou fluxo de venda.

O pedido, a cobrança, o split, as taxas, a conciliação, o reembolso e os controles de risco permanecem no mesmo fluxo hoje utilizado para cartão.

## Resultado esperado

Quando o pagamento por cartão estiver disponível para a oferta e a conta processadora estiver habilitada para a carteira, o comprador verá o botão oficial compatível com seu dispositivo. A autorização devolvida pela carteira será processada pelo mesmo gateway responsável pelo cartão daquela venda.

| Gateway de cartão | Apple Pay | Google Pay | Decisão |
| --- | --- | --- | --- |
| Cielo e-commerce | Suportado | Suportado | Implementar |
| Pagar.me PSP | Suportado | Suportado | Implementar |

## Escopo

- Checkout normal de produtos de pagamento único.
- Apple Pay e Google Pay dentro da experiência de cartão.
- Cielo e-commerce e Pagar.me PSP, que já participam da disponibilidade de cartão do checkout.
- Pagamento à vista na primeira entrega. Parcelamento por carteira poderá ser habilitado depois de homologação específica por gateway.

## Fora de escopo

- Criar ou completar integrações de cartão para outros provedores.
- Alterar regras de elegibilidade de produto, vendedor, split, taxa, chargeback, reembolso ou conciliação.
- Pix, boleto, checkout de assinatura, links de cobrança ou Checkout Transparente.
- Exibir carteira em navegador ou dispositivo sem suporte.

## Documentos

1. [Decisão de produto e fronteiras](./01_ESTADO_ATUAL_E_FRONTEIRAS.md)
2. [Contrato de carteira e responsabilidades](./02_CONTRATO_E_CONFIGURACAO_EXTERNA.md)
3. [Plano de implementação e homologação](./03_IMPLEMENTACAO_ROLLOUT_E_ACEITE.md)

## Princípios de entrega

- A disponibilidade é decidida pelo servidor; o navegador apenas filtra o que consegue apresentar.
- O token ou payload de carteira é transitório: não será persistido nem registrado em logs.
- O checkout usa os componentes oficiais das carteiras; dados de cartão não passam pela interface da Lowify.
- Uma indisponibilidade da carteira não remove o pagamento por cartão convencional.
