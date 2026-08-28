# Fase 4 — Banking V2: recarga de créditos por PIX

## Reuso confirmado

O Banking V2 já expõe `POST /pix` em `config/routes.php`; `ChargePixController` resolve `purpose` antes de encaminhar ao handler do gateway. A recarga deve ampliar esse contrato, sem criar fluxo paralelo.

## Dados e idempotência

- A cobrança PIX usa `purpose = communication_credit_topup`.
- O pacote define `amount` (valor PIX) e `bonus`; o crédito total é `amount + bonus`.
- A compra na Wallet congela `amount_snapshot` e `bonus_snapshot`; o payload PIX carrega o ID da compra, e não depende do pacote atual.
- `payment_method` já identifica PIX ou saldo normal, portanto a compra usa somente `payment_reference_id`, sem `payment_reference_type`.
- A confirmação usa a chave idempotente da cobrança PIX, não o ID do pacote.
- Banking não mantém saldo: após pagamento chama/publica a confirmação da compra PIX na Wallet, que marca `paid_at` e credita na mesma transação local.

## Pendências por camada

| Camada | Pendência |
| --- | --- |
| `config/routes.php` | Reusar ou adicionar rota autenticada para criação de recarga. |
| Request/Controller | Validar pacote ativo, owner da identidade autenticada e gateway PIX permitido. |
| `ChargePurposeResolver` | Aceitar `communication_credit_topup` sem quebrar purposes CT. |
| Use cases/handlers PIX | Persistir purpose e metadados do pacote para todos os gateways habilitados. |
| Webhook/consumer | Detectar recarga paga e invocar/publicar Wallet; reentrega não credita duas vezes. |
| Cliente Wallet | Usar autenticação de serviço, timeout e erro do padrão interno. |
| Testes | Cobrança criada, pagamento repetido, pacote inativo, owner adulterado e Wallet indisponível. |

## UI e edges

- Dashboard lista pacotes e gera cobrança PIX.
- Gateway/Public API extraem JWT; nunca aceitam `owner_user_id` arbitrário do browser.
- A tela acompanha PIX pendente/pago pelos dados de Banking V2.

## Pendências de produto

- Quem administra pacotes.
- Expiração e estorno de recarga.
