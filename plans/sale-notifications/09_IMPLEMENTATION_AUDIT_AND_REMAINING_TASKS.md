# Auditoria — implementação e pendências de comunicações de venda

> Revisado em: 2026-09-08
> Fonte: código das branches remotas `feat/sale-notifications`.
> Critério: “implementado” significa código confirmado; não significa SQL aplicado, teste executado ou homologação concluída.

## Decisões de produto confirmadas

- O novo RDC não usa Evolution. Os canais oficiais são WhatsApp Business Platform/Meta e e-mail transacional.
- RDC atende somente venda `pending`, até duas horas após a criação, usando o item com `item_type = principal`.
- RDC possui uma ou duas etapas, separadas por pelo menos dez minutos. Cada etapa pode usar e-mail, WhatsApp ou ambos.
- E-mail não é obrigatório no RDC e é cobrado no mesmo valor unitário do WhatsApp de RDC.
- Somente o e-mail da entrega pós-pagamento é obrigatório e gratuito.
- Venda de afiliado usa apenas as regras e os créditos do afiliado responsável; nunca herda a configuração do produtor.
- O owner e o autor de reenvio são resolvidos no backend; não são confiados ao browser.
- A confirmação financeira de e-mail e WhatsApp é `sent_to_provider`; `delivered` e `read` são informativos.
- Toda comunicação paga tenta créditos de comunicação primeiro. Fora do Checkout Transparente, pode usar saldo disponível do seller como fallback apenas se Account permitir para o owner.
- Uma tentativa usa uma única fonte de funding; não existe bloqueio parcial entre créditos e saldo.

## Implementado por fase

### Fase 1 — regras de produto e afiliação

Implementado no Commerce V2:

- tabelas/regras `product_sale_delivery_rules`, `product_sale_recovery_rules`, etapas e canais;
- modelos, repositórios e use cases de leitura/gravação para produtor e afiliado;
- inclusão das regras no create/update e no form-data de produto;
- DTO público de configurações, com disponibilidade e preço efetivo;
- validação de duas etapas, intervalo mínimo e máximo de 120 minutos;
- summary em lote para a lista de produtos.

Implementado no Dashboard Seller:

- tabela de entrega e RDC no card “Preço e Entrega” do formulário de produto;
- toggle de canais, preços somente leitura e stepper de minutos;
- componentes base `InputToggle`, `InputStepper` e `SettingToggle`.

Pendente:

- tela e payload de regras no contexto da afiliação;
- badge/summary na listagem de produtos;
- corrigir a regra que exige e-mail na primeira etapa do RDC;
- corrigir o Dashboard que apresenta e-mail de RDC como gratuito.

### Fase 2 — Account: flag e preço

Implementado:

- `SystemVar`/`UserSystemVar`, repositórios e serviço genérico;
- `SaleNotificationSettingsService` com global, override e efetivo;
- chaves de flag, habilitação WhatsApp de entrega e preços unitários;
- endpoints internos e administrativos no Account;
- testes unitários do serviço.

Pendente:

- expor e proteger as rotas administrativas pelo Public API/Gateway para perfis 1 e 2;
- telas administrativas para flag global, overrides e preços;
- testes de integração/autorização dessas rotas.
- **Concluído localmente, pendente de commit/deploy:** `sale_notifications_allow_seller_balance` é preferência somente por usuário, com default efetivo `true`, sem exposição no contrato global e com testes unitários de override.

### Fase 3 — Wallet: créditos

Implementado:

- pacotes, saldos, compras, razão, alertas e outbox;
- compra PIX e compra por saldo normal;
- consulta de saldo/pacotes, polling da compra e CRUD interno de pacotes;
- hold, release e consume idempotentes por referência comercial;
- expiração de compras e holds;
- alerta de crédito insuficiente em stream para Notifications.

Pendente:

- aplicar e validar o SQL manual no banco da Wallet;
- testes transacionais de compra, callback repetido, concorrência, expiração e saldo negativo tardio;
- teste de retry/concorrência da outbox e da expiração;
- interface administrativa de pacotes;
- confirmação de envio/retry do alerta de crédito insuficiente.
- hold, release e consume idempotentes do saldo disponível normal do seller, incluindo confirmação tardia e expiração.

### Fase 4 — Banking V2: recarga PIX

Implementado:

- purpose `communication_credit_topup` e vínculo entre PIX e UUID da compra;
- consumer de criação PIX com validação de assinatura e reuso idempotente da cobrança;
- repasse de expiração da Wallet ao PIX;
- confirmação de PIX pago para a Wallet.

Pendente:

- testes de criação, reentrega, pagamento tardio, expiração e Wallet indisponível;
- validação de todas as configurações de ambiente e providers em homologação;
- confirmar migrations aplicadas no banco Banking V2.

