# Fase 1 — Gestão de recuperação por produto

## Escopo

Esta fase entrega apenas configuração e visualização por produto. Ela não cria
dispatches, não agenda filas, não envia mensagens e não cobra o seller ou
afiliado.

Os detalhes completos de regras de negócio e das próximas fases estão no
[README](README.md).

## Rotas

### Reaproveitadas

| Rota | Responsabilidade nesta fase |
| --- | --- |
| `GET /products/{product_id}/form-data` | Retornar `sale_recovery` para a edição do produto do produtor. |
| `PATCH /products/{product_id}` | Receber e salvar `sale_recovery` no payload de edição do produtor. |
| `GET /affiliates/affiliated-products/{affiliate_id}` | Carregar o contexto e validar a afiliação antes de editar a regra do afiliado. |

### Novas

| Rota | Responsabilidade |
| --- | --- |
| `GET /affiliates/affiliated-products/{affiliate_id}/sale-recovery` | Buscar a regra própria do afiliado para o produto vinculado à afiliação. |
| `PUT /affiliates/affiliated-products/{affiliate_id}/sale-recovery` | Criar/atualizar a regra própria do afiliado. |
| `POST /products/sale-recovery/summaries` | Retornar em lote o resumo para as linhas da listagem de produtos. |

Payload do produtor no `PATCH /products/{product_id}`:

```json
{
  "sale_recovery": {
    "enabled": true,
    "steps": [
      { "stage": 1, "delay_minutes": 20, "channels": ["whatsapp", "email"] },
      { "stage": 2, "delay_minutes": 40, "channels": ["whatsapp"] }
    ]
  }
}
```

## Responsabilidades por arquivo

### `services-commerce-v2`

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| `migrations/<timestamp>_create_product_sale_recovery_rules.php` | Novo | Criar regra por produto e responsável (produtor ou afiliado). |
| `migrations/<timestamp>_create_product_sale_recovery_rule_steps.php` | Novo | Criar até dois stages e seus atrasos. |
| `migrations/<timestamp>_create_product_sale_recovery_rule_step_channels.php` | Novo | Criar os canais e-mail/WhatsApp de cada stage. |
| `app/Model/ProductSaleRecoveryRule.php` | Novo | Modelo e relações da regra. |
| `app/Model/ProductSaleRecoveryRuleStep.php` | Novo | Modelo e relações do stage. |
| `app/Model/ProductSaleRecoveryRuleStepChannel.php` | Novo | Modelo do canal por stage. |
| `app/Domain/SaleRecovery/Repository/*` | Novo | Consultas e persistência das três entidades. |
| `app/Application/UseCase/Product/GetProductFormDataUseCase.php` | Alterar | Acrescentar a chave `sale_recovery` ao agregado usado pela tela de produto. |
| `app/Application/UseCase/Product/UpdateProductUseCase.php` | Alterar | Extrair `sale_recovery` do payload geral e delegar a gravação da regra do produtor. |
| `app/Application/UseCase/SaleRecovery/SaveProductSaleRecoveryUseCase.php` | Novo | Validar e salvar regra do produtor de forma transacional. |
| `app/Application/UseCase/SaleRecovery/GetAffiliateProductSaleRecoveryUseCase.php` | Novo | Buscar regra do afiliado somente quando a afiliação pertence ao usuário. |
| `app/Application/UseCase/SaleRecovery/SaveAffiliateProductSaleRecoveryUseCase.php` | Novo | Validar e salvar regra individual do afiliado. |
| `app/Application/UseCase/SaleRecovery/ListProductSaleRecoverySummariesUseCase.php` | Novo | Buscar summaries em lote, sem N+1 e no contexto do usuário. |
| `app/Http/Controller/ProductController.php` | Alterar | Passar `sale_recovery` para o caso de uso no update e expor o summary em lote. |
| `app/Http/Controller/AffiliateController.php` | Alterar | Adicionar leitura e gravação de recovery para produto afiliado. |
| `app/Http/Request/*SaleRecovery*.php` | Novos | Validar o payload: até dois stages, atraso de 0–120 min, diferença mínima de 10 min, e 1–2 canais por stage. |
| `config/routes.php` | Alterar | Registrar as três rotas novas, antes de rotas dinâmicas que possam conflitar. |

### `dashboard-seller` — produto do produtor

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| `product_form.php` | Alterar | Exibir a seção “Recuperação de vendas”: toggle, stages, atraso e checkboxes de WhatsApp/e-mail. Carregar valores de `form-data`. |
| `app/request/ProductForm.php` | Alterar | Preservar/normalizar o objeto `sale_recovery` submetido pela tela, sem tratá-lo como coluna de `tbl_produtos`. |
| `app/request/CommerceV2ProductPayloadNormalizer.php` | Alterar | Encaminhar `sale_recovery` no formato esperado pelo Commerce V2. |
| `api/product/update.php` | Alterar | Manter `sale_recovery` no payload enviado ao `PATCH /products/{id}`. |
| `api/product/create.php` | Verificar | Não enviar recovery em criação inicial, salvo se a UI de novo produto também receber essa seção. |

### `dashboard-seller` — produto do afiliado

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| `affiliate_product_detail.php` | Alterar | Exibir a configuração individual do afiliado, sem exibir nem herdar a regra do produtor. |
| Endpoint/API local associado à tela de afiliado | Novo ou alterar | Chamar o `GET`/`PUT /affiliates/affiliated-products/{affiliate_id}/sale-recovery` pelo gateway autenticado. |
| `app/services/ProductAffiliateProgramService.php` ou novo `SaleRecoveryService.php` | Alterar/novo | Encapsular as requisições ao Commerce V2; preferir um serviço dedicado se o escopo não for programa de afiliados. |

### `dashboard-seller` — listagem de produtos

| Arquivo | Tipo | Responsabilidade |
| --- | --- | --- |
| `products.php` | Alterar | Reservar o local visual do badge/resumo de recovery na linha/card de produto. |
| `api/products_list.php` | Alterar | Após obter os produtos, chamar summaries em lote e injetar o resumo no HTML/JSON retornado. |
| Serviço cliente do Commerce V2 (novo ou existente) | Novo/alterar | Fazer o `POST /products/sale-recovery/summaries` para todos os IDs da página. |

## Regras que backend e frontend devem aplicar

- A regra é individual por produto.
- Produtor configura sua própria regra; afiliado configura a regra da própria afiliação para aquele produto.
- A venda afiliada nunca usa a regra do produtor.
- Há no máximo dois stages.
- Cada stage pode ter WhatsApp, e-mail ou ambos.
- O atraso máximo é duas horas após a venda; entre stage 1 e 2 há pelo menos dez minutos.
- A listagem só mostra o resumo aplicável ao usuário/contexto atual.

## Critérios de aceite

- [ ] O produtor salva e relê a configuração na edição de produto.
- [ ] O afiliado salva e relê sua configuração sem acessar a configuração do produtor.
- [ ] A UI e a API rejeitam terceiro stage, stage sem canal, atraso acima de 120 minutos ou intervalo menor que dez minutos.
- [ ] A listagem exibe summary correto sem uma requisição por produto.
- [ ] Nenhuma venda é agendada, nenhuma mensagem é enviada e nenhuma cobrança é criada nesta fase.
