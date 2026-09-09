# Fase 11 — Dashboard Seller: preferências e créditos de comunicação

## Objetivo

Entregar ao seller o controle de usar ou não seu saldo disponível como fallback
quando não houver créditos de comunicação. Esta é uma preferência financeira do
owner; não é configuração comercial e não substitui as regras por produto ou
afiliação.

Os fluxos obrigatórios são:

```text
Dashboard Seller → edge-gateway → edge-public-api → Account
Dashboard Seller → edge-gateway → edge-public-api → Wallet
```

## Regra de negócio

A chave é `sale_notifications_allow_seller_balance`, gravada apenas em
`user_system_vars`.

- Sem registro: valor efetivo `true`.
- Ativa: créditos são prioritários; fora do Checkout Transparente, saldo normal
  pode ser usado se não houver crédito suficiente.
- Desativa: a falta de crédito impede a comunicação paga, mesmo se houver
  saldo normal disponível.
- Checkout Transparente: nunca usa saldo normal, independentemente da chave.

O seller não pode alterar flag de rollout, habilitação geral de WhatsApp ou
preços. Essas operações pertencem ao Dashboard Admin.

## API a implementar

Os endpoints administrativos existentes de Account não podem ser expostos ao
seller, porque aceitam chaves comerciais. Criar um contrato limitado.

### Account

Criar endpoints internos:

| Método | Rota | Responsabilidade |
| --- | --- | --- |
| `GET` | `/users/{user_id}/sale-notifications/preferences` | Ler somente a preferência. |
| `PUT` | `/users/{user_id}/sale-notifications/preferences` | Salvar somente a preferência. |

Criar Request/use case/controller usando o `SaleNotificationSettingsService` e
`SystemVarService` existentes. O payload aceito é exclusivamente:

```json
{ "allow_seller_balance": true }
```

Resposta:

```json
{
  "user_id": 123,
  "allow_seller_balance": {
    "override": false,
    "effective": false
  }
}
```

Rejeitar com `422` qualquer chave além de `allow_seller_balance`. Não criar
novo domínio, tabela ou coluna de usuário.

### Public API e Gateway

| Método | Rota pública |
| --- | --- |
| `GET` | `/user/sale-notifications/preferences` |
| `PUT` | `/user/sale-notifications/preferences` |

Public API exige JWT, resolve o `user_id` exclusivamente pelo `sub` e chama
Account. Não aceitar `user_id` em path ou body. Gateway espelha as duas rotas.

## Interface — configurações do seller

Na tela **Perfil → Contas → Preferências**, adicionar uma seção
**“Comunicações de venda”**. Não criar uma tela paralela de preferências.

Conteúdo obrigatório:

1. Toggle: **“Usar saldo disponível quando não houver créditos de
   comunicação”**.
2. Texto: “Os créditos de comunicação são usados primeiro. Quando esta opção
   estiver ativa, vendas fora do Checkout Transparente também podem usar seu
   saldo disponível para enviar uma comunicação paga.”
3. Aviso: “O Checkout Transparente utiliza apenas créditos de comunicação.”
4. Carregar estado efetivo com `GET /user/sale-notifications/preferences`.
5. Sem override, mostrar toggle ligado, pois o default efetivo é `true`.
6. Salvar por `PUT`, enviando apenas `allow_seller_balance`.
7. Durante gravação, desabilitar interação; em sucesso consolidar valor
   retornado; em erro restaurar o valor anterior e mostrar feedback.

Não mostrar nesta tela:

- flag global ou override de ativação;
- configuração global de WhatsApp de entrega;
- preço de entrega ou RDC;
- dados/preferências de outro seller;
- pacotes administrativos.

Os preços efetivos permanecem somente leitura na configuração de produto e
afiliação, via `SaleNotificationRules`. Status, timeline e reenvio permanecem
em task operacional separada.

## Créditos de comunicação e modal de recarga

Ainda em **Perfil → Contas → Preferências**, incluir um card de **“Créditos de
comunicação”**. Ele é a entrada do seller para consultar crédito e iniciar uma
recarga; não deve exigir uma página paralela.

### Card de créditos

Carregar `GET /communication-credits/balance` e exibir:

1. Saldo total de créditos.
2. Valor bloqueado em comunicações aguardando confirmação.
3. Saldo disponível, inclusive quando negativo.
4. Botão primário **“Adicionar créditos”**.
5. Texto curto: “Créditos são usados para envios pagos de recuperação de venda
   e WhatsApp de entrega.”

Não exibir extrato financeiro normal, dados de outro seller nem gestão de
pacotes administrativos.

### Modal “Adicionar créditos”

O botão abre modal com pacotes ativos de
`GET /communication-credits/packages`.

Cada pacote mostra nome, valor a pagar (`amount`), crédito base, bônus quando
existir e total recebido (`amount + bonus`). A seleção visual deve indicar
claramente o pacote atual.

Meios de pagamento:

1. **PIX**: `POST /communication-credits/purchases` com `package_id` e uma
   idempotency key nova por intenção de compra.
2. **Saldo disponível**: `POST /communication-credits/purchases/wallet-balance`
   com o mesmo contrato, após confirmação explícita.

Nunca reutilizar a idempotency key depois de estado terminal (`paid`, `failed`,
`expired` ou `canceled`). Se a API indicar compra pendente para aquele pacote,
reapresentar essa compra em vez de criar PIX concorrente.

### PIX e polling

Depois de criar compra PIX:

1. Receber `uuid` e status inicial.
2. Mostrar QR Code/copia e cola retornados em `payment_data`.
3. Fazer polling de `GET /communication-credits/purchases/{uuid}` até estado
   terminal.
4. Em `creating` ou `pending`, manter o mesmo PIX e usar `expires_at` retornado
   pela Wallet para a contagem visual.
5. Em `paid`, atualizar o card de saldo, mostrar sucesso e encerrar polling.
6. Em `expired`, oferecer nova compra com nova idempotency key.
7. Em `failed` ou `canceled`, mostrar erro amigável e permitir nova tentativa.

Na compra por saldo, em sucesso `paid` atualizar card/modal imediatamente. Em
saldo insuficiente ou erro, manter seleção, não criar PIX automaticamente e
mostrar feedback recuperável.

## Produto, status e reenvio do seller

As regras de entrega/RDC por produto e afiliação já possuem formulário. Esta
task deve concluir as superfícies do seller que ainda faltam para operar e
acompanhar as comunicações.

### Listagem de produtos

Integrar `POST /products/sale-notifications/summaries` em `products.php` e no
endpoint que alimenta a listagem. Exibir resumo discreto por produto:

- entrega WhatsApp ativa/inativa;
- RDC ativa/inativa;
- quantidade de etapas ativas.

O resumo é apenas informativo e respeita o owner da listagem; edição continua
em produto e afiliação.

### Página de status

Criar a página de status de comunicações do seller, usando
`GET /sale-notifications`.

Ela deve listar somente registros cujo `owner_user_id` pertence ao seller
autenticado — em venda afiliada, o produtor não vê a comunicação paga pelo
afiliado. Exibir entrega e RDC com filtros por período, produto principal,
canal, status e tipo (`delivery`/`recovery`).

Colunas mínimas: venda, produto principal, tipo/etapa, canal, status,
agendamento/envio/confirmação, valor, fonte de funding e motivo de
skip/falha. Destacar comunicação sem retorno e confirmação tardia.

### Detalhe de venda e reenvio cobrável

Em `sale_detail`, adicionar a timeline de
`GET /sales/{sale_id}/communications` respeitando a mesma regra de owner.
Mostrar tentativas de entrega, dispatches RDC, eventos, cobrança, timeout e
falha de forma compreensível ao suporte/seller.

Seller ou colaborador autorizado pode usar o reenvio simples do pack por
`POST /sales/{sale_id}/delivery/resend`:

- o backend resolve autor e owner;
- é cobrável quando WhatsApp for efetivamente enviado;
- segue a regra atual do produto: sem WhatsApp ativo, reenvia somente e-mail;
- não permite escolher canais manualmente;
- o front explica que poderá haver consumo de crédito ou saldo conforme a
  preferência do owner.

## Implementação por repositório

### `services-account`