### Fase 5 — Commerce: entrega, RDC e outcomes

Implementado:

- `sale_delivery_attempts`, evolução de `sales_delivery` e eventos de RDC;
- criação de tentativa WhatsApp com owner, hold e deadlines de 3/10 minutos;
- fallback de e-mail primary em falha/timeout Meta e secondary após confirmação Meta;
- consumo/liberação de crédito e tratamento de confirmação tardia;
- agendamento RDC por produto principal, owner produtor/afiliado e canal;
- execução de dispatch Meta/e-mail, cancelamento de venda não pending e timeline de eventos;
- envelope `notification_outcome` no consumer existente `sales:delivery:actions`;
- reenvio do pack, com tentativa nova e gratuidade para admin.

Pendências e correções obrigatórias:

- Persistir funding em `sales_delivery` e `sale_recovery_dispatches`: fonte, estado, referência de hold e preço congelado.
- RDC por e-mail precisa criar hold antes do envio, liberar em falha e consumir em `sent_to_provider`; hoje só WhatsApp usa crédito.
- Implementar prioridade crédito → saldo, bloqueando saldo somente fora do Checkout Transparente e com flag Account ativa.
- Trocar consumo de WhatsApp em `delivered|read` por `sent_to_provider`, sem cobrar novamente em eventos posteriores.
- Remover a exigência de e-mail na etapa 1 do RDC.
- Reenvio administrativo precisa receber seleção explícita de e-mail/WhatsApp/ambos, sem fallback e sem cobrança.
- Reenvio seller/colaborador deve refletir todos os dados de autor e cobrança no histórico.
- Validar que `item_type = principal` é o valor efetivo de todos os itens de venda legados.
- Cobrir com testes os estados Meta fora de ordem, timeout e confirmação tardia.

### Fase 6 — Notifications e webhook

Implementado:

- templates Twig de RDC e alerta de crédito insuficiente;
- providers semanticamente `primary`/`secondary` para e-mail de entrega;
- outcomes genéricos por `sales_delivery.id` ou dispatch RDC;
- mapeamento Meta `sent` → `sent_pending`, `delivered`, `read` e `failed`;
- remoção de metadados internos antes da chamada Meta;
- consumer de alerta de crédito insuficiente.

Pendente:

- testes de callback duplicado, fora de ordem e tardio;
- teste de correlação de e-mail/RDC e de falha antes de referência do provider;
- validar que todos os outcomes de e-mail RDC chegam ao Commerce para permitir consume/release;
- validar templates Meta aprovados e variáveis de ambiente em homologação.

### Fase 7 — edges, telas e operação

Implementado:

- Gateway e Public API encaminham saldo, pacotes, compras, polling, summaries, status, comunicações e reenvio simples;
- Public API resolve o usuário pelo JWT nas operações de crédito;
- webhook normaliza status Meta e publica na fila de status.

Pendente:

- rotas administrativas Account/pacotes com autorização 1 e 2;
- endpoint e UI de reenvio admin por canais;
- página de créditos, pacotes, recarga PIX e polling no Dashboard;
- página de status de RDC/entregas;
- timeline em `sale_detail` e `admin_sale_detail`;
- configuração de afiliação no Dashboard;
- summaries/badges de produto;
- testes de autorização seller, afiliado, colaborador e admin;
- métricas, consultas operacionais e validação de logs estruturados.

## Ordem recomendada para retomada

1. Implementar a matriz de funding: Account flag, hold de saldo no Wallet, schema de funding e seleção no Commerce.
2. Corrigir RDC por e-mail e mover o consume de todos os canais para `sent_to_provider`.
3. Criar testes de unidade/integrados para Wallet, Banking, Commerce, Notifications e webhook antes de expandir fluxos.
4. Aplicar schema em ambiente controlado e executar validação de integração PIX + Redis + callback Meta.
5. Implementar reenvio administrativo por canais e timeline de venda.
6. Implementar telas de créditos/status e administração de flags, preços e pacotes.
7. Atualizar os checklists das fases após cada bloco validado.

## Referências de revisão

- `services-commerce-v2/app/Application/UseCase/Sale/ProcessPaidSaleEventDeliveryUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/ExecuteSaleRecoveryDispatchUseCase.php`
- `services-commerce-v2/app/Application/UseCase/Sale/ProcessNotificationOutcomeUseCase.php`
- `services-wallet/app/Application/UseCase/CommunicationCredit/`
- `services-banking-v2/app/Process/CommunicationCreditPurchaseQueueProcess.php`
- `services-notification/app/Service/SaleDeliveryResultQueueService.php`
- `services-notification/app/Process/WhatsappMetaDeliveryStatusQueueProcess.php`
- `edge-webhook/app/Infrastructure/Gateways/WhatsApp/Service/WhatsAppWebhookHandler.php`
