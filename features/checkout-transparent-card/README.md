# Feature — cartão de crédito no Checkout Transparente

> Status: planejada
> Última atualização: 2026-09-15
> Confiança: confirmada no código e na documentação pública dos provedores

## Objetivo

Permitir pagamento único por cartão no Checkout Transparente usando a conta do seller.

## Viabilidade por provedor

| Provedor | Evidência no código | Necessário para cartão direto | Decisão |
| --- | --- | --- | --- |
| Mercado Pago | Worker Pix com `access_token`. | `public_key` do seller no front, tokenização Mercado Pago.js e worker de cartão. Validar a adoção de Orders, caminho recomendado pelo provedor para novas integrações. | Viável. |
| Pagar.me | CT Pix já usa Orders; checkout normal já cria Orders de cartão com token, parcelas, endereço e 3DS. | Configuração pública de tokenização da conta do seller; endereço obrigatório no contrato CT de cartão. | Viável e menor adaptação. |
| Efí | Front Checkout e Banking V2 já geram `payment_token` e criam cobrança One Step. | Perfil de cartão da integração do seller: API de Cobranças habilitada, `payee_code` e aprovação cadastral de cartão. | Viável. |
| Woovi | Worker CT cria somente charge Pix com `AppID`. | Não há tokenização e criação de cartão direto no produto/API usados hoje. Woovi Parcelado é outra jornada. | Não viável na integração atual. |
| Kiwify | Worker CT cria QR Code Pix com Conta de Serviço e chave Ed25519. | Não há API pública de tokenização ou cobrança direta de cartão para esta integração. | Não viável na integração atual. |

## Fluxo proposto

```text
Front Checkout -> tokenização do provedor -> CT API -> fila -> worker de cartão
-> resposta da autorização e consulta/webhook quando pendente -> confirmação no Commerce V2
```

1. Disponibilizar `card` apenas em vendas `ONE_TIME` com Mercado Pago, Pagar.me ou Efí ativos.
2. Expor ao front somente configuração pública da integração selecionada e tokenizar diretamente no provedor. PAN, CVV e token não podem ser persistidos pela Lowify.
3. Enviar para o CT token, bandeira, parcelas e dados de comprador. Documento, telefone e endereço passam a ser requisitos do método.
4. Criar workers de cartão que normalizem `approved`, `pending` e `refused`. Fila, idempotência, consulta de status e confirmação da venda permanecem os mesmos.
5. Substituir a espera por QR Code pelo retorno da autorização. Para estados pendentes, webhook e consulta continuam sendo a confirmação final.

## Limitações e pendências

- Mercado Pago: validar Orders na conta do seller durante a implementação.
- Pagar.me: definir a política de 3DS por integração.
- Efí: validar o novo cadastro de cartão em homologação, incluindo a habilitação da conta do seller.
- Woovi Parcelado e checkout hospedado Kiwify ficam fora do método `card`.

## Referências

- `lowify-ct/services-checkout-transparent-api/app/Application/UseCase/Checkout/ResolveCheckoutAvailabilityUseCase.php`
- `lowify-ct/services-checkout-transparent-api/app/Application/UseCase/Charge/CreateChargeUseCase.php`
- `lowify-ct/services-checkout-transparent-api/app/Domain/Integration/Service/IntegrationGatewayCredentialRules.php`
- `lowify-ct/services-checkout-transparent-worker/app/Infrastructure/Gateways/`
- `edge/edge-public-api/app/Http/Controllers/ProductController.php`
- `front/front-checkout/views/checkout/form/methods/card.php`
- `services/service-commerce-v2/app/Application/UseCase/Product/ProcessProductCheckoutUseCase.php`
- `services/services-banking-v2/app/Infrastructure/Gateways/EfiBank/Client/EfiBankChargeCardClient.php`
- [Mercado Pago: Checkout API](https://www.mercadopago.com.br/developers/pt/reference/online-payments/checkout-api/overview) e [CardForm](https://www.mercadopago.com.br/developers/en/docs/checkout-api-payments/integration-configuration/card/integrate-via-cardform/introduction?scope=prod)
- [Pagar.me: pagamento com cartão](https://docs.pagar.me/reference/cart%C3%A3o-de-cr%C3%A9dito-1)
- [Efí: API de cobranças por cartão](https://dev.efipay.com.br/docs/api-cobrancas/cartao/)
- [Woovi: Pix e Woovi Parcelado](https://developers.woovi.com/en/docs/ecommerce/opencart/opencart3-extension)
- [Kiwify: API pública](https://ajuda.kiwify.com.br/pt-br/article/como-funciona-a-api-da-kiwify-1iosjhu/)
