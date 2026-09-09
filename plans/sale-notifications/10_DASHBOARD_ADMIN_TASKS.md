# Fase 10 — Dashboard Admin: comunicações de venda

## Objetivo

Entregar na tela existente **“Configurações do admin”** toda a gestão
administrativa de comunicações de venda: rollout, preços, overrides por seller
e pacotes de créditos. Não criar uma página administrativa paralela.

O caminho obrigatório é:

```text
Dashboard Admin → edge-gateway → edge-public-api → Account ou Wallet
```

O browser não chama serviços internos e não define `owner_user_id`.

## Permissões

| Ação | Perfis permitidos |
| --- | --- |
| Ler/editar padrão global | Admin `1` e `2` |
| Ler/criar/editar/remover override por seller | Admin `1` e `2` |
| Listar/criar/editar/desativar pacotes | Admin `1` e `2` |
| Reenvio gratuito | Fora desta task; `1`, `2` e `4` |

Admin `4` não pode alterar flags, preços, overrides ou pacotes. Seller e
colaborador também não.

## Modelo de configuração

| Chave Account | Default | Override por seller | Significado |
| --- | --- | --- | --- |
| `sale_notifications_feature_enabled` | `false` | Sim | Habilita a feature para o owner. |
| `sale_delivery_whatsapp_enabled` | `false` | Sim | Permite WhatsApp na entrega pós-pagamento. |
| `sale_delivery_whatsapp_unit_price` | `0.00` | Sim | Preço por WhatsApp de entrega confirmado. |
| `sale_recovery_unit_price` | `0.00` | Sim | Preço por canal RDC confirmado. |

O efetivo é `override ?? global`. Isso permite manter globalmente desativado e
habilitar apenas sellers selecionados. A interface deve distinguir claramente
valor herdado de override e permitir remover um override por chave.

`sale_notifications_allow_seller_balance` não pertence a este painel: é uma
preferência exclusiva do seller, detalhada em
[11_DASHBOARD_SELLER_TASKS.md](11_DASHBOARD_SELLER_TASKS.md).

## APIs e responsabilidades

### Account interno já disponível

| Método | Rota |
| --- | --- |
| `GET` / `PUT` | `/admin/sale-notifications/settings` |
| `GET` / `PUT` | `/admin/users/{user_id}/sale-notifications/settings` |
| `DELETE` | `/admin/users/{user_id}/sale-notifications/settings/{key}` |

O Account recebe chamadas internas; não recebe JWT nem decide se o chamador é
admin. Ele já valida chaves e valores.

### Wallet interno já disponível

| Método | Rota |
| --- | --- |
| `GET` | `/communication-credits/admin/packages` |
| `POST` | `/communication-credits/admin/packages` |
| `PATCH` | `/communication-credits/admin/packages/{id}` |

### Rotas a criar no Public API e Gateway

| Método | Rota pública | Destino |
| --- | --- | --- |
| `GET` / `PUT` | `/admin/sale-notifications/settings` | Account global |
| `GET` / `PUT` | `/admin/users/{user_id}/sale-notifications/settings` | Account override |
| `DELETE` | `/admin/users/{user_id}/sale-notifications/settings/{key}` | Account override |
| `GET` | `/admin/communication-credits/packages` | Wallet |
| `POST` | `/admin/communication-credits/packages` | Wallet |
| `PATCH` | `/admin/communication-credits/packages/{id}` | Wallet |

Public API extrai `sub` e `permissao` do JWT, exige permissão `1` ou `2`,
valida IDs numéricos e repassa o contrato ao serviço dono. Gateway apenas
espelha método, path, body, status e resposta; ele não duplica autorização.

## Interface — Configurações do admin

Adicionar uma seção própria **“Comunicações de venda”** na tela existente.

### Bloco 1 — padrão global

Campos:

1. Toggle “Ativar comunicações de venda”.
2. Toggle “Permitir WhatsApp na entrega pós-pagamento”.
3. Campo monetário “Preço do WhatsApp de entrega”.
4. Campo monetário “Preço por canal de recuperação de venda”.

Regras de UX:

- Carregar com `GET /admin/sale-notifications/settings`.
- Enviar atualização parcial por `PUT`.
- Mostrar valor efetivo/global, sem usar cálculos no browser.
- Validar decimal positivo ou zero com duas casas; não aceitar valores vazios,
  negativos ou formatos inválidos.
- Informar que preço `0.00` impede comunicações pagas, mesmo com feature ativa.

### Bloco 2 — configuração por seller

1. Usar o seletor/busca de seller já existente na área administrativa.
2. Carregar `GET /admin/users/{user_id}/sale-notifications/settings` ao
   selecionar seller.
3. Para cada chave comercial, mostrar global, override e efetivo.
4. Permitir salvar um ou mais overrides por `PUT`.
5. Permitir “Voltar ao padrão global” por chave usando `DELETE`.
6. Não permitir alterar o identificador do seller por campos editáveis.

### Bloco 3 — pacotes de crédito

Listar pacotes ativos e inativos com `name`, `amount`, `bonus`, estado e data
de atualização. Permitir criar e editar:

```json
{
  "name": "Pacote inicial",
  "amount": "20.00",
  "bonus": "2.00",
  "is_active": true
}
```

Validações:

- `name` não vazio;
- `amount > 0`;
- `bonus >= 0`;
- `is_active` booleano;
- nunca excluir pacote usado por compras: desativar com `is_active = false`.

### Bloco 4 — comunicação na venda (admin)

