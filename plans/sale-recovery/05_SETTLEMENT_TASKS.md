# Fase 5 — Liquidação financeira

## Dependências

Depende do resultado idempotente de envio da Fase 3. A reserva Lowify é criada
no início do dispatch, antes da mensagem ir ao provedor; a liquidação só reage
ao resultado confirmado ou falho registrado pelo fluxo de callbacks.

## Regras de liquidação definidas

| Contexto da venda | Cobrança |
| --- | --- |
| Checkout Lowify sem split | Descontar do saldo/extrato do responsável pela recuperação. |
| Checkout Transparente | Inserir item de cobrança na fatura do responsável. |

O caminho é identificado pela mesma regra já usada no Commerce para Checkout Transparente: `checkout_transparent_integration_id > 0` ou gateway `checkout_transparent`. Os demais casos seguem o caminho Lowify sem split.

## Bloqueio de saldo no Lowify

O bloqueio acontece **antes de iniciar o envio**. Cada dispatch de canal cria uma reserva própria; por exemplo, dez envios iniciados resultam em dez valores bloqueados enquanto aguardam o retorno do provedor.

```text
iniciar dispatch
  → verificar saldo disponível
  → criar bloqueio idempotente
  → enviar para Meta/e-mail
  → aprovado/sucesso: debitar o extrato e encerrar o bloqueio
  → recusado/falha: encerrar o bloqueio sem débito
  → sem retorno: manter bloqueio
```

| Resultado | Saldo total | Saldo bloqueado | Saldo disponível |
| --- | --- | --- | --- |
| Reserva criada | não muda | aumenta | diminui |
| Envio aprovado | diminui pelo débito | diminui | mantém o efeito líquido do débito |
| Envio recusado | não muda | diminui | volta a aumentar |
| Sem retorno | não muda | permanece | permanece reduzido |

O bloqueio e o débito usam `sale_recovery_dispatches.id` como chave de idempotência. Reprocessar início, callback ou fila não pode duplicar a reserva nem o lançamento no extrato.

## `services-wallet` — novas responsabilidades

A carteira já calcula disponibilidade como `total - blocked`, mas hoje só soma saques, disputas e reembolsos. Recovery precisa entrar nessa mesma conta.

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| Migration de `extract_types` | Nova | Adicionar um tipo de extrato para o débito de recuperação de venda, por exemplo `sale_recovery`. |
| `app/Domain/Extract/Enum/ExtractOperation.php` | Alterar | Adicionar a operação de débito aprovado de recovery. |
| `app/Application/UseCase/Extract/CreateExtractOperationUseCase.php` | Alterar | Construir o lançamento negativo do novo tipo, idempotente por dispatch. |
| `sale_recovery_balance_holds` (migration/model/repository) | Novo | Persistir reserva por dispatch: responsável, valor, status `blocked|approved|refused`, datas e referência. Não usar somente `extract`, pois o extrato não representa o bloqueio temporário. |
| Caso de uso de reserva de recovery | Novo | Bloquear saldo com lock do usuário e validar disponibilidade já descontando todos os bloqueios existentes. |
| Caso de uso de liquidação de recovery | Novo | Em sucesso, criar débito no extrato e encerrar a reserva; em falha, apenas liberar a reserva. |
| `app/Domain/Extract/Repository/ExtractAvailabilityRepository.php` | Alterar | Somar reservas `blocked` de recovery e retornar `recovery` em `block_details`. |
| `app/Application/UseCase/Extract/GetExtractAvailabilityUseCase.php` | Alterar | Incluir recovery em `blocked` e `available`. |

## `dashboard-seller` — saldo e extrato

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| `app/services/BalanceService.php` | Alterar | Somar recovery bloqueado ao cálculo local de `available`, `blocked` e `blockDetails`. |
| `balance.php` e componentes da tela de saldo | Alterar | Exibir “Recuperações pendentes” como composição do saldo bloqueado. |
| `views/dashboard/admin/seller_overview/_components/balance.php` | Alterar | Exibir recovery bloqueado no overview administrativo. |
| `api/admin/sellers_balance/details.php` | Alterar | Incluir recovery no detalhamento administrativo de bloqueios. |
| Componente inline de saldo informado pelo time | Alterar | Refletir a nova parcela `recovery` no total bloqueado/disponível. O caminho exato deve ser confirmado antes da implementação. |
| Extrato/listagem de movimentações | Alterar | Exibir o novo tipo de débito de recuperação com referência à venda/dispatch. |

## Checkout Transparente — item de fatura

O serviço de billing já tem o consumidor interno `billing.items.create` e a tabela `billing_items`, mas não há rota HTTP para inserir um item externo. A feature precisa expor uma integração interna idempotente para isso.

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| `services-checkout-transparent-billing/app/Domain/Billing/Enum/BillingItemType.php` | Alterar | Adicionar o tipo `sale_recovery`. |
| Request/UseCase/Controller de billing item | Novos | Criar endpoint interno autenticado para inserir item de fatura de recovery. Sugestão: `POST /billing/items`. |
| `services-checkout-transparent-billing/config/routes.php` | Alterar | Registrar a rota interna. |
| `BillingItemsQueueProcess` ou serviço comum de criação | Alterar | Reutilizar a mesma validação e idempotência por `source_type + source_id + type`. |
| `services-commerce-v2` cliente de Billing | Novo | Ao receber sucesso do envio de dispatch transparente, criar item `sale_recovery` com `source_type = sale_recovery_dispatch` e `source_id = dispatch_id`. |

O item não é criado antes do resultado do envio. Não há reserva de saldo neste caminho: ele compõe a fatura do Checkout Transparente.

## Critérios de aceite

- [ ] Dez dispatches Lowify iniciados bloqueiam dez taxas e reduzem o saldo disponível sem alterar o saldo total.
- [ ] Cada sucesso Lowify gera exatamente um débito de extrato do novo tipo e libera a reserva correspondente.
- [ ] Cada falha Lowify libera exatamente uma reserva sem gerar débito.
- [ ] Cada sucesso de Checkout Transparente cria exatamente um item de fatura `sale_recovery`.
