# Plano — Comunicações de venda

## Objetivo

Unificar as comunicações oficiais de venda em dois fluxos: entrega pós-compra e recuperação de venda pendente (RDC). Ambos usam WhatsApp Meta e e-mail transacional, configuração por produto/afiliação e créditos monetários pré-pagos administrados pela Wallet.

Evolution será descontinuado. Toda comunicação paga prioriza créditos de comunicação. Fora do Checkout Transparente, o saldo disponível do seller pode ser usado como fallback quando a conta o autorizar; no Checkout Transparente, a única fonte permitida são créditos de comunicação.

## Ordem de desenvolvimento

1. [Configuração por produto](01_PRODUCT_CONFIGURATION_TASKS.md)
2. [Account: acesso e preços](02_ACCOUNT_ACCESS_AND_PRICING_TASKS.md)
3. [Wallet: créditos](03_COMMUNICATION_CREDITS_TASKS.md)
4. [Banking V2: recarga PIX](04_PIX_TOPUPS_TASKS.md)
5. [Commerce: tentativas e dispatch](05_COMMERCE_DISPATCH_TASKS.md)
6. [Notification: envio e callbacks](06_NOTIFICATION_CALLBACKS_TASKS.md)
7. [Edges, Dashboard e operação](07_OPERATIONS_AND_DASHBOARD_TASKS.md)
8. [Auditoria de implementação e pendências](09_IMPLEMENTATION_AUDIT_AND_REMAINING_TASKS.md)

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

## Fontes de cobrança

- Há uma carteira monetária única por `owner_user_id`, compartilhada por RDC e entrega pós-compra.
- O custo efetivo é configurável por usuário, com padrão global e override em Account.
- Antes de um envio cobrável, Commerce tenta bloquear o valor na Wallet com a prioridade `communication_credit` → `seller_balance`.
- `seller_balance` somente é elegível fora do Checkout Transparente e se `sale_notifications_allow_seller_balance` estiver efetivo para o owner.
- Cada envio possui no máximo uma fonte e um bloqueio. Não é permitido bloquear parcialmente crédito e saldo na mesma comunicação.
- `sent_to_provider` confirma a cobrança para e-mail e WhatsApp: a Wallet consome o bloqueio. Falha antes desse evento ou expiração libera o bloqueio.
- O bloqueio de entrega dura até 10 minutos, configurável. Após liberar, uma confirmação tardia ainda consome a fonte originalmente selecionada; saldo/crédito pode ficar negativo.
- Recargas são pacotes PIX: valor pago, crédito base e crédito bônus. Banking V2 identifica a cobrança de recarga e solicita o crédito à Wallet após confirmação.
- Falta de crédito gera aviso por e-mail e WhatsApp ao responsável, com cooldown de 12 horas por usuário.

## Entrega pós-compra

O produto ou a afiliação pode ativar “enviar entrega por WhatsApp”. A regra vale para o produto principal; order bumps não decidem o fluxo.

```text
Venda paga
  → resolve regra do produtor/afiliado e owner_user_id
  → se WhatsApp ativo: cria tentativa e tenta bloquear crédito; fora do transparente pode usar saldo como fallback
  → envia WhatsApp Meta
  → sent_to_provider: consome a fonte bloqueada e envia e-mail pelo provider secondary
  → falha Meta: libera o bloqueio e envia e-mail pelo provider primary
  → sem retorno em 3 min: envia primary, marca timeout e mantém bloqueio até 10 min
  → confirmação tardia: consome a fonte originalmente escolhida, marca tardia e não envia secondary
```

Quando WhatsApp está desligado, não há telefone, não há fonte disponível/autorizada ou o enqueue falha, o e-mail segue pelo provider primary. Não há envio WhatsApp nesses casos.

Commerce escolhe o modo semântico `primary` ou `secondary` conforme a regra de negócio. Notification mapeia esse modo para o provedor real por env, inicialmente SendGrid e Mailtrap; os nomes dos provedores não pertencem à regra de negócio nem ao Account.

## RDC

- Elegível apenas para vendas `pending`, até duas horas após criação.
- Usa somente `tbl_sale_items.item_type = principal`.
- Uma ou duas etapas; no mínimo 10 minutos entre elas; cada etapa pode usar e-mail, WhatsApp ou ambos.
- Evolution não participa do RDC novo. Os únicos canais são WhatsApp Business Platform/Meta e e-mail transacional.
- E-mail não é obrigatório em nenhuma etapa do RDC. Quando habilitado, e-mail e WhatsApp são cobrados pelo mesmo valor unitário efetivo.
- O único e-mail obrigatório e gratuito é o da entrega pós-pagamento; essa regra não se aplica ao RDC.
- Cada canal de RDC cria um dispatch cobrável e usa a mesma carteira de créditos.
- Não há retry/fallback automático na primeira versão; contato ausente ou falta de crédito registra `skipped`.
- Ambos os templates contêm `/rdc?cod={order}`.

## Registros

`sale_delivery_attempts` representa a operação de entrega (inicial ou reenvio): `sale_id`, `owner_user_id`, `is_resend`, autor, modo de cobrança e timestamps.

`sales_delivery` representa cada canal concreto da tentativa e mantém a referência da mensagem no Notification. Além da referência de provider, congela `funding_source`, `funding_status`, `funding_reference_id` e `unit_price`. O `sales_delivery.id` é enviado no payload/correlation e retorna no callback; ele é a referência idempotente da Wallet.

`sale_recovery_dispatches` e `sale_recovery_dispatch_events` continuam sendo o registro do RDC, com as mesmas colunas de funding. O evento de `sent_to_provider` é a confirmação financeira para os dois canais.

## Inventário técnico de dados

| Serviço | Tabela/estrutura nova ou alterada | Forma de deploy |
| --- | --- | --- |
| Commerce V2 | `product_sale_delivery_rules`, `sale_delivery_attempts`, evolução de `sales_delivery`, regras e eventos de RDC | SQL manual |
| Account | chaves globais em `system_vars`, overrides em `user_system_vars` e preferência por usuário para uso de saldo | SQL manual + casos de uso/API |
| Wallet | créditos de comunicação e holds de saldo disponível do seller | SQL manual |
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
