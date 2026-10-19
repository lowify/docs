# Estado atual e fronteiras

## Produto Cielo efetivamente utilizado

O código atual usa a solução **Split de Pagamento pela API E-commerce Cielo**:

| Finalidade | Ambiente de produção | Uso atual na Lowify |
| --- | --- | --- |
| OAuth Split | `https://auth.braspag.com.br/oauth2/token` | Obtém Bearer token com `CIELO_ECOMMERCE_SPLIT_MERCHANT_ID` e `CIELO_ECOMMERCE_SPLIT_CLIENT_SECRET`. |
| Criar cobrança | `https://api.cieloecommerce.cielo.com.br/1/sales` | Cria cartão, Pix e cartão com Split. |
| Consultar cobrança | `https://apiquery.cieloecommerce.cielo.com.br/1/sales/{PaymentId}` | Confirma status após webhook. |
| Onboarding | `https://splitonboardingapi.braspag.com.br` | Cria e consulta seller/subordinate merchant. |
| Split pós-transacional | `https://split.braspag.com.br` | Deve ser usado nas cobranças recorrentes, conforme a documentação do Split. |

Não estamos usando Link de Pagamentos, API pública de assinaturas de outro produto, nem Gateway de Pagamento como solução de captura.

## Fluxo de cartão atual

```text
Produto ONE_TIME -> front-checkout coleta cartão
-> Commerce V2 monta pagamento
-> Banking V2 POST /1/sales
-> Payment.Type=SplittedCreditCard + SplitPayments
-> PaymentId -> venda única e webhook ChangeType 1
```

`CieloEcommerceChargeCardClient` envia `Amount`, `Installments`, `Capture`, cartão ou `PaymentToken`, `DoSplit` e `SplitPayments`. Ele não envia `Recurrent`, `RecurrentPayment`, `SaveCard`, `CardToken` ou `CardOnFile`.

O parcelamento atual é uma única venda paga em parcelas pelo comprador. Ele não cria uma assinatura e não representa uma cobrança mensal futura.

## Assinaturas já existentes

| Fluxo | Quem cria as cobranças futuras | O que a Lowify faz |
| --- | --- | --- |
| Woovi Pix Automático | Woovi | Cria a autorização, recebe webhooks de autorização e de cada cobrança, persiste e confirma as parcelas. |
| Efí Pix Automático | Lowify/Efí | Cria a autorização e agenda/cria cada `cobr` futura; webhooks e polling recuperam estados. |
| Cielo cartão recorrente, proposto | Cielo | Cria a série, recebe o `ChangeType: 2`, consulta cada `PaymentId`, faz o Split pós-transacional e confirma a parcela. |

O padrão reutilizável é a compensação de assinatura no Commerce V2: uma primeira parcela aprova a venda inicial; parcelas posteriores geram/localizam uma venda recorrente e executam o fluxo normal de venda paga. Não se reutiliza o protocolo Pix nem se cria uma nova cobrança Cielo mensalmente.

## Estado dos dados e eventos

O Banking V2 já possui `subscriptions` com `provider_id`, `correlation_id`, valor, frequência, vencimento e conta; `subscriptions_charge` relaciona uma cobrança individual à assinatura por `identifier_id`. O Commerce V2 já tem `subscriptions`, `subscriptions_installments`, `sales.subscription_id` e `ProcessSubscriptionChargePaidUseCase`.

O contrato existente usa `correlation_id` para localizar a assinatura e uma parcela identificada pelo número e por um identificador único de pagamento. Para Cielo, o encaixe proposto é:

```text
subscriptions.correlation_id        = RecurrentPaymentId
subscriptions_charge.identifier_id  = PaymentId
subscriptions_installments.end_to_end_id = PaymentId
```

O último uso precisa ser confirmado na implementação: o nome `end_to_end_id` veio de Pix, mas o campo hoje é a chave de pagamento idempotente consumida pelo Commerce. Se essa semântica não for aceita, deve-se adicionar um identificador de transação de provedor de forma aditiva; não sobrecarregar o campo silenciosamente.

## Lacunas atuais

1. `SUBSCRIPTION` não disponibiliza `card` no Commerce V2.
2. A criação Cielo não possui contrato de recorrência nem persiste `RecurrentPaymentId`.
3. O Edge reconhece somente `ChangeType` 1, 7 e 25; `ChangeType: 2` seria registrado e ignorado.
4. Não há consulta de recorrência por `RecurrentPaymentId`, cancelamento da recorrência ou reconciliação de recorrências Cielo.
5. Não há adaptador de Split pós-transacional para cada parcela recorrente.
6. O token de pagamento usado hoje no checkout não pode ser presumido como `CardToken` reutilizável da Cielo.

## Riscos e limites externos

| Situação externa | Risco | Tratamento previsto |
| --- | --- | --- |
| Recorrência não habilitada na conta Master | Série não é criada; a Cielo pode retornar `313`. | Bloquear ativação até confirmação e teste em sandbox. |
| Cartão Protegido ou cobrança sem CVV não habilitados | Renovações podem falhar ou exigir CVV. | Confirmar produto contratado e modelo com a Cielo antes do código. |
| Webhook removido ou desmarcado no portal Cielo | Parcela pode ser paga sem ser processada na Lowify. | Conferir o cadastro e criar reconciliação por `RecurrentPaymentId`. |
| Falha ao aplicar Split pós-transacional | Comprador pode ser cobrado, mas a distribuição ao seller fica pendente. | Persistir estado próprio, retry observável e não confirmar efeito financeiro final antes do resultado definido. |
| Reentrega de webhook ou consulta | Duplicidade de venda, entrega ou repasse. | Chaves únicas por assinatura/parcela/PaymentId e processamento idempotente. |
| Alteração de conta/credencial externa | Novas séries e consultas falham. | Monitorar erro por integração e pausar novas adesões daquela conta. |

## Referências de descoberta

- `services/services-banking-v2/config/autoload/cielo_ecommerce.php`
- `services/services-banking-v2/app/Infrastructure/Gateways/CieloEcommerce/Client/CieloEcommerceClientBase.php`
- `services/services-banking-v2/app/Infrastructure/Gateways/CieloEcommerce/Client/CieloEcommerceChargeCardClient.php`
- `edge/edge-webhook/app/Infrastructure/Gateways/CieloEcommerce/Service/CieloEcommerceWebhookHandler.php`
- `services/services-banking-v2/app/Domain/Subscription/Repository/SubscriptionRepository.php`
- `services/service-commerce-v2/app/Application/UseCase/Subscription/ProcessSubscriptionChargePaidUseCase.php`
- [Split pela API E-commerce Cielo](https://docs.cielo.com.br/split/reference/split-pela-api-e-commerce-cielo)
- [Recorrência no Split](https://docs.cielo.com.br/split/docs/recorr%C3%AAncia)
- [Recorrência na API E-commerce Cielo](https://docs.cielo.com.br/ecommerce-cielo/reference/recorr%C3%AAncia)
- [Tokenização no Split](https://docs.cielo.com.br/split/reference/apiecommerce-criar-cardtoken)
