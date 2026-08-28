# Fase 1 — Configuração de comunicação por produto

## Escopo

Adicionar à configuração existente de RDC a opção independente de entrega pós-compra por WhatsApp. Produtor configura o produto próprio; afiliado configura sua afiliação/produto. A venda de afiliado nunca usa a configuração do produtor.

## Dados

Manter as tabelas de RDC: `product_sale_recovery_rules`, etapas e canais.

Criar `product_sale_delivery_rules` com `product_id`, `owner_user_id`, `owner_type` (`producer|affiliate`), `affiliate_id`, `whatsapp_enabled` e timestamps. A unicidade usa `affiliate_scope_id` gerada por `COALESCE(affiliate_id, 0)`, impedindo duplicidade de produtor mesmo com `affiliate_id = NULL`.

## Rotas

| Rota | Uso |
| --- | --- |
| `GET /products/{id}/form-data` | Incluir RDC, entrega WhatsApp e custos efetivos somente leitura. |
| `PATCH /products/{id}` | Salvar RDC e `sale_delivery.whatsapp_enabled` do produtor. |
| `GET/PUT /affiliates/affiliated-products/{affiliateId}/sale-recovery` | Manter RDC do afiliado. |
| `GET/PUT /affiliates/affiliated-products/{affiliateId}/sale-delivery` | Nova configuração de entrega WhatsApp do afiliado. |
| `POST /products/sale-notifications/summaries` | Novo resumo em lote para lista de produtos. |

## Responsabilidades

- `services-commerce-v2`: SQL manual, modelos, repositórios e casos de uso para ler/salvar regras no contexto do responsável.
- `services-account`: fornecer feature flags e preços efetivos por usuário.
- `edge-public-api` e `edge-gateway`: expor contratos ao Dashboard com JWT/autorização.
- `dashboard-seller`: incluir toggles de RDC e entrega em `product_form.php` e `affiliate_product_detail.php`; mostrar preço efetivo, sem permitir edição.

## Pendências técnicas por componente

| Componente | Tabelas/SQL | Classes e contratos | UI/validação |
| --- | --- | --- | --- |
| Commerce V2 | Adicionar `product_sale_delivery_rules` ao SQL manual; manter/criar tabelas de RDC no mesmo deploy. | `ProductSaleDeliveryRule` model, repository, `Get/SaveProductSaleDeliveryUseCase`; ampliar `GetProductFormDataUseCase`, `UpdateProductUseCase`, `ProductController` e `AffiliateController`. | Request DTO valida booleano e resolve owner pelo JWT/afiliação, nunca pelo payload. |
| Account | Nenhuma regra de produto. | Cliente interno para flag/preço efetivos. | Retornar preços somente leitura no form-data. |
| Public API/Gateway | Sem banco. | Rotear `GET/PUT` de delivery afiliado e summary ao Commerce. | Preservar `sub` como owner autenticado. |
| Dashboard | Sem banco. | Normalizer/Payload de produto mantém `sale_delivery`; cliente via Gateway. | Toggle de produtor e afiliado, badge de lista, tratamento de feature desativada. |

## SQL e compatibilidade

- O SQL manual deve ser idempotente no nível de deploy ou possuir pré-checagem operacional; não alterar SQL já aplicado.
- A regra de afiliado exige `affiliate_id` válido e ativo, e `affiliate_id` é `NULL` para produtor; a coluna técnica gerada `affiliate_scope_id` existe apenas para o índice único.
- Não incluir flag de entrega em `tbl_produtos`: ela pertence ao contexto proprietário produto/afiliação.

## Critérios de aceite

- [ ] Produtor e afiliado leem/salvam apenas as próprias regras.
- [ ] A venda afiliada resolve apenas a configuração do afiliado.
- [ ] A lista mostra resumo sem N+1.
- [ ] Nenhuma mensagem ou crédito é movimentado nesta fase.
