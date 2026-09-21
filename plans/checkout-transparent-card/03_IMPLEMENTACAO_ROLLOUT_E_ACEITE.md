# Implementação, rollout e aceite

## Ordem de implementação

### Fase 0 - contratos de provedor

1. Confirmar em homologação a tokenização, autorização, recusa, parcelamento, consulta e webhook de cada conta de seller.
2. Fechar o contrato público e a chave de idempotência da tentativa antes de criar qualquer migration.
3. Homologar Mercado Pago primeiro, seguido por Pagar.me e Efí. Mercado Pago estabelece o padrão de Public Key, tokenização no navegador e criação por Orders; os demais adaptadores reutilizam o contrato comum.

### Fase 1 - CT API e Dashboard

1. Criar migrations aditivas de método da integração, chaves por método, `charges.method`, parcelas e tentativa.
2. Implementar e executar `integration-payment-methods:backfill-pix` em homologação antes de a seleção ler as tabelas novas.
3. Estender `IntegrationGatewayCredentialRules`, criação/edição de integração e o formulário/API do Dashboard para os campos de cartão por método.
4. Acrescentar `card_credit` à disponibilidade e retornar somente configuração pública da integração selecionada.
5. Implementar criação de charge sem token, criação idempotente de tentativa, serialização segura e transições de estado.

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

## Marco Mercado Pago

O Mercado Pago foi implementado como primeiro adaptador de cartão. O fluxo validado é:

```text
Public Key por método -> Mercado Pago.js tokeniza no navegador
-> tentativa idempotente -> Orders no worker -> resultado sanitizado
-> confirmação idempotente de charge, venda e entrega
```

- O cartão usa `payment_method_id` explícito. A adaptação converte o código visual `mastercard` para `master` antes de criar o pedido no Mercado Pago.
- Aprovação imediata não aguarda o ciclo de QR Code ou uma confirmação manual: o resultado do worker confirma a venda no fluxo já existente.
- Recusas do provedor ficam registradas na tentativa, sem token ou dados brutos do cartão.
- A Public Key é configurada pela ação de edição da integração. O Access Token não é solicitado nem exposto nessa tela.

## Próximos adaptadores

Os próximos adaptadores devem reutilizar o endpoint de tentativa, o envelope de fila, a separação de configuração pública e credenciais privadas, e a confirmação centralizada. Cada adaptador adiciona apenas:

1. Tokenizador e configuração pública próprios.
2. Payload de criação e consulta de status do provedor.
3. Mapeamento entre bandeira apresentada e identificador aceito pelo provedor, quando necessário.
4. Casos de aprovação, pendência, recusa e reenvio idempotente.

## Marco Pagar.me

O Pagar.me foi implementado no mesmo contrato de tentativa, sem reutilizar split ou qualquer configuração do PSP da Lowify:

1. A Public Key fica em `card_credit`; a `secret_key` privada é herdada da integração quando já existe.
2. O navegador tokeniza o cartão diretamente; PAN e CVV não seguem para Commerce V2.
3. O worker cria `POST /orders` com `credit_card.card_token`, parcelas, `auth_and_capture` e endereço de cobrança.
4. O status é consultado em `GET /charges/{id}` pelo polling existente.

O fluxo foi exercitado com mock HTTP isolado: aprovação imediata, recusa imediata e pendência posteriormente aprovada por polling.

## Marco Efí

1. O método `card_credit` recebe o Identificador de conta da Efí; Client ID, Client Secret e certificado permanecem privados na integração.
2. O Front Checkout tokeniza no navegador com `payment-token-efi` e envia somente o token transitório à tentativa.
3. O worker autentica a API Cobranças em `/v1/authorize` e cria a cobrança One Step em `/v1/charge/one-step`.
4. A cobrança recebe nome, CPF, e-mail e telefone da pessoa pagadora. Endereço não é exigido por esse fluxo.
5. A aprovação imediata foi confirmada ponta a ponta: charge, venda e entrega passaram para `paid` uma única vez.

## Rollout e rollback

1. Publicar migrations e contratos retrocompatíveis com `card_credit` indisponível.
2. Executar o backfill Pix e validar contagem de integrações, métodos e chaves antes de a leitura nova ser ativada.
3. Habilitar cartão por provedor somente após homologação de uma integração de teste.
4. Começar com sellers internos, observando tentativa, resultado, status final e confirmação no Commerce V2.
5. Em rollback, retirar `card_credit` da disponibilidade. Charges já criadas continuam consultáveis e confirmáveis; migrations aditivas permanecem.

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
