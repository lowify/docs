# Estado atual e fronteiras

## Fluxo confirmado

| Componente | Comportamento atual | Mudança necessária |
| --- | --- | --- |
| Front Checkout | Exibe `pix_automatic` para produto `SUBSCRIPTION`. | Exibir o método quando a disponibilidade do Checkout Transparente retornar uma integração elegível e coletar os dados exigidos pelo provedor. |
| Commerce V2 | Cria venda `pix_automatic`, assinatura local e parcelas a partir do identificador recebido. | Permitir que a venda transparente aguarde o identificador da autorização do cliente criada pelo Checkout Transparente; associar a assinatura após a resposta do provedor. |
| Banking V2 | Possui clientes, tabelas e handlers para Woovi e Efí, mas os processos de atualização de Pix Automático, scheduler, recuperação e criação de `cobr` da Efí estão desativados na configuração atual. As filas publicadas por esses handlers também não usam o contrato consumido hoje pelo Commerce V2. | Serve para consultar payloads e estados do provedor, não como fluxo operacional pronto para reutilização. O Checkout Transparente usa as credenciais da integração do seller e mantém seus próprios adaptadores. |
| API do Checkout Transparente | `charges.method` e `integration_payment_methods.method` já aceitam `pix_automatic`, mas a disponibilidade aceita somente `ONE_TIME` e não seleciona esse método. | Selecionar o método somente para `SUBSCRIPTION`, registrar a autorização do cliente e publicar a instrução de assinatura. |
| Worker do Checkout Transparente | Possui apenas `payment.create` e `payment.status.check` para cobranças avulsas. | Adicionar ações para criar e acompanhar a autorização do cliente e, para Efí, criar cada cobrança futura. |
| Confirmação do Checkout Transparente | Confirma uma única `charge`, notifica o Commerce V2 e publica os itens de faturamento dessa cobrança. | Encaminhar cada cobrança paga ao fluxo de assinaturas sem repetir venda, entrega ou faturamento. |

## Provedores

| Provedor | Situação | Decisão |
| --- | --- | --- |
| Woovi | Possui `POST /api/v1/subscriptions` com `type=PIX_RECURRING`, QR Code para o cliente autorizar cobranças futuras e eventos sobre autorização e pagamento. As cobranças futuras são geradas pela Woovi. | Implementar. Exige AppID da integração, dados reais da pessoa pagadora e webhooks `PIX_AUTOMATIC_*`. |
| Efí | Possui location de recorrência em `POST /v2/locrec`, recorrência em `POST /v2/rec`, consulta da recorrência e cobrança por `POST /v2/cobr` ou `PUT /v2/cobr/:txid`. | Implementar. Exige agendamento local de `cobr`, dois webhooks próprios de Pix Automático, consulta e recuperação de atualizações que chegarem atrasadas. |
| Mercado Pago | A API de Assinaturas é um produto separado do Checkout API; sua documentação de adesão apresenta fluxo hospedado por link. O Checkout API Transparente permanece voltado ao Pix avulso por order. | Não implementar no Checkout Transparente. O fluxo não oferece a autorização e as cobranças recorrentes na conta integrada do seller. |
| Pagar.me | A criação de assinatura da API atual não expõe `pix` em `payment_method`. | Não implementar. |
| Kiwify | A integração atual do Checkout Transparente gera QR Code Pix de produto Kiwify; a API pública disponível nesse fluxo não expõe autorização recorrente para uma conta externa. | Não implementar. |

## Diferenças que definem o desenho

