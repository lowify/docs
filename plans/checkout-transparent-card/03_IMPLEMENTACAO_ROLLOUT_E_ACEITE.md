# Implementação, rollout e aceite

## Ordem de implementação

### Fase 0 - contratos de provedor

1. Confirmar em homologação a tokenização, autorização, recusa, parcelamento, consulta e webhook de cada conta de seller.
2. Fechar o contrato público e a chave de idempotência da tentativa antes de criar qualquer migration.
3. Homologar na ordem Pagar.me, Efí e Mercado Pago. A ordem reduz a adaptação de backend no primeiro provedor e valida depois os dois modelos de tokenização restantes.

### Fase 1 - CT API e Dashboard

1. Criar migrations aditivas de charge e tentativa.
2. Estender `IntegrationGatewayCredentialRules`, criação/edição de integração e o formulário/API do Dashboard para os campos de cartão.
3. Acrescentar `card` à disponibilidade e retornar somente configuração pública da integração selecionada.
4. Implementar criação de charge sem token, criação idempotente de tentativa, serialização segura e transições de estado.

### Fase 2 - Edge, Commerce e Front Checkout

1. Ajustar a disponibilidade do Edge para combinar produto elegível e capacidade CT de cartão.
2. Ajustar Commerce V2 para criar venda pendente transparente de cartão sem validar gateway padrão, Cielo/Pagar.me PSP ou onboarding do cartão normal.
3. Manter as regras de produto `ONE_TIME`, seller com CT habilitado, limite de parcelas e venda pendente duplicada.
4. Criar tokenizadores por integração no Front Checkout. Remover logs de token e impedir fallback de PAN/CVV para Edge ou Commerce.
5. Enviar endereço, documento e telefone conforme o contrato do provedor.

### Fase 3 - Worker, status e webhooks

1. Implementar clientes de cartão Mercado Pago, Pagar.me e Efí no worker, cada um com criação e consulta de status.
2. Atualizar a normalização de resultado para aprovar imediatamente quando o provedor retornar aprovado.
3. Validar os resolvers existentes de Pagar.me e Mercado Pago com eventos de cartão; estender o resolver Efí, hoje Pix, e manter polling como reconciliação.
4. Cobrir recusa e nova tentativa na mesma charge, sem uma segunda venda ou cobrança paralela.

## Rollout e rollback

1. Publicar migrations e contratos retrocompatíveis com `card` indisponível.
2. Habilitar cartão por provedor somente após homologação de uma integração de teste.
3. Começar com sellers internos, observando tentativa, resultado, status final e confirmação no Commerce V2.
4. Em rollback, retirar `card` da disponibilidade. Charges já criadas continuam consultáveis e confirmáveis; migrations aditivas permanecem.

## Casos de aceite

| Caso | Resultado esperado |
| --- | --- |
| Seller sem integração de cartão ativa | `card` não aparece nem é aceito. |
| Produto `ONE_TIME` elegível | Venda pendente e uma única charge são criadas para a integração selecionada. |
| Aprovação imediata | Charge e venda ficam `paid` uma vez, com um único efeito financeiro/entrega. |
| Pendente e webhook/polling pago | A mesma confirmação ocorre uma vez. |
| Recusa e token novo | Nova tentativa na mesma charge; não duplica venda, pedido, item financeiro ou notificação. |
| Reenvio da mesma tentativa | Idempotência impede nova cobrança no provedor. |
| Token e dados de cartão | Não aparecem em MariaDB, Redis de resultado, logs, auditoria ou resposta HTTP. |
| Woovi e Kiwify | Não anunciam nem aceitam `card`. |

## Tasks executáveis

1. Aprovar este plano e o contrato de tentativa.
2. Criar branch por repositório a partir de `main`; não desenvolver sobre os branches de feature existentes.
3. Implementar CT API e migrations com testes de estado, tentativa e sanitização.
4. Implementar Dashboard, Edge, Commerce e Front Checkout com testes de contrato.
5. Implementar worker e testes de adaptador com respostas aprovadas, pendentes e recusadas de cada provedor.
6. Criar documento de deploy e executar homologação ponta a ponta antes de ativar sellers.

## Referências

- `services-checkout-transparent-api/app/Infrastructure/Queue/JobPayloadFactory.php`
- `services-checkout-transparent-api/app/Process/GatewayResultQueueProcess.php`
- `services-checkout-transparent-api/app/Application/UseCase/Charge/ConfirmChargePaymentUseCase.php`
- `services-checkout-transparent-worker/app/Application/UseCase/Payment/AbstractCreatePaymentUseCase.php`
- `edge-checkout-transparent-webhook/edge/edge-checkout-transparent-webhook/app/Infrastructure/Webhook/Resolver/`
- `services-banking-v2/app/Infrastructure/Gateways/PagarmePsp/Client/PagarmePspCardClient.php`
- `services-banking-v2/app/Infrastructure/Gateways/EfiBank/Client/EfiBankChargeCardClient.php`
- [Mercado Pago: Checkout API](https://www.mercadopago.com.br/developers/pt/reference/online-payments/checkout-api/overview)
- [Pagar.me: pagamento com cartão](https://docs.pagar.me/reference/cart%C3%A3o-de-cr%C3%A9dito-1)
- [Efí: API de cobranças por cartão](https://dev.efipay.com.br/docs/api-cobrancas/cartao/)