1. Caso de uso limitado à chave de preferência.
2. Request que aceite booleano estrito.
3. Controller/rotas internas específicas.
4. Reutilizar a regra de default efetivo `true` já existente.

### `edge-public-api`

1. Client/controller para as duas rotas.
2. Resolver identidade pelo JWT, ignorando qualquer tentativa de alvo externo.
3. Repassar `422` do Account sem esconder erro de validação.
4. Reutilizar os endpoints já publicados de créditos; nunca encaminhar o
   browser diretamente à Wallet.
5. Preservar o owner do JWT ao encaminhar summary, status, timeline e reenvio
   do seller/colaborador; nunca aceitar owner/autor do browser.

### `edge-gateway`

1. Espelhar `GET` e `PUT`.
2. Preservar contrato e resposta do Public API.
3. Espelhar summary de produto, status, timeline e reenvio cobrável.

### Dashboard Seller

1. Localizar `Perfil → Contas → Preferências`.
2. Adicionar a seção usando componentes de toggle e feedback já existentes.
3. Adicionar o card de créditos e o modal de recarga descritos acima.
4. Carregar preferências, saldo e pacotes antes da renderização quando o padrão do front exigir chamadas de
   Gateway antes de output.
5. Garantir acessibilidade: label ligado ao toggle, texto explicativo e estado
   disabled durante save.
6. Integrar summary/badge na listagem de produtos.
7. Criar página de status e timeline em `sale_detail`.
8. Adicionar ação de reenvio simples no detalhe, com confirmação de possível
   cobrança e feedback do resultado.

## Fluxos de aceite

1. Seller sem registro lê `effective = true`.
2. Seller desativa e lê `override = false`, `effective = false`.
3. Seller reativa e lê `override = true`, `effective = true`.
4. Payload com preço ou feature flag retorna `422`.
5. Um seller não consegue consultar ou editar a preferência de outro user.
6. Sem JWT, as rotas públicas retornam `401`.
7. Seller escolhe pacote, gera PIX, recebe `uuid` e vê `payment_data` no modal.
8. Polling mantém compra pendente e atualiza saldo apenas após `paid`.
9. Compra por saldo insuficiente não gera PIX nem altera créditos.
10. Seller vê somente comunicações cujo owner é ele; produtor não vê tentativa
    atribuída ao afiliado.
11. Reenvio seller/colaborador respeita a regra do produto e registra cobrança
    quando WhatsApp for efetivamente enviado.

## Testes obrigatórios

- Unitários Account: default, desativar, reativar e payload inválido.
- Public API: identidade pelo `sub`, sem possibilidade de user alvo e `401`
  sem JWT.
- Gateway: forwarding e preservação de erros.
- Front: loading, save bem-sucedido, rollback visual em erro e default ligado.
- Front: listagem de pacotes, compra idempotente, polling PIX, expiração, erro
  e atualização de saldo após pagamento.
- Front/API: resumo na listagem de produtos, isolamento de owner na página de
  status/timeline e reenvio cobrável do seller/colaborador.
- Homologação: usar seller sintético, alternar a preferência e restaurar o
  estado original; gerar PIX sintético sem pagamento e deixá-lo expirar ou
  cancelar segundo o fluxo de homologação.

## Fora de escopo

- Flags/preços/overrides comerciais.
- Gestão de pacotes.
- Regras de produto/afiliação.

## Critérios de aceite

- [ ] Preferência e créditos aparecem em `Perfil → Contas → Preferências`.
- [ ] Seller altera apenas sua própria preferência.
- [ ] Default sem registro é `true`.
- [ ] Checkout Transparente continua fora do fallback por saldo.
- [ ] Não há chamada direta do browser para Account.
- [ ] Há testes de escopo, autenticação e validação.
- [ ] Modal lista somente pacotes ativos e respeita compra pendente/idempotência.
- [ ] PIX pendente é acompanhado até status terminal sem duplicar cobrança.
- [ ] Listagem de produto mostra summary sem expor preço/configuração de outro owner.
- [ ] Página de status e `sale_detail` isolam corretamente produtor e afiliado.
- [ ] Reenvio simples do seller/colaborador é cobrável e segue a regra do produto.
