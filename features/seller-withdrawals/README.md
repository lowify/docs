# Feature — saques de sellers

> Status: ativo, temporariamente indisponível para novas solicitações
> Última atualização: 2026-11-18
> Confiança: confirmada no código

## Objetivo

Permite que sellers solicitem saque do saldo disponível para uma conta cadastrada. A suspensão temporária interrompe apenas a criação de novas solicitações; não altera solicitações já registradas nem os fluxos administrativos.

## Fluxo principal

```text
Seller -> dashboard-seller (telas de saldo/saques) -> action ou API -> withdrawalRequest -> MySQL e Redis -> solicitação pendente
```

## Componentes e responsabilidades

| Componente | Responsabilidade | Entrada/saída relevante |
| --- | --- | --- |
| `dashboard-seller/balance.php` | Exibe saldo e abertura de saque | Desabilita a abertura do modal durante suspensão |
| `dashboard-seller/contas.php` e `withdrawals.php` | Exibem contas/solicitações | Desabilitam o botão de novo saque durante suspensão |
| `includes/operations/withdrawal_limits.php` | Centraliza suspensão, limites e aviso | `withdrawalRequestsAreTemporarilyDisabled()` |
| `includes/operations/withdrawal.php` | Cria a solicitação de saque | Recusa a criação durante suspensão |
| `actions/withdrawal/create.php` e `api/request-withdrawal.php` | Entradas de solicitação | A action usa o fluxo central; a API retorna erro durante suspensão |

## Contratos e autorização

O endpoint interno `actions/withdrawal/create.php` exige sessão autenticada, impede colaboradores e valida a elegibilidade do perfil. A API legada `api/request-withdrawal.php` autentica por token. Ambas recusam novos saques enquanto a chave de suspensão central estiver ativa.

## Dados e processamento assíncrono

Solicitações aprovadas para criação são persistidas em `tbl_saques`. Quando o limite diário estiver ativo, a reserva do limite usa Redis. A suspensão temporária acontece antes dessas operações, sem escrever registros ou reservar valor.

## Operação e validação

A suspensão é controlada em `withdrawalRequestsAreTemporarilyDisabled()` e deve ser revertida para `false` ao normalizar a operação. A interface mostra a indisponibilidade e o servidor aplica a mesma regra, evitando que uma chamada direta contorne o bloqueio.

## Limitações e pendências

Não foi localizado um teste automatizado do fluxo. A validação atual cobre lint PHP e inspeção dos caminhos de UI e servidor. A rota `saque_process.php` atualmente redireciona antes de processar a solicitação, portanto não é uma via ativa de criação.

## Referências

- `dashboard-seller/includes/operations/withdrawal_limits.php`
- `dashboard-seller/includes/operations/withdrawal.php`
- `dashboard-seller/actions/withdrawal/create.php`
- `dashboard-seller/api/request-withdrawal.php`
- `docs/deploys/2026-09-09-seller-withdrawal-limits-config/2026-09-09_SELLER_WITHDRAWAL_LIMITS_CONFIG_DEPLOY.md`
