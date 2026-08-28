# Fase 3 — Wallet: créditos de comunicação

## Dados e SQL manual

Criar no banco da Wallet:

| Tabela | Campos mínimos | Índices/restrições |
| --- | --- | --- |
| `communication_credit_packages` | `name`, `amount`, `bonus`, `is_active`, timestamps | `amount > 0`, `bonus >= 0`; compra referencia o pacote por FK e crédito recebido é `amount + bonus` |
| `communication_credit_balances` | `owner_user_id`, `balance`, `blocked_amount`, timestamps | PK em `owner_user_id`; disponível = `balance - blocked_amount` |
| `communication_credit_purchases` | owner, pacote, snapshots, método, referência, status, chave idempotente, `created_at` e `paid_at` | uma compra `pending` por owner/pacote; não possui `credited_at` nem `updated_at` |
| `communication_credit_entries` | `owner_user_id`, `operation`, `amount`, `source_type`, `source_id`, `expires_at`, `created_at` | único `(source_type, source_id, operation)`; índice por owner/data e por expiração de hold |
| `communication_credit_alerts` | `owner_user_id`, `alert_type`, `cooldown_until`, timestamps | único `(owner_user_id, alert_type)` |

`operation` é `topup|hold|release|consume`. `communication_credit_entries` é a razão/auditoria imutável. `communication_credit_balances` é a projeção de leitura e lock: cada operação atualiza razão e saldo na mesma transação, bloqueando a linha de `owner_user_id`. O disponível é `balance - blocked_amount`; consumo tardio pode deixar `balance` negativo.

## Modelos, repositórios e casos de uso

| Camada | Pendência |
| --- | --- |
| Models | `CommunicationCreditPackage`, `CommunicationCreditBalance`, `CommunicationCreditEntry`, `CommunicationCreditAlert`. |
| Repositories | Buscar/criar saldo com lock, consultar razão, criar entry idempotente e controlar cooldown. |
| Use cases | `HoldCommunicationCreditUseCase`, `ReleaseCommunicationCreditUseCase`, `ConsumeCommunicationCreditUseCase`, `CreditCommunicationTopupUseCase`, `GetCommunicationCreditBalanceUseCase`. |
| Compras | `CreateCommunicationCreditPurchaseUseCase` retorna a pendente do mesmo pacote; `PayWithWalletBalanceUseCase` debita saldo normal e credita comunicação na mesma transação. |
| Concorrência | Bloquear usuário em transação, como `CreateExtractOperationUseCase`; hold só ocorre com disponível suficiente. |
| Expiração | Hold grava `expires_at`; processo da Wallet localiza holds vencidos e cria `release` idempotente. |
| Confirmação tardia | Se o hold expirou, `consume` é permitido e pode resultar em saldo negativo. |
| Alertas | `NotifyInsufficientCommunicationCreditUseCase` cria/renova cooldown e publica pedido ao Notification. |

## API interna

Adicionar controller, requests e rotas autenticadas no padrão de `ExtractController`:

| Rota sugerida | Uso |
| --- | --- |
| `GET /communication-credits/users/{user_id}/balance` | saldo total, bloqueado, disponível e negativo. |
| `POST /communication-credits/holds` | criar hold por referência. |
| `POST /communication-credits/holds/{source_type}/{source_id}/release` | liberar hold. |
| `POST /communication-credits/consumptions` | consumir hold ou débito tardio. |
| `POST /communication-credits/topups` | crédito idempotente vindo do Banking V2. |
| `POST /communication-credit-purchases` | criar/retornar compra pendente de pacote por PIX ou saldo normal. |
| `GET /communication-credits/entries` | extrato paginado/filtrado. |
| `GET /communication-credit-packages` | listar pacotes ativos. |

Todas usam `ValidateLedgerServiceAuthorizationMiddleware` e assinatura interna. A API pública não chama Wallet diretamente: passa por Public API/Gateway quando o chamador é Dashboard.

## Integrações consumidoras

- Commerce chama hold antes de WhatsApp/RDC cobrável, release em falha e consume em confirmação.
- Banking V2 chama topup após PIX pago.
- Wallet solicita alerta quando faltam créditos; Notification envia os canais.
- Dashboard consulta saldo, extrato e pacotes via edges.

## Critérios de aceite

- [ ] Dois holds concorrentes não usam o mesmo saldo.
- [ ] Reentrega de hold/release/consume/topup não gera uma segunda entry.
- [ ] O consume tardio funciona sem hold e permite saldo negativo.
- [ ] Cooldown de insuficiência é no máximo um alerta por owner em 12 horas.
