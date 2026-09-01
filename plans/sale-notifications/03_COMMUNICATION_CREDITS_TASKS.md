# Fase 3 — Wallet: créditos de comunicação

## Objetivo e fronteiras

O `services-wallet` é a fonte de verdade dos créditos monetários usados por comunicações pagas: entrega por WhatsApp e recuperação de venda (RDC). Ele não decide se a comunicação deve ser enviada, nem seleciona canal, template ou provedor; essas decisões pertencem ao Commerce e ao Notification.

- O saldo é único por `owner_user_id`, compartilhado entre entrega e RDC.
- Créditos podem ficar negativos somente em uma confirmação tardia de envio, depois de um bloqueio já ter expirado.
- Antes de enviar uma comunicação paga, o Commerce solicita um bloqueio. Sem crédito disponível, não há envio do canal pago.
- Toda alteração de saldo deve ter lançamento imutável e idempotente.

## Ordem de implementação

### 3.1 — Preparar schema e operação de extrato

Responsável: `services-wallet` (SQL manual, incluído no deploy consolidado).

- [ ] Criar `communication_credit_packages` com `name`, `amount`, `bonus`, `is_active`, `created_at` e `updated_at`.
  - `amount` é o valor monetário do pacote; `bonus` é o crédito adicional concedido.
  - Validar `amount > 0` e `bonus >= 0`.
- [ ] Criar `communication_credit_balances`, com uma linha por `owner_user_id`, `balance`, `blocked_amount`, `created_at` e `updated_at`.
  - O saldo disponível é calculado como `balance - blocked_amount`; não criar coluna duplicada.
- [ ] Criar `communication_credit_purchases`.
  - Campos: `uuid`, `owner_user_id`, `communication_credit_package_id`, snapshots `amount` e `bonus`, `payment_method`, `payment_reference_id`, `status`, `idempotency_key`, `payment_data`, `error_code`, `pending_package_id`, `created_at`, `paid_at`.
  - `payment_method`: `pix` ou `wallet_balance`.
  - `payment_reference_id` referencia a cobrança PIX no Banking ou o lançamento normal de extrato no Wallet, conforme o método.
  - `pending_package_id` é coluna gerada: contém o ID do pacote em `creating` ou `pending`, para permitir no máximo uma recarga válida por usuário/pacote.
  - Criar FK para o pacote e índices para consulta por proprietário, status e referência de pagamento.
- [ ] Criar `communication_credit_entries` como razão imutável.
  - Campos: `owner_user_id`, `operation`, `amount`, `source_type`, `source_id`, `expires_at`, `created_at`.
  - Operações: `topup`, `hold`, `release`, `consume`.
  - Unicidade por `source_type`, `source_id` e `operation` para tornar callbacks e jobs idempotentes.
- [ ] Criar `communication_credit_alerts` para controlar o aviso de crédito insuficiente por usuário, com `alert_type`, `cooldown_until`, timestamps e unicidade de alerta por proprietário/tipo.
- [ ] Criar, no catálogo manual de `extract_types`, o tipo de débito “compra de créditos de comunicação”.
  - O tipo `35` fica reservado para esta feature; o deploy deve parar se ele já estiver ocupado por outra descrição.
  - Esse lançamento é necessário quando o pacote é comprado com saldo normal da Wallet.
- [ ] Registrar no arquivo SQL a ordem de aplicação e queries de pré-validação para tabelas e `extract_types` existentes.

### 3.2 — Modelos, enums e repositórios

Responsável: `services-wallet`.

- [x] Criar modelos e casts para `CommunicationCreditPackage`, `CommunicationCreditBalance`, `CommunicationCreditPurchase`, `CommunicationCreditEntry` e `CommunicationCreditAlert`.
- [x] Criar enums para status de compra, método de pagamento, operação do razão e tipo de alerta.
- [x] Adicionar a operação correspondente ao enum e às regras de validação do extrato normal.
- [x] Criar repositório de pacotes: listar ativos e obter pacote ativo por ID.
- [x] Criar repositório de saldo com `findOrCreate` e leitura com bloqueio pessimista por `owner_user_id`.
- [x] Criar repositório de compras: criar de forma idempotente, localizar pendência por usuário/pacote, bloquear compra durante confirmação e localizar por referência de pagamento.
- [x] Criar repositório de lançamentos: criar idempotentemente, consultar bloqueio aberto por origem e selecionar bloqueios vencidos em lotes seguros.
- [x] Criar repositório de alertas com aquisição atômica de cooldown, evitando que eventos concorrentes disparem mais de um aviso em 12 horas.

