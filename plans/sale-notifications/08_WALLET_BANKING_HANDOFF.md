# Handoff — créditos de comunicação: Wallet e Banking V2

## Estado e origem do código

O desenvolvimento inicial está em branches locais `feat/sale-notifications-credits`:

- `services-wallet`: commit `28114b3` (`feat: add communication credit wallet flows`).
- `services-notification`: commit `39fb6be` (`feat: add insufficient communication credit email template`).

Nada deste código ou do SQL foi aplicado na VPS de homologação. Em 2026-08-29, a VPS tinha Wallet na branch `feat-cielo-integration`, com alteração local em `.dockerignore`, e Notifications na `main`.

O próximo responsável deve revisar os commits antes de integrar: não houve suite automatizada executável no checkout local (`vendor/` ausente; `composer install` foi bloqueado por ausência de `ext-redis`). Lint PHP e `git diff --check` foram executados nos arquivos alterados.

## O que foi implementado na Wallet

### Dados e domínio

- Modelos, enums, repositórios e valor monetário para pacote, saldo, compra, razão, alerta e outbox de créditos.
- Pacotes: `amount` é o valor pago e `bonus` é o crédito adicional; o crédito concedido é `amount + bonus`.
- Saldo de comunicação separado por `owner_user_id`, com `balance`, `blocked_amount` e disponível calculado.
- Razão imutável com `topup`, `hold`, `release` e `consume`.
- Novo tipo de extrato `35` para compra de crédito com saldo normal.

### Recargas

- Consulta de pacotes ativos e saldo.
- Recarga PIX cria compra `creating`, gera UUID público e persiste evento na outbox.
- Processo de outbox assina e publica em `banking:communication-credit-purchases:create`.
- Polling por UUID expõe estado, dados PIX, erro e datas.
- Atualização PIX criada/falha e confirmação PIX creditam a Wallet de comunicação de forma idempotente.
- Expiração local de recarga após uma hora; pagamento PIX tardio continua sendo aceito.
- Compra com saldo normal usa o fluxo existente de extrato e grava `payment_reference_id` com o lançamento resultante.

### Cobrança de entrega/RDC

- Rotas e casos de uso para `hold`, `release` e `consume`.
- Hold reduz disponível; release desfaz bloqueio; consume reduz saldo.
- Consume posterior a release reduz saldo e pode deixá-lo negativo, conforme regra confirmada.
- Processo periódico libera holds vencidos.
- Alerta de crédito insuficiente possui cooldown de 12 horas. O Commerce deve enviar `owner_email` no hold; a Wallet publica no stream de e-mail após o commit.

### Rotas internas da Wallet

Todas estão dentro do grupo já protegido por autorização e assinatura de serviço:

| Rota | Finalidade |
| --- | --- |
| `GET /communication-credits/packages` | Pacotes ativos |
| `GET /communication-credits/owners/{owner_user_id}/balance` | Saldo de comunicação |
| `POST /communication-credits/purchases` | Inicia/reutiliza recarga PIX |
| `GET /communication-credits/purchases/{uuid}` | Polling da recarga |
| `PATCH /communication-credits/purchases/{uuid}/pix` | Banking informa PIX criado/falha |
| `POST /communication-credits/purchases/{uuid}/pix/confirm` | Banking informa PIX pago |
| `POST /communication-credits/purchases/wallet-balance` | Compra com saldo disponível do extrato |
| `POST /communication-credits/holds` | Reserva crédito para dispatch |
| `POST /communication-credits/releases` | Libera reserva |
| `POST /communication-credits/consumes` | Consome reserva/crédito tardio |
| `/communication-credits/admin/packages` | CRUD interno de pacote |

O `edge-public-api` deve aplicar JWT, ownership e a permissão administrativa 1/2 antes de encaminhar chamadas administrativas à Wallet.

## Pendências e revisão obrigatória da Wallet

- [ ] Aplicar o bloco `services-wallet` de `deploy/001_sale_notifications.sql` em ambiente controlado; validar que o ID 35 em `extract_types` está livre.
- [ ] Criar testes de integração/transação para compra PIX, callback repetido, pagamento tardio, compra com saldo disponível, hold/release/consume e expiração.
- [ ] Subir o ambiente Docker local para rodar `composer test`, `composer analyse` e formatter; o host atual não possui `ext-redis`.
- [ ] Revisar concorrência dos processos de outbox e expiração. Eles devem reclamar eventos/linhas sob lock antes de processar, evitando duas instâncias publicarem/liberarem a mesma origem em paralelo.
- [ ] Revisar a política de retry da outbox e de publicação do e-mail. O alerta de e-mail não possui outbox própria; uma falha de Redis é registrada pelo `NotificationService`, mas não é reprocessada automaticamente.
- [ ] Padronizar controllers e requests: alguns foram escritos de forma compacta e precisam de revisão de estilo, respostas de domínio e validação por operação.
- [ ] Validar explicitamente que uma compra por saldo normal não pode gerar duas entradas em concorrência; o extrato permanece fonte de verdade do saldo disponível.
- [ ] Não expor diretamente essas rotas ao front. Dashboard deve chamar `edge-gateway`/`edge-public-api`.

## Notifications já iniciado

Há migration `2026_08_28_000056_seed_communication_credit_insufficient_email_template.php` e Twig `wallet/communication_credit_insufficient.twig` no commit `39fb6be`.

Ela cria o `correlation_type` `communication_credit_insufficient`, consumido pelo stream já existente `stream:notifications:email_single`.

## Trabalho necessário no Banking V2

### Consumir criação de PIX

Consumir a fila Redis:

```text
banking:communication-credit-purchases:create
```

Mensagem publicada pela Wallet:

```json
{
  "id": "uuid-do-evento",
  "event": "communication_credit_purchase.create",
  "timestamp": 0,
  "metadata": {
    "purchase_uuid": "uuid-da-recarga",
    "owner_user_id": 123,
    "package_id": 1,
    "amount": "10.00",
    "pix_expires_at": "YYYY-MM-DD HH:MM:SS"
  },
  "signature": "hmac-sha256"
}
```

O Banking deve validar a assinatura com o segredo de serviços e ser idempotente por `purchase_uuid`/`id`.

Criar cobrança PIX com validade de **duas horas**, usando purpose `communication_credit_topup`. A validade local da Wallet é uma hora e não deve cancelar esta charge.

### Retornar resultado à Wallet

Após criar PIX:

```http
PATCH /communication-credits/purchases/{purchase_uuid}/pix
```

Sucesso:

```json
{ "payment_reference_id": 123, "payment_data": { "...dados do PIX...": "..." } }
```

Falha:

```json
{ "error_code": "pix_creation_failed" }
```

Após confirmação de pagamento:

```http
POST /communication-credits/purchases/{purchase_uuid}/pix/confirm
```

```json
{ "payment_reference_id": 123, "payment_data": { "...": "..." } }
```

Essas chamadas devem usar a assinatura de serviço já exigida pela Wallet e ser repetíveis. Pagamento de uma charge cuja recarga local esteja `expired` deve ser confirmado e creditado normalmente: a cobrança PIX continua válida por duas horas.

### Regras que Banking não deve decidir

- Não calcula bônus, saldo de créditos ou elegibilidade de comunicação.
- Não decide se uma recarga de uma hora deve gerar nova charge; isso é da Wallet.
- Não cancela PIX na expiração local da Wallet.

