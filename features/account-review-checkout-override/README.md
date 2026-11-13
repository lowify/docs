# Feature — revisão de conta e elegibilidade de checkout

> Status: em evolução
> Última atualização: 2026-11-13
> Confiança: confirmada no código; alteração de override planejada

## Objetivo

Controlar a revisão cadastral de sellers e a disponibilidade de checkout. O status de review é hoje parte da elegibilidade de checkout para contas na fase 3.

## Fluxo confirmado

```text
Conversão de tipo
  -> services-account limpa account_review_status e enfileira refresh
  -> ProfileCompletionRefreshQueueProcess / complete_register
  -> account review e status de seller

Checkout
  -> Commerce V2 consulta seller no Account
  -> fase 3 exige account_review_status=approved
  -> cria venda ou devolve seller indisponível
```

## Estado atual e limitação

`ConvertAccountTypeUseCase` aceita fases 2 e 3, mas grava `account_review_status = NULL` ao converter PF↔PJ. A recuperação automática de `NULL` para `pending` está limitada à fase 2; uma conta fase 3 pode permanecer sem revisão pendente e sem ser elegível para checkout.

O plano [override de checkout durante revisão após conversão de conta](../../plans/account-review-checkout-override/README.md) propõe manter a review real em `pending` e introduzir uma autorização exclusiva de checkout para sellers que eram aprovados antes da conversão.

## Componentes

| Componente | Responsabilidade atual |
| --- | --- |
| `services-account` | Conversão PF/PJ, estado de review, documentos/KYC e filas de refresh. |
| `services-commerce-v2` | Elegibilidade do seller para checkout padrão e transparente. |
| `dashboard-seller` | Operações administrativas de review e conversão. |

## Dados e filas

- `tbl_usuarios.account_phase`: fase 1 (PF), 2 (migrada) ou 3 (full).
- `tbl_usuarios.account_review_status`: `pending`, `in_review`, `approved`, `rejected`, `resubmission_requested` ou `NULL` no estado legado/problemático descrito acima.
- `user_reviews`: histórico e review ativa da conta.
- `accounts:complete:refresh`: fila que recalcula completion e pode assegurar uma review.
- `account:user:events`: fila de eventos `complete_register`.

## Limitações e pendências

- Hoje não há estado separado de “checkout autorizado por exceção” e “review cadastral pendente”.
- A decisão para `resubmission_requested` após uma conversão com override ainda depende de regra de produto.
- O override planejado não deve liberar saque, conta bancária ou integração de cartão.

## Referências

- `services-account/app/Application/UseCase/AccountMigration/ConvertAccountTypeUseCase.php`
- `services-account/app/Process/ProfileCompletionRefreshQueueProcess.php`
- `services-commerce-v2/app/Domain/Seller/Services/SellerEligibilityService.php`
- [Plano da alteração](../../plans/account-review-checkout-override/README.md)
