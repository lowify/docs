# Estado atual e fronteiras

## Fluxo confirmado

| Componente | Comportamento atual | Mudança necessária |
| --- | --- | --- |
| CT API | `ResolveCheckoutAvailabilityUseCase` mapeia somente `pix`. | Mapear `card` para Mercado Pago, Pagar.me e Efí e declarar campos obrigatórios por provedor. |
| Edge Public API | Valida a disponibilidade, cria a venda no Commerce V2 e cria a `charge`; depois espera QR Code Pix. | Encaminhar dados de cartão tokenizados e substituir a espera de QR Code por resultado de cartão. |
| Commerce V2 | Para `checkout_mode=transparent`, cria venda pendente e não chama Banking. Antes disso, porém, valida disponibilidade e onboarding do cartão normal. | Separar a regra de cartão transparente da regra de gateway padrão, Cielo e Pagar.me PSP da Lowify. Manter a exigência de produto e seller elegíveis. |
| CT worker | Consome `gateway:instructions` com `payment.create` e `payment.status.check`; todos os clientes atuais criam Pix. | Criar o caminho `card` nos clientes elegíveis, preservando o envelope, correlação e consulta de status. |
| Resultado CT | `payment.create.result` registra tentativa e deixa a charge em `processing`; somente status check pago chama `ConfirmChargePaymentUseCase`. | Tratar aprovação de cartão no retorno imediato, sem aguardar um ciclo Pix para confirmar a venda. |
| Dashboard Seller | O cadastro de integração aceita somente as credenciais Pix atuais. | Adicionar campos e validação de cartão por provedor, sem expor segredos na tela ou no checkout. |

## Provedores

| Provedor | Evidência reutilizável | Fronteira da implementação |
| --- | --- | --- |
| Mercado Pago | Worker Pix usa `access_token`. | Cadastro precisa de `public_key`; front usa Mercado Pago.js. Validar Orders, recomendado para integração nova, e o contrato de webhook/status para cartão. |
| Pagar.me | Worker CT Pix já usa `/orders`; Banking V2 já monta `credit_card` com token, parcelas, endereço e 3DS. | O código do Banking usa credencial e split da Lowify como referência de payload, não como dependência do CT. Cadastro do seller precisa de tokenização pública e credencial de servidor. |
| Efí | Front atual usa `payment-token-efi`; Banking V2 já cria cartão One Step com `payment_token`. | Credenciais CT atuais são Pix com certificado. Criar perfil de cartão com `payee_code` e validar a habilitação de Cobranças/cartão da conta do seller. |
| Woovi | CT cria charge Pix com `AppID`. | Não há API de cartão direto no produto integrado. Não incluir. |
| Kiwify | CT cria QR Code Pix com Conta de Serviço. | Não há API de cartão direto nessa integração. Não incluir. |

## Restrições que o plano resolve

1. `charges.sale_id` e `charges.order_id` são únicos. Após uma recusa, recriar a venda ou a charge falha ou duplica o pedido; a nova tentativa deve reutilizar a charge existente.
2. A `charge` não possui `payment_method`, bandeira ou parcelas. Esses dados precisam ser persistidos somente quando forem úteis para estado e exibição, nunca junto do token.
3. `metadata_json` segue para Redis em `payment.create`. Token de cartão é transitório: o worker não pode registrá-lo em `charge_attempts`, `charge_status_checks`, auditorias ou logs de erro.
4. O front atual registra o resultado bruto da tokenização no console. Esse log precisa sair no fluxo de cartão transparente.

## Referências de descoberta

- `services-checkout-transparent-api/app/Application/UseCase/Checkout/ResolveCheckoutAvailabilityUseCase.php`
- `edge-public-api/app/Http/Controllers/ProductController.php`
- `service-commerce-v2/app/Application/UseCase/Product/ProcessProductCheckoutUseCase.php`
- `service-commerce-v2/app/Application/UseCase/Product/ResolveCheckoutPaymentMethodsUseCase.php`
- `services-checkout-transparent-worker/app/Process/GatewayInstructionQueueProcess.php`
- `front-checkout/views/checkout/form/methods/card.php`
- `front/dashboard-seller/api/dashboard/checkout_transparent/integrations.php`
