# Estado atual e fronteiras

## Fluxo confirmado

| Componente | Comportamento atual | Mudança necessária |
| --- | --- | --- |
| CT API | Seleciona integração por método habilitado/default e aceita `card_credit` com tentativa idempotente. | Reutilizar o contrato para Pagar.me e Efí, adicionando somente os campos específicos de cada gateway. |
| Edge Public API | Mantém a criação da venda pendente e da charge; para cartão, a tentativa recebe apenas o token transitório. | Manter o contrato único ao adicionar novos tokenizadores. |
| Commerce V2 | Para `checkout_mode=transparent`, cria venda pendente sem validar gateway padrão, Cielo, Pagar.me PSP ou onboarding do cartão normal. | Preservar elegibilidade de produto, seller e limite de parcelas em cada novo método. |
| CT worker | Mercado Pago cria cartão por Orders, consulta o pedido e publica o resultado no envelope existente. | Implementar os adaptadores Pagar.me e Efí sem alterar o envelope ou a correlação. |
| Resultado CT | Aprovação imediata de cartão confirma charge, venda e entrega no mesmo fluxo idempotente de confirmação. | Cobrir estados pendentes por polling/webhook conforme o provedor. |
| Dashboard Seller | Mercado Pago configura a Public Key de cartão na edição da integração; o Access Token permanece privado. | Adicionar configurações públicas equivalentes para Pagar.me e Efí. |

## Provedores

| Provedor | Evidência reutilizável | Fronteira da implementação |
| --- | --- | --- |
| Mercado Pago | Worker Pix usa `access_token`; cartão usa Public Key no front e Orders no worker. | Implementado e validado com aprovação e recusa. Polling continua como reconciliação; webhook de cartão permanece a validar no rollout. |
| Pagar.me | Worker CT Pix já usa `/orders`; Banking V2 já monta `credit_card` com token, parcelas, endereço e 3DS. | O código do Banking usa credencial e split da Lowify como referência de payload, não como dependência do CT. Cadastro do seller precisa de tokenização pública e credencial de servidor. |
| Efí | Front atual usa `payment-token-efi`; Banking V2 já cria cartão One Step com `payment_token`. | Credenciais CT atuais são Pix com certificado. Criar perfil de cartão com `payee_code` e validar a habilitação de Cobranças/cartão da conta do seller. |
| Woovi | CT cria charge Pix com `AppID`. | Não há API de cartão direto no produto integrado. Não incluir. |
| Kiwify | CT cria QR Code Pix com Conta de Serviço. | Não há API de cartão direto nessa integração. Não incluir. |

## Restrições que o plano resolve

1. `charges.sale_id` e `charges.order_id` permanecem únicos. Após uma recusa, a nova tentativa reutiliza a charge existente e recebe nova chave de idempotência.
2. `charges.method`, `charge_installments` e `charge_attempts` suportam cartão sem duplicar o modelo de parcelas que também atenderá Pix Automático.
3. Configuração, habilitação/default e chaves ficam escopadas ao método da integração. `integrations.settings_json` e `integration_keys` permanecem como compatibilidade e origem do backfill Pix.
4. `metadata_json` segue para Redis em `payment.create`. Token de cartão é transitório: o worker não o registra em `charge_attempts`, `charge_status_checks`, auditorias ou logs de erro. O resultado do gateway passa por sanitização antes de persistir.
5. O Front Checkout não registra a resposta bruta de tokenização no console. A tela conserva somente token transitório, máscara e identificadores não sensíveis necessários à tentativa.

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
