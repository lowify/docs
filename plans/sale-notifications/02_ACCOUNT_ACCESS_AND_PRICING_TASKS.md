# Fase 2 — Account: acesso, preço e configuração global

## Banco e SQL manual

No banco do Account, inserir em `system_vars`:

| Chave | Valor inicial |
| --- | --- |
| `sale_notifications_feature_enabled` | `0` |
| `sale_delivery_whatsapp_enabled` | `0` |
| `sale_delivery_whatsapp_status_timeout_seconds` | `180` |
| `sale_delivery_whatsapp_hold_timeout_seconds` | `600` |
| `sale_delivery_email_provider_primary` | `sendgrid` |
| `sale_delivery_email_provider_secondary` | `mailtrap` |
| `sale_delivery_whatsapp_unit_price` | valor comercial |
| `sale_recovery_unit_price` | valor comercial |

Usar `user_system_vars` para overrides de flag e preço. Não criar coluna em tabela de usuário e não replicar estado em Commerce.

## Domínio e API

| Camada | Pendência |
| --- | --- |
| Model/repository | Mapear leitura/upsert/delete de `user_system_vars` e leitura de `system_vars`. |
| Use case | Resolver flag e preço efetivos por `user_id`, usando override → global. |
| Use case | Administrar override e remoção com autorização adequada. |
| Controller + Request | Expor consulta interna para Commerce e operações administrativas para Public API. |
| JsonResponder/exceptions | Manter formato e erros padrão do Account. |
| Testes | Fallback global, override, remoção, usuário inexistente e autorização. |

## Contratos

- Commerce consulta Account antes de salvar regra, agendar RDC e iniciar entrega.
- Wallet recebe `owner_user_id` e valor já resolvido; não consulta preço no Account.
- Dashboard acessa Account somente via Gateway/Public API.
- A resposta de preço devolve global, override (ou `null`) e efetivo; o browser não calcula valor.

## Critérios de aceite

- [ ] Sem override, todos usam o padrão global.
- [ ] Override de afiliado não altera o produtor e vice-versa.
- [ ] Feature desativada bloqueia operação e envio.
- [ ] Commerce não depende de conexão/tabela do Account.