Na tela `admin_sale_detail`, incluir uma seção **“Comunicações de venda”** que
sempre é visível ao admin autorizado, inclusive quando o owner da venda for um
afiliado.

Exibir a timeline obtida de `GET /sales/{sale_id}/communications`:

- tentativa de entrega, canal, provider, status e timestamps;
- dispatch de RDC, etapa, canal, motivo de skip/falha e eventos do provider;
- owner financeiro, tipo/id do autor de reenvio, fonte de funding e preço
  congelado, quando existirem;
- confirmação tardia, timeout e estado de cobrança.

Adicionar ação **“Reenviar comunicação”** para admin `1`, `2` e `4`:

1. Abrir modal para selecionar e-mail, WhatsApp ou ambos.
2. Permitir WhatsApp mesmo que ele esteja desligado na regra do produto.
3. Não fazer fallback automático entre canais escolhidos.
4. Informar que o reenvio administrativo é gratuito.
5. O backend resolve `owner_user_id`, `author_type = admin`, `author_user_id`
   e `chargeable = false`; o browser não envia esses campos.

O contrato atual de reenvio simples precisa ser expandido no Commerce/Public
API/Gateway para receber explicitamente `channels`, por exemplo:

```json
{ "channels": ["email", "whatsapp"] }
```

Rejeitar lista vazia, canal desconhecido e seller tentando usar esse contrato
administrativo.

## Implementação por repositório

### `edge-public-api`

1. Criar clients/controllers para Account administrativo e pacotes da Wallet.
2. Registrar as seis rotas com middleware JWT e autorização exclusiva `1|2`.
3. Repassar erros de negócio `404` e `422` sem convertê-los em sucesso.
4. Manter imports de `routes/api.php` em ordem alfabética.
5. Ajustar o endpoint de reenvio administrativo para encaminhar a seleção de
   canais apenas quando o JWT for admin `1`, `2` ou `4`.
6. Preservar a checagem de permissão e escopo ao consultar comunicações de uma
   venda no detalhe administrativo.

### `edge-gateway`

1. Espelhar as seis rotas do Public API.
2. Encaminhar método, corpo, query, status e payload sem regra de negócio.
3. Espelhar o contrato de reenvio administrativo e de consulta de comunicações.

### Front administrativo

1. Localizar a implementação da tela **Configurações do admin**.
2. Criar a seção e os três blocos descritos acima, seguindo componentes visuais
   já existentes.
3. Tratar loading, sucesso, erro e atualização otimista com reversão em erro.
4. Nunca renderizar dados de outro seller após troca de seleção/loading.
5. Implementar a timeline e o modal de reenvio na tela `admin_sale_detail`.

## Fluxos de aceite

### Rollout por seller

1. Global fica `feature_enabled = false`.
2. Admin 1/2 salva override `true` para seller A.
3. Seller A retorna global `false`, override `true`, efetivo `true`.
4. Seller B, sem override, continua efetivo `false`.

### Preço efetivo

1. Alterar preço global de RDC.
2. Seller sem override recebe novo efetivo.
3. Definir preço exclusivo para seller A.
4. Alterar global não muda A.
5. Remover override de A faz A voltar ao global.

### Pacotes

1. Admin cria pacote com amount e bonus.
2. Admin desativa pacote existente.
3. Compras antigas permanecem consultáveis.
4. A listagem pública de pacotes ativos não retorna o pacote desativado.

### Reenvio administrativo

1. Admin 1/2/4 abre uma venda que pertence a produtor ou afiliado.
2. Timeline apresenta todas as tentativas e dispatches, sem depender de quem é
   o owner financeiro.
3. Admin seleciona somente e-mail, somente WhatsApp ou ambos.
4. O reenvio é registrado com autor admin e não cria hold/consumo de crédito ou
   saldo.
5. Payload com `owner_user_id`, `chargeable` ou autor enviado pelo browser é
   ignorado/rejeitado; o backend determina esses dados.

## Testes obrigatórios

- Public API: admin 1/2 recebe `200`; admin 4 e seller recebem `403`; sem JWT
  recebe `401`.
- Forwarding Public API → Account/Wallet, incluindo respostas `422` e `404`.
- Gateway: proxy das seis rotas e preservação de status/payload.
- Front: carregamento de global, override, remoção e erro de API.
- Commerce/Public API/Gateway: seleção de canais no reenvio administrativo,
  gratuidade e autor resolvido no backend.
- Front admin: timeline, visibilidade para owner afiliado e modal com os três
  cenários de canais.
- Homologação: usar seller sintético para habilitar override e revertê-lo; criar
  pacote com marcador de homologação e deixá-lo desativado após teste.

## Fora de escopo

- Preferência financeira do seller.
- Recargas PIX e saldo do seller.
- Página de status do seller e reenvio cobrável do seller/colaborador.
- Alterar hold/consume/release no Commerce/Wallet.

## Critérios de aceite

- [ ] Apenas admin 1/2 administra flags, preços, overrides e pacotes.
- [ ] Tudo fica na tela “Configurações do admin”.
- [ ] Override removido volta ao padrão global.
- [ ] Pacotes são desativados, nunca apagados.
- [ ] `admin_sale_detail` mostra timeline completa, inclusive de venda afiliada.
- [ ] Admin 1/2/4 reenvia os canais selecionados sem cobrança.
- [ ] Browser não chama Account/Wallet diretamente.
- [ ] Cobertura de autorização e forwarding existe.