1. O Pix avulso do Checkout Transparente termina quando uma `charge` é paga. No Pix Automático, precisamos guardar a autorização do cliente, seu estado, o número da parcela e o identificador de cada cobrança futura.
2. A Woovi cria a próxima cobrança e informa seu resultado. A Efí depende de agendamento e criação de `cobr` antes do vencimento.
3. `charge_installments` pode ser reutilizada para representar cobranças futuras, desde que uma entidade de assinatura seja dona da correlação, do provedor, da frequência e do estado.
4. A criação atual de venda `pix_automatic` no Commerce V2 exige um identificador já existente. O Checkout Transparente só recebe esse identificador depois de criar a autorização do cliente, por isso o vínculo precisa ocorrer em duas etapas.
5. A confirmação atual publica os itens de faturamento de uma única `charge`. A recorrência precisa definir e testar o equivalente por parcela, sem duplicação.
6. As frequências normalizadas hoje pelo Commerce V2 (`WEEKLY`, `MONTHLY`, `SEMIANNUALLY` e `ANNUALLY`) são aceitas pela Woovi e podem ser mapeadas para a periodicidade da Efí. A validação do método deve preservar esse conjunto comum.
7. A primeira cobrança precisa ser uma decisão de produto. A jornada atual da Efí cria uma autorização para cobrar no futuro; para liberar o produto no ato da adesão, a jornada escolhida também precisa criar e receber a primeira cobrança. Na Woovi, isso corresponde a `PAYMENT_ON_APPROVAL`.
8. A autorização do cliente precisa registrar qual valor será cobrado em todas as parcelas. Hoje o preço enviado inclui bumps escolhidos e o desconto de saída; sem uma regra própria, ambos entram em todas as parcelas. Essa decisão precisa existir antes de pedir a autorização ao cliente.

## Riscos do controle externo da conta

Depois que o cliente autoriza as cobranças, o seller continua dono da conta do provedor. Ele pode mudar algo diretamente lá. Quando isso acontece, a Lowify pode parar de saber que o cliente autorizou, pagou ou cancelou uma cobrança. Isso afeta venda, entrega e renovação.

### Woovi

| Ação externa | Consequência |
| --- | --- |
| Remover ou alterar qualquer webhook de Pix Automático | Quando o cliente autoriza, paga ou cancela, a Lowify deixa de receber o aviso. A venda pode não ser liberada após pagamento ou uma assinatura cancelada pode continuar parecendo ativa até a consulta posterior encontrar a mudança. |
| Desativar a aplicação, revogar o AppID ou trocar a credencial usada na integração | A Lowify não consegue criar nova autorização, consultar pagamentos pendentes nem conferir se os webhooks continuam certos. Enquanto a integração não for corrigida, não há uma forma segura de continuar a operação. |
| Cancelar uma assinatura pela conta do provedor | O provedor deixa de gerar as próximas cobranças, mas a Lowify só descobre quando recebe ou consulta essa alteração. Sem essa confirmação, o produto pode continuar como se a assinatura existisse. |

### Efí

| Ação externa | Consequência |
| --- | --- |
| Remover ou substituir `webhookrec` ou `webhookcobr` | A Lowify deixa de receber os avisos de autorização e pagamento para todas as assinaturas daquela conta. Um pagamento pode acontecer sem liberar a venda até a consulta posterior encontrar o resultado. |
| Revogar ou restringir escopos, Client ID, Client Secret ou certificado | A Lowify não consegue consultar o que aconteceu, criar a próxima cobrança, registrar os callbacks ou recuperar uma falha. A renovação para até a integração ser corrigida. |
| Revisar ou cancelar uma `rec` ou `cobr` pela conta do provedor | O seller pode cancelar a autorização ou uma cobrança que a Lowify ainda mostra como ativa. Antes de entregar ou renovar, o estado precisa ser conferido no provedor para não agir sobre uma cobrança cancelada. |

### Chave Pix da Efí

A documentação confirma que os callbacks de Pix Automático são associados à chave e à conta, mas não explica o que acontece com uma autorização ou cobrança já existente se o seller remover ou substituir a chave Pix. Antes de ativar o método, a homologação precisa provar quatro pontos: criar nova cobrança, consultar autorização, consultar cobrança existente e receber callback. Enquanto isso não for comprovado, a integração deve parar de aceitar novas cobranças se a chave cadastrada deixar de responder.

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
- [Efí: Credenciais e escopos](https://dev.efipay.com.br/docs/api-pix/credenciais/)
- [Mercado Pago: Assinaturas](https://www.mercadopago.com.br/developers/pt/docs/subscriptions/overview)
- [Pagar.me: assinatura de plano](https://docs.pagar.me/reference/criar-assinatura-de-plano-1)
- [Pagar.me: assinaturas](https://docs.pagar.me/reference/assinaturas-1)
