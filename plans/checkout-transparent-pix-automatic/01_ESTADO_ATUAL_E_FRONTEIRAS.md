# Estado atual e fronteiras

## Fluxo confirmado

| Componente | Comportamento atual | Mudança necessária |
| --- | --- | --- |
| Front Checkout | Exibe `pix_automatic` para produto `SUBSCRIPTION`. | Exibir o método quando a disponibilidade CT retornar uma integração elegível e coletar os dados exigidos pelo provedor. |
| Commerce V2 | Cria venda `pix_automatic`, assinatura local e parcelas a partir da correlação recebida. | Permitir que a venda transparente aguarde a correlação do mandato criada pelo CT; associar a assinatura após a resposta do provedor. |
| Banking V2 | Implementa Woovi, Efí e Pinbank para a Lowify. Woovi recebe webhooks; Efí agenda `cobr` e processa atualizações. | Serve como referência de contrato e estados. O CT usa as credenciais da integração do seller e mantém seus próprios adaptadores. |
| CT API | `charges.method` e `integration_payment_methods.method` já aceitam `pix_automatic`, mas a disponibilidade aceita somente `ONE_TIME` e não seleciona esse método. | Selecionar o método somente para `SUBSCRIPTION`, criar o registro recorrente e publicar a instrução de assinatura. |
| CT worker | Possui apenas `payment.create` e `payment.status.check` para cobranças avulsas. | Adicionar ações de assinatura, atualização e, para Efí, criação de cobrança futura. |
| Confirmação CT | Confirma uma única `charge`, notifica o Commerce V2 e publica os itens de faturamento dessa cobrança. | Encaminhar cada cobrança paga para o fluxo idempotente de assinaturas e preservar o faturamento por parcela. |

## Provedores

| Provedor | Situação | Decisão |
| --- | --- | --- |
| Woovi | Possui `POST /api/v1/subscriptions` com `type=PIX_RECURRING`, QR Code de autorização e eventos de mandato e cobrança. As cobranças futuras são geradas pela Woovi. | Implementar. Exige AppID da integração, dados reais da pessoa pagadora e webhooks `PIX_AUTOMATIC_*`. |
| Efí | Possui location de recorrência em `POST /v2/locrec`, recorrência em `POST /v2/rec`, consulta da recorrência e cobrança por `POST /v2/cobr` ou `PUT /v2/cobr/:txid`. | Implementar. Exige agendamento local de `cobr`, consulta, reconciliação e tratamento de atualizações. |
| Mercado Pago | A API de Assinaturas é um produto separado do Checkout API; sua documentação de adesão apresenta fluxo hospedado por link. O Checkout API Transparente permanece voltado ao Pix avulso por order. | Não implementar no CT. O fluxo não entrega o contrato de mandato e cobranças recorrentes da integração do seller. |
| Pagar.me | A criação de assinatura da API atual não expõe `pix` em `payment_method`. | Não implementar. |
| Kiwify | A integração CT atual gera QR Code Pix de produto Kiwify; a API pública disponível nesse fluxo não expõe mandato recorrente para uma conta externa. | Não implementar. |

## Diferenças que definem o desenho

1. O Pix avulso do CT termina quando uma `charge` é paga. Pix Automático precisa manter mandato, estado, número da parcela e identificador de cada cobrança futura.
2. A Woovi cria a próxima cobrança e informa seu resultado. A Efí depende de agendamento e criação de `cobr` antes do vencimento.
3. `charge_installments` pode ser reutilizada para representar cobranças futuras, desde que uma entidade de assinatura seja dona da correlação, do provedor, da frequência e do estado.
4. A Woovi exige endereço real da pessoa pagadora na criação. O endereço fixo usado hoje no checkout comum não pode ser reproduzido no CT.
5. A criação atual de venda `pix_automatic` no Commerce V2 pressupõe uma correlação já existente. O CT só recebe essa correlação após criar o mandato, portanto o vínculo precisa ocorrer em duas etapas.
6. A confirmação atual publica os itens de faturamento de uma única `charge`. A recorrência precisa definir e testar o equivalente por parcela, sem duplicação.
7. As frequências normalizadas hoje pelo Commerce V2 (`WEEKLY`, `MONTHLY`, `SEMIANNUALLY` e `ANNUALLY`) são aceitas pela Woovi e podem ser mapeadas para a periodicidade da Efí. A validação do método deve preservar esse conjunto comum.

## Referências de descoberta

- `services/service-commerce-v2/app/Application/UseCase/Product/ProcessProductCheckoutUseCase.php`
- `services/service-commerce-v2/app/Application/UseCase/Subscription/ProcessSubscriptionChargePaidUseCase.php`
- `services/services-banking-v2/app/Infrastructure/Gateways/Woovi/Client/WooviSubscriptionClient.php`
- `services/services-banking-v2/app/Infrastructure/Gateways/EfiBank/Client/EfiBankSubscriptionClient.php`
- `services/services-banking-v2/app/Infrastructure/Services/EfiRecurringChargeScheduler.php`
- `services-checkout-transparent-api/app/Application/UseCase/Checkout/ResolveCheckoutAvailabilityUseCase.php`
- `services-checkout-transparent-api/app/Application/UseCase/Charge/CreateChargeUseCase.php`
- [Woovi: Pix Automático](https://developers.woovi.com/docs/category/pix-autom%C3%A1tico)
- [Efí: Pix Automático](https://dev.efipay.com.br/docs/api-pix/pix-automatico/)
- [Mercado Pago: Assinaturas](https://www.mercadopago.com.br/developers/pt/docs/subscriptions/overview)
- [Pagar.me: assinatura de plano](https://docs.pagar.me/reference/criar-assinatura-de-plano-1)
- [Pagar.me: assinaturas](https://docs.pagar.me/reference/assinaturas-1)