### 3.3 — Consulta de pacotes e saldo

Responsável: `services-wallet`.

- [x] Implementar caso de uso para listar pacotes ativos, expondo somente `id`, `name`, `amount`, `bonus` e crédito total calculado.
- [x] Implementar caso de uso para consultar o saldo de comunicação do usuário: total, bloqueado e disponível.
- [x] Garantir que a criação inicial do saldo seja transparente e não gere lançamento.
- [x] Expor endpoints internos autenticados e assinados para essas duas consultas, para consumo futuro pelo `edge-public-api`.

### 3.4 — Criar compra de pacote

Responsável: `services-wallet`; integração externa com Banking fica na Fase 4.

- [ ] Implementar `CreateCommunicationCreditPurchaseUseCase` recebendo proprietário, pacote, método de pagamento e chave de idempotência.
  - A Wallet gera o `uuid` público da recarga e devolve-o imediatamente ao front via `edge-public-api`.
  - Para PIX, criar a compra em `creating` e publicar a solicitação na fila do Banking; não chamar o Banking de forma síncrona.
  - A compra e um evento `communication_credit_purchase.create` devem ser gravados na mesma transação em uma outbox local da Wallet.
  - Um processo da Wallet publica eventos pendentes na fila consumida pelo Banking e tenta novamente após falha.
- [ ] Copiar `amount` e `bonus` do pacote para os snapshots da compra; alterações posteriores no pacote não podem alterar uma compra iniciada.
- [ ] Se já houver compra válida (`creating` ou `pending`) do mesmo pacote para o usuário, retornar essa compra em vez de criar outra cobrança.
  - Uma recarga é reutilizável por uma hora na Wallet (`expires_at`); após isso, uma nova solicitação gera nova compra e nova charge.
  - A charge PIX criada pelo Banking expira em duas horas e pode ser paga após a expiração local; o pagamento tardio da compra original ainda deve creditar o usuário.
- [ ] Validar pacote ativo, método aceito e chave de idempotência.
- [ ] Criar consulta por UUID para polling: enquanto `creating`, o front aguarda; em `pending`, receberá os dados PIX; em `failed`, receberá `error_code`; nos demais estados, o resultado final.
- [ ] O Banking consome a fila de criação PIX e chama a Wallet para gravar `payment_reference_id` + `payment_data`, mudando a compra para `pending`, ou `error_code`, mudando-a para `failed`.
- [ ] Não creditar saldo nessa etapa para compra PIX pendente.
- [x] Criar processo de expiração de recargas que marca `creating` e `pending` com `expires_at <= agora` como `expired`.
  - A criação também deve aplicar essa expiração sob lock antes de decidir reutilizar uma compra, sem depender exclusivamente do processo periódico.

### 3.5 — Comprar com saldo normal da Wallet

Responsável: `services-wallet`.

- [ ] Implementar confirmação local da compra com `payment_method = wallet_balance` numa única transação de banco.
- [ ] Bloquear a conta/saldo de extrato normal e validar disponibilidade antes do débito.
- [ ] Criar o lançamento de débito usando o novo `extract_type` de compra de créditos.
- [ ] Marcar a compra como `paid`, preencher `paid_at` e usar o ID desse lançamento como `payment_reference_id`.
- [ ] Criar lançamento `topup` no razão de comunicação por `amount + bonus` e incrementar `communication_credit_balances.balance` na mesma transação.
- [ ] Garantir idempotência: repetição da mesma requisição não pode debitar o extrato ou creditar duas vezes.
- [ ] Definir resposta para saldo normal insuficiente sem criar débito parcial.

### 3.6 — Confirmar compra PIX e creditar

Responsável: `services-wallet`; o contrato de callback do Banking é detalhado na Fase 4.

- [ ] Implementar `ConfirmCommunicationCreditPixPurchaseUseCase` por ID da compra/referência PIX.
- [ ] Bloquear a compra, validar que ela ainda está pendente e tratar callback repetido como sucesso idempotente.
- [ ] Validar que a cobrança informada corresponde à compra e ao valor esperado antes de creditar.
- [ ] Na mesma transação local: preencher `payment_reference_id`, mudar para `paid`, preencher `paid_at`, criar lançamento `topup` e atualizar o saldo.
- [ ] Tratar falha, expiração e cancelamento sem crédito; nunca permitir que um callback de pagamento crie crédito para compra terminal incompatível.

### 3.7 — Bloquear, liberar e consumir créditos

