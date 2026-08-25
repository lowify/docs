# Recuperação de vendas por canais oficiais

## Objetivo

Permitir que produtor ou afiliado configure, por produto, até duas etapas de recuperação de uma venda pendente. Cada etapa pode disparar e-mail, WhatsApp oficial, ou ambos. A feature utiliza Meta/WhatsApp Business Platform e e-mail transacional. O fluxo Evolution será descontinuado.

Este plano descreve a implementação. Não cria migrations, rotas ou telas por si só.

## Ordem de desenvolvimento

Os documentos abaixo são ordenados por dependência. Uma fase só deve avançar para produção depois dos critérios de aceite da anterior, salvo tarefas técnicas sem dependência explícita.

1. [Gestão por produto](01_PRODUCT_MANAGEMENT_TASKS.md) — modelo de configuração, APIs e telas de produtor/afiliado.
2. [Gestão de taxa](02_FEE_MANAGEMENT_TASKS.md) — preço padrão, override por usuário e gestão administrativa.
3. [Acesso, dispatch e histórico](03_ACCESS_DISPATCH_AND_HISTORY_TASKS.md) — feature flag, agendamento, templates, callbacks, fila genérica e detalhe da venda.
4. [Status e observabilidade](04_STATUS_AND_OBSERVABILITY_TASKS.md) — página de RDC, consultas, métricas e suporte.
5. [Liquidação](05_SETTLEMENT_TASKS.md) — reservas de saldo, extrato Lowify e itens de fatura do Checkout Transparente.

## Regras de negócio confirmadas

| Tema | Regra |
| --- | --- |
| Elegibilidade | Apenas venda `pending`, independentemente do meio de pagamento, até duas horas após sua criação. |
| Produto | Usar exclusivamente `tbl_sale_items.item_type = 'principal'`; order bumps e demais itens não participam. |
| Responsável | Venda própria: produtor. Venda com `sales.affiliate_id`: afiliado da venda; a regra do produtor não é aplicada. |
| Configuração | Individual por produto, tanto para produtor quanto para afiliado. |
| Etapas | Uma ou duas. O segundo atraso deve ser pelo menos 10 minutos maior que o primeiro; ambos dentro de 120 minutos. |
| Canais | Cada etapa aceita `email`, `whatsapp` ou ambos e gera um dispatch por canal. |
| Conteúdo | Ambos incluem `/rdc?cod={order}`. WhatsApp usa template Meta aprovado; e-mail usa template Twig salvo no banco. |
| Reenvio | Não haverá retry, reenvio nem fallback automático de canal na primeira versão. |
| Corrida com pagamento | Se a venda for paga depois da validação e durante o envio, a mensagem permanece enviada. |
| Contato ausente | Registrar `skipped`; não enviar nem cobrar. |
| Consentimento | Controle interno de opt-in/opt-out. |
| Rollout | Desligada por padrão. Account é a fonte de verdade do estado efetivo por usuário; admins 1 e 2 controlam o override em Restrições. |

## Configuração e registros

### Regras por produto

`product_sale_recovery_rules`

- `product_id`, `owner_user_id`, `owner_type` (`producer|affiliate`), `affiliate_id` e `is_enabled`.
- Uma regra pertence ao produtor ou à afiliação do afiliado. Para afiliado, validar a afiliação ativa antes de salvar.
- Unicidade: `(product_id, owner_type, owner_user_id, affiliate_id)`.

`product_sale_recovery_rule_steps`

- Uma ou duas etapas por regra: `step` (`1|2`), `delay_minutes` e `is_enabled`.
- Unicidade: `(product_sale_recovery_rule_id, step)`.

`product_sale_recovery_rule_step_channels`

- Canais da etapa: `email|whatsapp`.
- Unicidade: `(product_sale_recovery_rule_step_id, channel)`.

### Dispatch e eventos

Evoluir `sale_recovery_dispatches`. A unidade é **venda + etapa + canal**.

- Manter: `id`, `sale_id`, `stage`, `status`, `scheduled_for`, timestamps.
- Acrescentar: `product_id`, `product_sale_recovery_rule_id`, `owner_user_id`, `affiliate_id`, `channel` e `skip_reason`.
- Migrar a semântica de `user_id` para `owner_user_id`.
- `channel` aceita somente `email|whatsapp`.
- Trocar a unicidade para `(sale_id, stage, channel)`.
- O dispatch congela produto, responsável, canal e horário ao ser agendado; mudanças posteriores na regra não o alteram.

