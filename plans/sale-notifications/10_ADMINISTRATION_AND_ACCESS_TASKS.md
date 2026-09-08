# Fase 10 — Administração, acesso e rollout

## Objetivo

Entregar a gestão segura das configurações comerciais de comunicações de venda
e dos pacotes de crédito, respeitando a cadeia obrigatória:

```text
Dashboard/Admin → edge-gateway → edge-public-api → Account ou Wallet
```

O browser nunca chama Account ou Wallet diretamente. O Account continua sendo a
fonte de verdade de flags, preços e overrides. A Wallet continua dona de
pacotes e créditos.

## Escopo desta task

1. Expor configurações globais e por usuário do Account para administração.
2. Permitir que o seller controle apenas o uso de saldo normal como fallback.
3. Expor o CRUD administrativo de pacotes de crédito da Wallet.
4. Criar/ligar as telas administrativas necessárias.
5. Cobrir autenticação, autorização, escopo e contratos por testes.

Não incluir nesta task páginas de saldo/recarga, lista de status, timeline de
venda ou reenvio. Elas pertencem às tarefas operacionais do Dashboard.

## Regras de autorização

| Operação | Perfis permitidos | Regra obrigatória |
| --- | --- | --- |
| Ler/editar padrão global | Admin `1` e `2` | Somente esses perfis. |
| Ler/criar/editar/remover override de outro usuário | Admin `1` e `2` | `user_id` vem da rota; validar formato numérico. |
| Listar/criar/editar pacote | Admin `1` e `2` | Nunca expor endpoints internos da Wallet ao browser. |
| Ler/alterar preferência de uso de saldo | Seller autenticado e colaborador dentro do seu escopo, se a regra de colaboração permitir | O `user_id` é sempre o `sub` do JWT; não aceitar alvo no body/URL. |
| Reenvio gratuito | Fora desta task; Admin `1`, `2` e `4` | Perfil `4` não recebe gestão de preço, flag ou pacote. |

O Public API é responsável por extrair `sub` e `permissao` do JWT. O Gateway
apenas preserva o contrato e o status retornado. Account e Wallet não devem
confiar em `user_id` enviado pelo browser como identidade.

## Chaves e semântica

### Globais e overrides administrativos

| Chave Account | Tipo | Default | Pode ter override por usuário | Uso |
| --- | --- | --- | --- | --- |
| `sale_notifications_feature_enabled` | boolean | `false` | Sim | Habilita a feature para o owner. |
| `sale_delivery_whatsapp_enabled` | boolean | `false` | Sim | Permite entrega pós-pagamento por WhatsApp. |
| `sale_delivery_whatsapp_unit_price` | decimal(12,2) | `0.00` | Sim | Valor por WhatsApp de entrega confirmado. |
| `sale_recovery_unit_price` | decimal(12,2) | `0.00` | Sim | Valor por canal de RDC confirmado. |

O valor efetivo é `override ?? global`. Portanto, o rollout pode manter o
padrão global desativado e habilitar sellers específicos por override. A UI
administrativa deve deixar claro quando um valor é herdado e oferecer uma ação
explícita de “remover override”, retornando ao padrão global.

### Preferência do seller

`sale_notifications_allow_seller_balance` existe apenas em `user_system_vars`.
Não criar valor global, não incluir a chave na tela de padrão global e não
permitir que o seller altere flag/preços.

- Sem registro: `effective = true`.
- Com registro `0`: créditos de comunicação continuam prioritários, mas não há
  fallback para saldo disponível do seller.
- Com registro `1`: fallback permitido fora do Checkout Transparente.
- Checkout Transparente nunca usa saldo normal, mesmo com a preferência ativa.

## APIs a implementar

As rotas de Account e Wallet abaixo já existem como contratos internos. A task
deve criar os encaminhamentos em Public API/Gateway e as telas consumidoras.

### Administração de configurações

#### Account interno já disponível

| Método | Rota interna | Finalidade |
| --- | --- | --- |
| `GET` / `PUT` | `/admin/sale-notifications/settings` | Ler/gravar padrão global. |
| `GET` / `PUT` | `/admin/users/{user_id}/sale-notifications/settings` | Ler/gravar override. |
| `DELETE` | `/admin/users/{user_id}/sale-notifications/settings/{key}` | Remover um override. |