Responsável: `services-wallet`; Commerce chamará esses contratos nas fases de entrega e RDC.

- [ ] Implementar `HoldCommunicationCreditUseCase` recebendo `owner_user_id`, origem (`sale_delivery` ou `sale_recovery_dispatch`), ID da origem, valor e expiração.
- [ ] Bloquear o saldo de comunicação, recalcular disponibilidade sob lock e recusar se o disponível for menor que o valor.
- [ ] Registrar `hold`, incrementar `blocked_amount` e gravar `expires_at`; repetição para a mesma origem deve retornar o bloqueio existente.
- [ ] Implementar `ReleaseCommunicationCreditUseCase`.
  - Encontrar bloqueio ainda aberto, registrar `release` e reduzir `blocked_amount` na mesma transação.
  - Repetições não devem alterar saldo novamente.
- [ ] Implementar `ConsumeCommunicationCreditUseCase`.
  - Com bloqueio ativo: registrar `consume`, reduzir `blocked_amount` e reduzir `balance` na mesma transação.
  - Sem bloqueio ativo por confirmação tardia: registrar consumo tardio e reduzir `balance`, podendo ficar negativo.
  - A origem deve impedir consumo duplicado.
- [ ] Definir valores como dinheiro decimal, sem float, e validar valor positivo em todos os comandos.

### 3.8 — Expiração de bloqueios e alerta de crédito insuficiente

Responsável: `services-wallet`.

- [ ] Criar processo periódico para localizar bloqueios vencidos e liberar cada um via o mesmo caso de uso idempotente.
- [ ] Configurar lote, frequência, lock/concorrência e observabilidade no padrão de processos atual do serviço.
- [ ] Ao recusar bloqueio por falta de crédito, gravar/atualizar o controle de alerta e publicar pedido de aviso ao Notification.
- [ ] Limitar o aviso a um por `owner_user_id` a cada 12 horas, por e-mail e WhatsApp.
- [ ] Falha ao publicar alerta não pode converter a tentativa em enviada nem afetar o saldo; deve ser observável e reprocessável.

### 3.9 — APIs internas e contratos

Responsável: `services-wallet`.

- [ ] Criar controller, requests, respostas e rotas para créditos de comunicação, seguindo autenticação de serviço e assinatura já usadas pelo Wallet.
- [ ] Expor contratos internos para: listar pacotes, consultar saldo, iniciar compra, comprar com saldo normal, confirmar PIX, bloquear, liberar e consumir.
- [ ] Padronizar erros de domínio: pacote inativo/inexistente, compra pendente existente, saldo normal insuficiente, crédito insuficiente, referência inválida e conflito de estado.
- [ ] Documentar payloads e códigos de retorno para Commerce, Banking, `edge-public-api` e Dashboard implementarem sem depender da estrutura interna das tabelas.
- [ ] Expor operações administrativas de pacote exclusivamente para administradores com permissão `1` ou `2`: listar todos, criar, editar e ativar/desativar.

### 3.10 — Testes e critérios de aceite

Responsável: `services-wallet`.

- [ ] Cobrir pacotes ativos/inativos e snapshots imutáveis de `amount` e `bonus`.
- [ ] Cobrir uma única pendência por pacote/usuário, idempotência de criação e nova compra após estado terminal.
- [ ] Cobrir compra PIX, callback duplicado, valor/referência incorretos e transições terminais.
- [ ] Cobrir compra por saldo normal, saldo insuficiente, débito único de extrato e crédito único no razão.
- [ ] Cobrir concorrência de dois bloqueios disputando o último crédito disponível.
- [ ] Cobrir liberar, consumir, expirar, confirmação tardia e saldo negativo exclusivamente no caso tardio.
- [ ] Cobrir idempotência por origem/operação e consistência entre `balance`, `blocked_amount` e razão.
- [ ] Cobrir cooldown de alerta e falha de publicação do aviso.
- [ ] Executar suite do `services-wallet`, análise estática e formatter definidos pelo repositório.

## Dependências e pendências externas

- Fase 4 define o contrato final Banking V2 ↔ Wallet para PIX e o identificador da referência de pagamento.
- A operação de extrato depende da convenção/ID disponível na tabela manual `extract_types` do ambiente de deploy.
- A administração de pacotes é exclusiva para administradores com permissão `1` ou `2`; as rotas administrativas serão adicionadas numa task própria.
- A política de expiração de créditos comprados e a política de estorno PIX seguem pendentes; nenhum vencimento de crédito deve ser implementado antes dessa definição.
