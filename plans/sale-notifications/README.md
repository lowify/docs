# Plano — Comunicações de venda

## Objetivo

Unificar as comunicações oficiais de venda em dois fluxos: entrega pós-compra e recuperação de venda pendente (RDC). Ambos usam WhatsApp Meta e e-mail transacional, configuração por produto/afiliação e créditos monetários pré-pagos administrados pela Wallet.

Evolution será descontinuado. Checkout Lowify e Checkout Transparente seguem as mesmas regras de créditos; o meio de pagamento da venda não altera o custo da comunicação.

## Ordem de desenvolvimento

1. [Configuração por produto](01_PRODUCT_CONFIGURATION_TASKS.md)
2. [Account: acesso e preços](02_ACCOUNT_ACCESS_AND_PRICING_TASKS.md)
3. [Wallet: créditos](03_COMMUNICATION_CREDITS_TASKS.md)
4. [Banking V2: recarga PIX](04_PIX_TOPUPS_TASKS.md)
5. [Commerce: tentativas e dispatch](05_COMMERCE_DISPATCH_TASKS.md)
6. [Notification: envio e callbacks](06_NOTIFICATION_CALLBACKS_TASKS.md)
7. [Edges, Dashboard e operação](07_OPERATIONS_AND_DASHBOARD_TASKS.md)

## Responsabilidade e acesso

| Contexto | Quem configura | Quem paga créditos |
| --- | --- | --- |
| Venda própria | Produtor | Produtor (`owner_user_id`) |
| Venda de afiliado | Afiliado, por afiliação/produto | Afiliado (`owner_user_id`) |
| Reenvio do seller | Seller responsável | `owner_user_id` |
| Reenvio por colaborador | Colaborador autorizado | `owner_user_id` |
| Reenvio por admin 1, 2 ou 4 | Admin | Gratuito |

Account é a fonte de verdade das variáveis e feature flags do usuário. O Dashboard chega aos serviços apenas por:

```text
dashboard-seller → edge-gateway → edge-public-api → serviço responsável
```

## Créditos de comunicação

- Há uma carteira monetária única por `owner_user_id`, compartilhada por RDC e entrega pós-compra.
- O custo efetivo é configurável por usuário, com padrão global e override em Account.
- Antes de um envio cobrável, a Wallet bloqueia o valor. Sem crédito disponível, o canal pago não é enviado.
- Após confirmação do provedor, a Wallet consome o crédito bloqueado. Em falha, libera o bloqueio.
- O bloqueio de WhatsApp de entrega dura até 10 minutos, configurável. Após liberar, uma confirmação Meta tardia ainda consome créditos; a carteira pode ficar negativa.
- Recargas são pacotes PIX: valor pago, crédito base e crédito bônus. Banking V2 identifica a cobrança de recarga e solicita o crédito à Wallet após confirmação.
- Falta de crédito gera aviso por e-mail e WhatsApp ao responsável, com cooldown de 12 horas por usuário.

## Entrega pós-compra

O produto ou a afiliação pode ativar “enviar entrega por WhatsApp”. A regra vale para o produto principal; order bumps não decidem o fluxo.

```text
Venda paga
  → resolve regra do produtor/afiliado e owner_user_id
  → se WhatsApp ativo e houver crédito: cria tentativa e bloqueia crédito
  → envia WhatsApp Meta
  → confirmação Meta até 3 min: consome crédito e envia e-mail pelo provider secondary
  → falha Meta: libera crédito e envia e-mail pelo provider primary
  → sem retorno em 3 min: envia primary, marca timeout e mantém bloqueio até 10 min
  → confirmação tardia: consome crédito, marca tardia e não envia secondary
```

Quando WhatsApp está desligado, não há telefone, não há crédito ou o enqueue falha, o e-mail segue pelo provider primary. Não há envio WhatsApp nesses casos.

`primary` e `secondary` são configurações do fluxo `sale_delivery`, inicialmente SendGrid e Mailtrap, respectivamente; os nomes dos provedores não pertencem à regra de negócio.

## RDC

- Elegível apenas para vendas `pending`, até duas horas após criação.
- Usa somente `tbl_sale_items.item_type = principal`.
- Uma ou duas etapas; no mínimo 10 minutos entre elas; cada etapa pode usar e-mail, WhatsApp ou ambos.
- Cada canal cria um dispatch cobrável e usa a mesma carteira de créditos.
- Não há retry/fallback automático na primeira versão; contato ausente ou falta de crédito registra `skipped`.
- Ambos os templates contêm `/rdc?cod={order}`.

## Registros

`sale_delivery_attempts` representa a operação de entrega (inicial ou reenvio): `sale_id`, `owner_user_id`, `is_resend`, autor, modo de cobrança e timestamps.

`sales_delivery` representa cada canal concreto da tentativa e mantém a referência da mensagem no Notification. O `sales_delivery.id` é enviado no payload/correlation e retorna no callback; ele é também a referência idempotente da Wallet para WhatsApp.

`sale_recovery_dispatches` e `sale_recovery_dispatch_events` continuam sendo o registro do RDC, agora com débito/bloqueio na carteira de créditos em vez de extrato/fatura.

## Inventário técnico de dados

| Serviço | Tabela/estrutura nova ou alterada | Forma de deploy |
| --- | --- | --- |
| Commerce V2 | `product_sale_delivery_rules`, `sale_delivery_attempts`, evolução de `sales_delivery`, regras e eventos de RDC | SQL manual |
| Account | chaves globais em `system_vars` e overrides em `user_system_vars` | SQL manual + casos de uso/API |
| Wallet | `communication_credit_packages`, `communication_credit_entries`, `communication_credit_alerts` | SQL manual |
| Banking V2 | purpose `communication_credit_topup` em cobranças PIX existentes | confirmar migration/schema apenas se o purpose for enumerado |
| Notification | correlação por `sales_delivery.id`/dispatch e fila genérica de resultados | migrations do serviço se o schema de mensagem exigir |

## Reenvios

- Seller reenvia o pack. Se WhatsApp estiver inativo na regra aplicável, envia somente e-mail. É cobrável quando houver WhatsApp efetivamente enviado.
- Colaborador segue o mesmo fluxo cobrável do seller.
- Admin 1, 2 ou 4 seleciona e-mail, WhatsApp ou ambos e nunca gera cobrança. Canais escolhidos manualmente são independentes: não há fallback automático.

## Decisões ainda pendentes

- Administração dos pacotes de recarga (recomendado: admin 1 e 2).
- Expiração de créditos e política de estorno de recarga PIX.

## Critérios transversais

- Toda operação financeira e todo callback deve ser idempotente pela referência da tentativa/dispatch.
- Account, Commerce, Wallet, Banking V2, Notification e edges devem preservar seus limites de responsabilidade.
- O Dashboard não acessa tabelas de serviço diretamente.
- Dados de preço e saldo pertencem à Wallet/Account, não a `sales_delivery` ou aos dispatches.