#### Rotas públicas a criar

| Método | Public API e Gateway | Destino | Body/resultado |
| --- | --- | --- | --- |
| `GET` | `/admin/sale-notifications/settings` | Account global | Retornar `global`, `override`, `effective` do contrato Account. |
| `PUT` | `/admin/sale-notifications/settings` | Account global | Aceitar somente as quatro chaves globais; atualização parcial. |
| `GET` | `/admin/users/{user_id}/sale-notifications/settings` | Account usuário | Exibir global, override e efetivo. |
| `PUT` | `/admin/users/{user_id}/sale-notifications/settings` | Account usuário | Aceitar as quatro chaves comerciais e `sale_notifications_allow_seller_balance`. |
| `DELETE` | `/admin/users/{user_id}/sale-notifications/settings/{key}` | Account usuário | Validar a chave permitida; remover apenas aquele override. |
| `GET` | `/user/sale-notifications/preferences` | Account do `sub` | Retornar somente `allow_seller_balance`. |
| `PUT` | `/user/sale-notifications/preferences` | Account do `sub` | Aceitar somente `{ "allow_seller_balance": true|false }`. |

### Ajuste mínimo necessário no Account

Os endpoints existentes de override aceitam todas as chaves administrativas e
não devem ser reutilizados diretamente pelo seller. Criar um caso de uso e
rota interna específicos, por exemplo:

```text
GET /users/{user_id}/sale-notifications/preferences
PUT /users/{user_id}/sale-notifications/preferences
```

Esse caso de uso deve permitir exclusivamente
`sale_notifications_allow_seller_balance`. Ele deve responder o mesmo formato
efetivo já usado pelo `SaleNotificationSettingsService`, reduzido a:

```json
{
  "user_id": 123,
  "allow_seller_balance": {
    "override": false,
    "effective": false
  }
}
```

Não duplicar `SystemVarService`, não criar domínio novo e não criar coluna em
`users`.

### Administração de pacotes

#### Wallet interno já disponível

| Método | Rota interna |
| --- | --- |
| `GET` | `/communication-credits/admin/packages` |
| `POST` | `/communication-credits/admin/packages` |
| `PATCH` | `/communication-credits/admin/packages/{id}` |

#### Rotas públicas a criar

| Método | Public API e Gateway | Finalidade |
| --- | --- | --- |
| `GET` | `/admin/communication-credits/packages` | Listar ativos e inativos para administração. |
| `POST` | `/admin/communication-credits/packages` | Criar pacote. |
| `PATCH` | `/admin/communication-credits/packages/{id}` | Editar pacote, inclusive ativação/desativação. |

Contrato de pacote:

```json
{
  "name": "Pacote inicial",
  "amount": "20.00",
  "bonus": "2.00",
  "is_active": true
}
```

Validações:

- `name`: texto não vazio, máximo conforme Request existente.
- `amount`: decimal maior que zero.
- `bonus`: decimal maior ou igual a zero.
- `is_active`: booleano.
- Não excluir pacote que já possa ser referência de compra; desativar com
  `is_active = false`.

## Implementação por repositório

### `services-account`

1. Criar request/caso de uso/controller para a preferência limitada do próprio
   usuário, usando `SaleNotificationSettingsService` e `SystemVarService`
   existentes.
2. Garantir que esse caminho nunca aceite as quatro chaves administrativas.
3. Criar testes unitários para default `true`, salvar `false`, reativar `true`
   e rejeitar payload com chave comercial.
4. Não alterar defaults, prioridades ou a regra de Checkout Transparente.

### `edge-public-api`

1. Criar controller/client para Account administrativo e preferência própria.
2. Criar controller/client para o CRUD administrativo de pacotes na Wallet.
3. Registrar as rotas JWT acima.
4. Proteger administração exclusivamente com `permissao in [1, 2]`.
5. Resolver o usuário da preferência exclusivamente a partir de `sub`.
6. Repassar status e corpo de Account/Wallet sem remodelar erros de negócio.
7. Manter imports de `routes/api.php` em ordem alfabética.

