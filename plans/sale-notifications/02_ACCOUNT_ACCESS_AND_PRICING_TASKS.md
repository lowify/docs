# Fase 2 — Account: acesso, preço e configuração global

## Banco e SQL manual

No banco do Account, inserir em `system_vars`:

| Chave | Valor inicial |
| --- | --- |
| `sale_notifications_feature_enabled` | `0` |
| `sale_delivery_whatsapp_enabled` | `0` |
| `sale_delivery_whatsapp_unit_price` | valor comercial |
| `sale_recovery_unit_price` | valor comercial |

Usar `user_system_vars` para overrides de flag e preço. Não criar coluna em tabela de usuário e não replicar estado em Commerce.

O SQL manual em `deploy/001_sale_notifications.sql` cria `user_system_vars` somente
quando ausente e garante `updated_at` + unicidade por (`user_id`, `var_key`) em
instalações legadas. A pré-checagem de duplicidade deve retornar vazia antes do
índice único ser aplicado.

## Domínio e API

| Camada | Pendência |
| --- | --- |
| Model/repository | **Concluído:** componente genérico `SystemVar` para leitura/upsert global e por usuário, incluindo remoção de override. |
| Use case | **Concluído:** serviço de aplicação `SaleNotificationSettingsService` resolve flag e preço efetivos por `user_id`, usando override → global. |
| Use case | **Concluído:** salva e remove override. A autorização é responsabilidade do Gateway/Public API. |
| Controller + Request | **Concluído:** expõe consulta interna para Commerce e contratos administrativos. |
| JsonResponder/exceptions | **Concluído:** respostas seguem `JsonResponder` e `UseCaseException`. |
| Testes | **Concluído (unitário):** fallback global, override isolado, remoção, usuário inexistente e validação de preço. A autorização 1/2 será coberta no Gateway/Public API, onde o JWT existe. |

## Contratos

- Commerce consulta Account antes de salvar regra, agendar RDC e iniciar entrega.
- Wallet recebe `owner_user_id` e valor já resolvido; não consulta preço no Account.
- Dashboard acessa Account somente via Gateway/Public API.
- A resposta de preço devolve global, override (ou `null`) e efetivo; o browser não calcula valor.

### Rotas implementadas no Account

| Método | Rota | Consumidor |
| --- | --- | --- |
| `GET` | `/users/{user_id}/sale-notifications/settings` | Commerce, contrato interno. |
| `GET` / `PUT` | `/admin/sale-notifications/settings` | Gateway/Public API para ler/alterar padrão global. |
| `GET` / `PUT` | `/admin/users/{user_id}/sale-notifications/settings` | Gateway/Public API para ler/alterar override. |
| `DELETE` | `/admin/users/{user_id}/sale-notifications/settings/{key}` | Gateway/Public API para remover um override e voltar ao padrão. |

O Account não recebe identidade/permissão administrativa nessas chamadas. O Gateway/Public
API deverá limitar as rotas administrativas às permissões **1 e 2** antes de encaminhá-las.

`SystemVarService` é genérico e pode atender futuras configurações sem acoplar persistência
à feature. O serviço de aplicação `SaleNotificationSettingsService` contém somente o contrato
específico: chaves permitidas, defaults, validação e montagem de efetivo.

## Critérios de aceite

- [x] Sem override, todos usam o padrão global.
- [x] Override de afiliado não altera o produtor e vice-versa.
- [x] Feature desativada é exposta ao Commerce para bloquear operação e envio.
- [x] Commerce não depende de conexão/tabela do Account.