Criar `sale_recovery_dispatch_events` como trilha append-only. Cada evento guarda `event_type`, `occurred_at`, `reason`, `metadata` e, quando houver mensagem no provedor, `provider_reference_type` + `provider_reference_id`. Esses campos apontam para o registro concreto da mensagem (`email_single` ou `whatsapp_meta`), sem inflar o dispatch com datas e referências de cada provedor.

Estados esperados do dispatch: `scheduled`, `processing`, `queued`, `sent_to_provider`, `confirmed`, `failed`, `skipped` e `canceled`.

## Taxa e liquidação

- A taxa é única por recuperação e igual para e-mail e WhatsApp.
- A chave é `sale_recovery_unit_price`, com valor padrão em `system_vars` e override em `user_system_vars`.
- Os dados e as variáveis efetivas do usuário, inclusive `sale_recovery_feature_enabled`, pertencem ao Account. Commerce não replica nem persiste esse estado.
- O valor efetivamente movimentado pertence ao serviço financeiro; não deve ser copiado para `sale_recovery_dispatches`.
- Checkout Lowify sem split: reservar saldo antes de iniciar o envio. Sucesso gera débito no extrato e encerra a reserva; falha/recusa libera a reserva; ausência de retorno a mantém bloqueada.
- Checkout Transparente: após sucesso do envio, criar item `sale_recovery` na fatura. Não há reserva de saldo nesse caminho.

## Fluxo alvo

```text
Venda pending criada
  → localizar item principal e responsável (produtor ou afiliado)
  → consultar Account para validar a feature flag efetiva e localizar a regra do produto
  → criar dispatches por etapa/canal
  → scheduler entrega o dispatch vencido
  → worker revalida pending, janela, contato, template e acesso
  → Lowify: reserva saldo; Transparente: segue sem reserva
  → cria mensagem oficial com correlação do dispatch
  → notification publica resultado na fila genérica
  → Commerce registra evento e atualiza dispatch
  → sucesso: liquida reserva ou cria item de fatura
  → falha: libera reserva Lowify; sem retorno mantém bloqueio
```

O novo resultado de notificação deve usar a fila genérica `sales:notification:results`, com `context` (`sale_delivery|sale_recovery`), `subject_id`, canal, referência concreta da mensagem, status e erro. O consumidor do Commerce encaminha `sale_delivery` ao fluxo existente e `sale_recovery` ao registro de eventos do RDC.

## Acesso do Dashboard aos serviços

Toda chamada do `dashboard-seller` para a feature segue este caminho:

```text
dashboard-seller → edge-gateway → edge-public-api → serviço responsável
```

O Dashboard não chama `services-commerce-v2`, `services-account` nem `services-wallet` diretamente. `edge-public-api` aplica o contrato público/autorização e encaminha para o serviço dono do dado; `edge-gateway` apenas expõe a rota ao Dashboard. Comunicação interna entre serviços pode usar o contrato autenticado próprio.

## Reaproveitamentos e limites

| Elemento | Reuso |
| --- | --- |
| `ProcessPendingSaleEventUseCase`, scheduler e fila de recovery | Reaproveitar infraestrutura de agendamento, locking e idempotência; substituir a resolução global por regra produto/responsável no novo fluxo. |
| `sale_recovery_dispatches` | Evoluir para registrar exclusivamente os canais oficiais. |
| `services-notification` e callbacks atuais de `sales_delivery` | Reaproveitar sender → webhook → fila → consumer, com correlação por `dispatch_id`. |
| `sales_delivery` | Não usar como entidade de RDC; permanece exclusivamente para entrega pós-pagamento. |
| `WalletService` e disponibilidade de extrato | Estender para reservas de RDC e novo tipo de débito. |
| Billing do Checkout Transparente | Reusar a criação idempotente de `billing_items`; expor endpoint interno para item externo. |

## Visibilidade

- No detalhe de venda normal, um RDC de afiliado aparece apenas para o afiliado responsável; o produtor não o vê.
- Em `admin_sale_detail`, admin sempre vê o histórico e o responsável.
- A página de status mostra somente canais oficiais e respeita `owner_user_id`; admin pode consultar todos.

## Fora de escopo inicial

- Retry, reenvio manual e fallback de WhatsApp para e-mail.
- Compatibilidade operacional com Evolution.
- Cobrança sem confirmação de envio.

## Critérios transversais

- Reprocessamentos não podem duplicar dispatch, evento, reserva, débito ou item de fatura.
- A autorização deve ser aplicada ao ler/salvar regras e novamente ao agendar/enviar.
- O produtor nunca herda ou enxerga a configuração/recuperação particular do afiliado.
- Cada mudança de estado relevante deve ser rastreável por evento e referência do provedor.