### `edge-gateway`

1. Espelhar exatamente as rotas do Public API.
2. Usar o proxy/controller existente; não implementar regra de autorização aqui.
3. Preservar método, path, body, query, status e resposta.

### Front administrativo

Localizar a tela administrativa existente que concentra restrições/configurações
de seller. Não criar uma segunda fonte de verdade no Dashboard.

Implementar:

1. Seção de padrão global: flag, WhatsApp de entrega e dois preços.
2. Busca/seleção de seller para leitura e edição de override.
3. Estado visual de herdado versus override e ação de remover override por
   chave.
4. Seção de pacotes: listagem, criação, edição e toggle de ativo.
5. Preferência do seller: toggle “Usar saldo disponível quando não houver
   créditos de comunicação”, separado das configurações comerciais.
6. Textos que expliquem: crédito é prioritário; saldo não é usado no Checkout
   Transparente; desativar essa preferência pode impedir um envio pago mesmo
   havendo saldo normal.

Não mostrar segredos, dados de Wallet de terceiros nem permitir alterar
`owner_user_id` pelo formulário.

## Fluxos de aceite

### A. Rollout por seller

1. Global permanece `feature_enabled = false`.
2. Admin 1/2 grava override `true` para seller A.
3. `GET` administrativo do seller A retorna global `false`, override `true` e
   efetivo `true`.
4. Seller B, sem override, continua com efetivo `false`.

### B. Preço efetivo

1. Admin altera o preço global de RDC.
2. Seller sem override recebe o novo valor efetivo.
3. Admin grava preço próprio para seller A.
4. Alterações globais posteriores não mudam o efetivo de A.
5. Admin remove o override de A; ele volta imediatamente ao global.

### C. Preferência de saldo

1. Seller sem registro lê `effective = true`.
2. Seller grava `false` e lê `override = false`, `effective = false`.
3. Uma chamada autenticada de seller não consegue gravar preço/flag comercial.
4. Seller A não consegue ler nem alterar a preferência de seller B.

### D. Pacotes

1. Admin 1/2 cria pacote com amount e bonus.
2. Seller comum recebe `403` em todas as rotas `/admin/communication-credits/*`.
3. Admin desativa pacote existente; compras antigas continuam consultáveis e o
   pacote deixa de aparecer na listagem pública de ativos.
4. Perfil 4 recebe `403` em configurações e pacotes.

## Testes obrigatórios

- Unitários no Account para a preferência limitada do usuário.
- Feature/integration tests no Public API para `1`, `2`, `4`, seller e usuário
  sem JWT: `200`, `401` e `403` corretos.
- Tests de forwarding Public API → Account/Wallet, incluindo erro `422` e `404`.
- Testes do Gateway que comprovem o proxy das novas rotas.
- Testes da Wallet para validação de pacote e bloqueio de criação por usuário
  comum na borda pública.
- Smoke test em homologação: admin habilita apenas um seller sintético, lê o
  efetivo e reverte a alteração; criar/desativar um pacote sintético e limpar
  ou manter desativado com marcador de homologação.

## Fora de escopo

- Criar ou cobrar recargas PIX.
- Saldo, histórico, status de RDC/entrega e timeline.
- Reenvio seller, colaborador ou admin.
- Alterar lógica de hold/consume/release no Commerce/Wallet.
- Mudar template Meta/e-mail ou configuração de providers.

## Critérios de aceite

- [ ] Admin 1/2 gerencia padrão, override e pacotes exclusivamente via
  Gateway → Public API → serviço dono.
- [ ] Perfil 4 e seller comum não conseguem alterar dados administrativos.
- [ ] Seller altera somente sua preferência de saldo; não altera flag/preço.
- [ ] Toda resposta de configuração informa global, override e efetivo quando
  aplicável.
- [ ] Remover override restaura o padrão sem apagar configuração global.
- [ ] Pacote utilizado nunca é excluído; apenas desativado.
- [ ] Há cobertura automatizada de autorização e do contrato de forwarding.
- [ ] O smoke test em homologação é reversível e documentado.
