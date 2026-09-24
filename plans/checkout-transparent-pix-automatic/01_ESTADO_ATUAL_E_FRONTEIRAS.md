# Estado atual e fronteiras

## Fluxo confirmado

| Componente | Comportamento atual | Mudança necessária |
| --- | --- | --- |
| Front Checkout | Exibe `pix_automatic` para produto `SUBSCRIPTION`. | Exibir o método quando a disponibilidade do Checkout Transparente retornar uma integração elegível e coletar os dados exigidos pelo provedor. |
| Commerce V2 | Cria venda `pix_automatic`, assinatura local e parcelas a partir da correlação recebida. | Permitir que a venda transparente aguarde a correlação do mandato criada pelo Checkout Transparente; associar a assinatura após a resposta do provedor. |
| Banking V2 | Possui clientes, tabelas e handlers para Woovi e Efí, mas os processos de atualização de Pix Automático, scheduler, recuperação e criação de `cobr` da Efí estão desativados na configuração atual. As filas publicadas por esses handlers também não usam o contrato consumido hoje pelo Commerce V2. | Serve para consultar payloads e estados do provedor, não como fluxo operacional pronto para reutilização. O Checkout Transparente usa as credenciais da integração do seller e mantém seus próprios adaptadores. |
| API do Checkout Transparente | `charges.method` e `integration_payment_methods.method` já aceitam `pix_automatic`, mas a disponibilidade aceita somente `ONE_TIME` e não seleciona esse método. | Selecionar o método somente para `SUBSCRIPTION`, criar o registro recorrente e publicar a instrução de assinatura. |
| Worker do Checkout Transparente | Possui apenas `payment.create` e `payment.status.check` para cobranças avulsas. | Adicionar ações de assinatura, atualização e, para Efí, criação de cobrança futura. |
| Confirmação do Checkout Transparente | Confirma uma única `charge`, notifica o Commerce V2 e publica os itens de faturamento dessa cobrança. | Encaminhar cada cobrança paga para o fluxo idempotente de assinaturas e preservar o faturamento por parcela. |

## Provedores

| Provedor | Situação | Decisão |
| --- | --- | --- |
| Woovi | Possui `POST /api/v1/subscriptions` com `type=PIX_RECURRING`, QR Code de autorização e eventos de mandato e cobrança. As cobranças futuras são geradas pela Woovi. | Implementar. Exige AppID da integração, dados reais da pessoa pagadora e webhooks `PIX_AUTOMATIC_*`. |
| Efí | Possui location de recorrência em `POST /v2/locrec`, recorrência em `POST /v2/rec`, consulta da recorrência e cobrança por `POST /v2/cobr` ou `PUT /v2/cobr/:txid`. | Implementar. Exige agendamento local de `cobr`, dois webhooks próprios de Pix Automático, consulta, reconciliação e tratamento de atualizações. |
| Mercado Pago | A API de Assinaturas é um produto separado do Checkout API; sua documentação de adesão apresenta fluxo hospedado por link. O Checkout API Transparente permanece voltado ao Pix avulso por order. | Não implementar no Checkout Transparente. O fluxo não entrega o contrato de mandato e cobranças recorrentes da integração do seller. |
| Pagar.me | A criação de assinatura da API atual não expõe `pix` em `payment_method`. | Não implementar. |
| Kiwify | A integração atual do Checkout Transparente gera QR Code Pix de produto Kiwify; a API pública disponível nesse fluxo não expõe mandato recorrente para uma conta externa. | Não implementar. |

## Diferenças que definem o desenho

