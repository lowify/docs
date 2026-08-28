# Fase 5 — Commerce: tentativas, RDC e dispatch

## SQL manual e entidades

| Estrutura | Alteração técnica |
| --- | --- |
| `sale_delivery_attempts` | Criar pai da entrega/reenvio: `sale_id`, `owner_user_id`, `is_resend`, `author_type`, `author_user_id`, `chargeable`, `idempotency_key`, timestamps. |
| `sales_delivery` | Adicionar `sale_delivery_attempt_id`, `owner_user_id`, `is_late_delivery`, `status_timeout_at` e `hold_timeout_at`; tornar `reference_id` anulável antes do sender; ampliar enum de status. |
| `sale_recovery_dispatches` | Manter evolução planejada: produto, regra, owner, afiliação, canal, skip reason e unicidade venda/etapa/canal. |
| `sale_recovery_dispatch_events` | Criar timeline append-only, referência de provider, reason e metadata. |

Antes de criar a unicidade `(sale_delivery_attempt_id, type)`, inventariar reenvios históricos. Nenhuma linha atual deve ser sobrescrita.

## Entrega pós-compra

| Ponto atual | Pendência |
| --- | --- |
| `ProcessPaidSaleEventDeliveryUseCase` | Resolver produto principal, owner, regra de delivery e preço no Account; criar tentativa e linhas de canal antes do enqueue. |
| `SaleDeliveryPayloadBuilder` / `SaleDeliveryModeResolver` | Preservar payload/template atual, adicionando IDs de tentativa/entrega na correlação. |
| Novo `CreateSaleDeliveryAttemptUseCase` | Criar tentativa idempotente inicial/reenvio e determinar `chargeable`. |
| Novo `ExecuteSaleDeliveryChannelUseCase` | Solicitar hold Wallet, criar mensagem Meta/e-mail e atualizar estado. |
| Novo processo de timeout | Usar `status_timeout_at` e `hold_timeout_at` congelados na criação; aos 3 min enviar primary e aos 10 min liberar hold, sempre de forma idempotente. |
| `SaleDeliveryRepository` | Buscar por ID, atualizar status/transições e listar por venda/tentativa; não usar só type/reference. |

### Reenvio

- Seller e colaborador chamam `ResendSaleDeliveryPackUseCase`; resolve a regra atual e só inclui WhatsApp se estiver ativo.
- Admin 1/2/4 chama `ResendSaleDeliveryChannelsUseCase`; canais explícitos, `chargeable = false`, sem fallback.
- A autorização é resolvida em Commerce a partir de JWT/contexto encaminhado; `author_type` não é aceito sem validação.

## RDC

| Ponto atual | Pendência |
| --- | --- |
| `ProcessPendingSaleEventSaleRecoveryUseCase` | Trocar regra global por produto principal + owner e criar dispatch por etapa/canal. |
| `ExecuteSaleRecoveryDispatchUseCase` | Revalidar pending/janela/contato/flag, pedir hold Wallet e enviar canal oficial. |
| Scheduler/fila de recovery | Preservar locking/idempotência; cancelar/skip sem crédito ou elegibilidade. |
| `RegisterSaleRecoveryEventUseCase` | Aplicar callback, registrar evento e consumir/liberar créditos. |

## Cliente Wallet e tempos

- Criar client autenticado/retry seguro para hold, release e consume; referência sempre é `sales_delivery.id` ou `sale_recovery_dispatches.id`.
- Não repetir envio em caso de erro de Wallet ou falta de crédito.
- Delivery: `status_timeout_seconds` (180) e `hold_timeout_seconds` (600) pertencem a `config/autoload/sale_delivery.php`; Commerce os grava como deadlines sem recalcular tentativa antiga.
- Commerce escolhe `primary|secondary` no payload de e-mail; não envia o nome do provedor como regra de negócio.
- Meta tardia após hold liberado: consume tardio; saldo pode ficar negativo.

## Rotas necessárias

| Rota de domínio | Responsabilidade |
| --- | --- |
| `POST /sales/{sale_id}/delivery/resend` | seller/colaborador reenvia pack. |
| `POST /admin/sales/{sale_id}/delivery/resend` | admin reenvia canais selecionados. |
| `GET /sales/{sale_id}/communications` | histórico com visibilidade do owner/admin. |
| `GET /sale-notifications/status` | cards e lista de RDC/entregas. |

Public API/Gateway expõem essas rotas ao Dashboard; Commerce continua dono das regras.

## Critérios de aceite

- [ ] Venda paga cria uma tentativa inicial única.
- [ ] Reenvio cria tentativa nova, nunca reutiliza o `sales_delivery.id` original.
- [ ] Hold é ligado à referência correta e não duplica consumo.
- [ ] Fluxos de RDC e entrega continuam separados, compartilhando apenas créditos.
