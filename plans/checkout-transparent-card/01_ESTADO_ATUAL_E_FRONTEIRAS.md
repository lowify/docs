# Estado atual e fronteiras

## Fluxo confirmado

| Componente | Comportamento atual | Mudança necessária |
| --- | --- | --- |
| CT API | Seleciona integração por método habilitado/default e aceita `card_credit` com tentativa idempotente. | Reutilizar o contrato para novos gateways, adicionando somente os campos específicos de cada provedor. |
| Edge Public API | Mantém a criação da venda pendente e da charge; para cartão, a tentativa recebe apenas o token transitório. | Manter o contrato único ao adicionar novos tokenizadores. |
| Commerce V2 | Para `checkout_mode=transparent`, cria venda pendente sem validar gateway padrão, Cielo, Pagar.me PSP ou onboarding do cartão normal. | Preservar elegibilidade de produto, seller e limite de parcelas em cada novo método. |
| CT worker | Mercado Pago e Pagar.me criam cartão por Orders; Efí cria cobrança One Step. Todos consultam status e publicam no envelope existente. | Manter o envelope e a correlação ao adicionar novos gateways. |
| Resultado CT | Aprovação imediata de cartão confirma charge, venda e entrega no mesmo fluxo idempotente de confirmação. | Cobrir estados pendentes por polling/webhook conforme o provedor. |
| Dashboard Seller | Mercado Pago e Pagar.me configuram Public Key; Efí configura o Identificador de conta na edição da integração. | Preservar as credenciais privadas fora da tela de edição. |

## Provedores

| Provedor | Evidência reutilizável | Fronteira da implementação |
| --- | --- | --- |
| Mercado Pago | Worker Pix usa `access_token`; cartão usa Public Key no front e Orders no worker. | Implementado e validado com aprovação e recusa. Polling continua como reconciliação; webhook de cartão permanece a validar no rollout. |
| Pagar.me | Worker CT Pix já usa `/orders`; Banking V2 já monta `credit_card` com token, parcelas e endereço. | Implementado sem split: tokenização no navegador, `auth_and_capture`, endereço de cobrança e polling de `/charges/{id}`. Cadastro do seller precisa de Public Key, credencial de servidor e domínio autorizado para tokenização. |
| Efí | Front usa `payment-token-efi`; o worker cria cartão One Step com `payment_token`. | O método `card_credit` usa `payee_code`; as credenciais e o certificado da integração autenticam a API Cobranças. Nome, CPF, e-mail e telefone seguem no cliente da cobrança. |
| Woovi | CT cria charge Pix com `AppID`. | Não há API de cartão direto no produto integrado. Não incluir. |
| Kiwify | CT cria QR Code Pix com Conta de Serviço. | Não há API de cartão direto nessa integração. Não incluir. |

## Restrições que o plano resolve

1. `charges.sale_id` e `charges.order_id` permanecem únicos. Após uma recusa, a nova tentativa reutiliza a charge existente e recebe nova chave de idempotência.
2. `charges.method`, `charge_installments` e `charge_attempts` suportam cartão sem duplicar o modelo de parcelas que também atenderá Pix Automático.
3. Configuração, habilitação/default e chaves ficam escopadas ao método da integração. `integrations.settings_json` e `integration_keys` permanecem como compatibilidade e origem do backfill Pix.
4. `metadata_json` segue para Redis em `payment.create`. Token de cartão é transitório: o worker não o registra em `charge_attempts`, `charge_status_checks`, auditorias ou logs de erro. O resultado do gateway passa por sanitização antes de persistir.
5. O Front Checkout não registra a resposta bruta de tokenização no console. A tela conserva somente token transitório, máscara e identificadores não sensíveis necessários à tentativa.

## Riscos do controle externo da conta

O pagamento é criado na conta do seller. Depois de habilitar a integração, ele ainda pode alterar ou remover recursos diretamente no provedor. Algumas dessas alterações não impedem apenas uma nova venda: elas podem deixar uma cobrança pendente sem confirmação ou fazer o estado financeiro no provedor divergir de uma venda que a Lowify já marcou como paga.

### Mercado Pago

| Ação externa | Consequência |
| --- | --- |
| Desconectar a aplicação ou invalidar a autorização OAuth | O `access_token` deixa de servir para criar pedidos e consultar cobranças. Uma cobrança que estiver pendente não pode ser confirmada com segurança até a conta ser conectada novamente. |

### Pagar.me

| Ação externa | Consequência |
| --- | --- |
| Remover `checkout.lowify.com.br` dos domínios autorizados | O navegador deixa de tokenizar novos cartões. Não há cobrança a consultar nem correção por polling: o checkout fica incapaz de iniciar a tentativa até o domínio ser autorizado de novo. |
| Revogar ou trocar a Public Key ou a Secret Key na conta do provedor | A Public Key antiga impede a tokenização; a Secret Key antiga impede a criação e a consulta de cobranças. Tentativas em andamento podem ficar sem um resultado confirmável até as chaves cadastradas na integração serem atualizadas. |

### Efí

| Ação externa | Consequência |
| --- | --- |
| Revogar ou substituir Client ID, Client Secret ou certificado da aplicação | A autenticação da API de cobranças falha. A Lowify não consegue criar nem consultar cobranças que dependam dessas credenciais até a integração ser corrigida. |

## Padrões para os próximos adaptadores

1. Separar `card_brand`, usado pela interface, de `payment_method_id`, usado pelo gateway. A primeira adaptação mostrou que ambos podem divergir, como `mastercard` na tela e `master` no Mercado Pago.
2. Configurações públicas pertencem ao método de pagamento; credenciais privadas pertencem ao método ou são copiadas para ele somente no servidor quando houver reutilização autorizada da integração.
3. O adaptador retorna estado normalizado, identificador da cobrança e identificador da transação. `GatewayResultQueueProcess` é o único ponto que persiste o resultado e confirma uma venda paga.
4. Uma recusa deixa a charge apta a nova tentativa com nova chave de idempotência. O token de uma tentativa não pode ser reutilizado nem reaproveitado em persistência.

## Referências de descoberta

- `services-checkout-transparent-api/app/Application/UseCase/Checkout/ResolveCheckoutAvailabilityUseCase.php`
- `edge-public-api/app/Http/Controllers/ProductController.php`
- `service-commerce-v2/app/Application/UseCase/Product/ProcessProductCheckoutUseCase.php`
- `service-commerce-v2/app/Application/UseCase/Product/ResolveCheckoutPaymentMethodsUseCase.php`
- `services-checkout-transparent-worker/app/Process/GatewayInstructionQueueProcess.php`
- `front-checkout/views/checkout/form/methods/card.php`
- `front/dashboard-seller/api/dashboard/checkout_transparent/integrations.php`
- [Mercado Pago: cancelamentos e estornos](https://www.mercadopago.com.br/developers/pt/docs/checkout-api-orders/payment-management/refunds-cancellations)
- [Pagar.me: cobranças](https://docs.pagar.me/reference/cobran%C3%A7as-1)
- [Efí: cobranças por cartão](https://dev.efipay.com.br/docs/api-cobrancas/cartao/)