1. O Pix avulso do Checkout Transparente termina quando uma `charge` é paga. Pix Automático precisa manter mandato, estado, número da parcela e identificador de cada cobrança futura.
2. A Woovi cria a próxima cobrança e informa seu resultado. A Efí depende de agendamento e criação de `cobr` antes do vencimento.
3. `charge_installments` pode ser reutilizada para representar cobranças futuras, desde que uma entidade de assinatura seja dona da correlação, do provedor, da frequência e do estado.
4. A criação atual de venda `pix_automatic` no Commerce V2 pressupõe uma correlação já existente. O Checkout Transparente só recebe essa correlação após criar o mandato, portanto o vínculo precisa ocorrer em duas etapas.
5. A confirmação atual publica os itens de faturamento de uma única `charge`. A recorrência precisa definir e testar o equivalente por parcela, sem duplicação.
6. As frequências normalizadas hoje pelo Commerce V2 (`WEEKLY`, `MONTHLY`, `SEMIANNUALLY` e `ANNUALLY`) são aceitas pela Woovi e podem ser mapeadas para a periodicidade da Efí. A validação do método deve preservar esse conjunto comum.
7. A primeira cobrança precisa ser uma decisão de produto. A jornada atual da Efí cria a autorização para uma cobrança futura; para liberar o produto no ato da adesão, a jornada escolhida precisa gerar também a primeira cobrança. Na Woovi, isso corresponde a `PAYMENT_ON_APPROVAL`.
8. O mandato deve congelar a composição recorrente. Hoje o preço enviado inclui bumps escolhidos e o desconto de saída; sem regra própria, ambos passam a compor todas as parcelas. A regra precisa ser decidida antes de criar o mandato.

## Riscos operacionais da Woovi

1. O seller controla a conta Woovi e pode remover ou alterar os webhooks. Isso interrompe os eventos das assinaturas daquela conta. Se também revogar o AppID ou substituir a credencial, o Checkout Transparente perde a capacidade de consultar essas assinaturas até a conta ser corrigida.
2. A recuperação pela API existe, mas ocorre depois do evento e custa consultas por assinatura e parcela. Ela reduz perda de informação, mas não preserva confirmação em tempo real quando os webhooks da conta deixam de funcionar.

## Riscos operacionais da Efí

1. O seller controla as credenciais que registram `webhookrec` e `webhookcobr` e pode removê-los ou substituí-los. Isso interrompe os callbacks de recorrência ou cobrança para todas as assinaturas daquela conta. A consulta posterior permite reconciliar estados conhecidos, mas não repõe a confirmação em tempo real enquanto o cadastro externo permanece alterado.

## Referências de descoberta

- `services/service-commerce-v2/app/Application/UseCase/Product/ProcessProductCheckoutUseCase.php`
- `services/service-commerce-v2/app/Application/UseCase/Subscription/ProcessSubscriptionChargePaidUseCase.php`
- `services/services-banking-v2/app/Infrastructure/Gateways/Woovi/Client/WooviSubscriptionClient.php`
- `services/services-banking-v2/app/Infrastructure/Gateways/EfiBank/Client/EfiBankSubscriptionClient.php`
- `services/services-banking-v2/app/Infrastructure/Services/EfiRecurringChargeScheduler.php`
- `services/services-banking-v2/config/autoload/processes.php`
- `services/service-commerce-v2/app/Process/SubscriptionActionsProcess.php`
- `services-checkout-transparent-api/app/Application/UseCase/Checkout/ResolveCheckoutAvailabilityUseCase.php`
- `services-checkout-transparent-api/app/Application/UseCase/Charge/CreateChargeUseCase.php`
- [Woovi: Pix Automático](https://developers.woovi.com/docs/category/pix-autom%C3%A1tico)
- [Woovi: eventos de Pix Automático](https://developers.woovi.com/docs/pix-automatic/webhooks/pix-automatic-webhooks)
- [Woovi: API de assinaturas, parcelas e webhooks](https://developers.woovi.com/api-redoc)
- [Efí: Pix Automático](https://dev.efipay.com.br/docs/api-pix/pix-automatico/)
- [Efí: Webhooks](https://dev.efipay.com.br/docs/api-pix/webhooks/)
- [Mercado Pago: Assinaturas](https://www.mercadopago.com.br/developers/pt/docs/subscriptions/overview)
- [Pagar.me: assinatura de plano](https://docs.pagar.me/reference/criar-assinatura-de-plano-1)
- [Pagar.me: assinaturas](https://docs.pagar.me/reference/assinaturas-1)
