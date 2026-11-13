# Relatório técnico — conteúdo externo e redirecionamentos no Checkout

| Campo | Valor |
| --- | --- |
| Data | 13/11/2026 |
| Sistema | Checkout público da Lowify |
| Escopo | Dashboard Seller, Commerce V2, edge-gateway e front-checkout |
| Tema | Conteúdo externo exibido pelo Checkout e destinos externos acionados pelo navegador |

## Resumo

O Checkout da Lowify permite que configurações de produto determinem conteúdo e destinos externos usados na página pública. Os três caminhos principais são o iframe inserido pelo Checkout Styler, a URL de saída do Checkout e a URL de redirecionamento pós-pagamento.

Esses caminhos são funcionalidades de produto. Ao mesmo tempo, vinculam o domínio de pagamento da Lowify a conteúdo e domínios que podem estar fora do controle direto da plataforma. O sistema não mantém hoje uma política central de domínios aprovados nem um registro da navegação final do comprador.

Esse cenário pode contribuir para risco de reputação, phishing, mixed content e perda de confiança no Checkout. Ele não demonstra, isoladamente, a causa de uma classificação específica por McAfee, Avast ou qualquer outro motor.

## Arquitetura e fluxo atual

```text
Dashboard Seller
  -> seller configura o produto e o checkout
  -> Commerce V2 persiste os campos do produto
  -> edge-gateway expõe as rotas públicas de checkout
  -> front-checkout recebe o contexto do produto
  -> navegador do comprador renderiza conteúdo e executa destinos configurados
```

O `front-checkout` consulta o contexto do produto em `GET /checkout/context/{short_code}`. Ele recebe dados já persistidos e os usa para montar a página. O Commerce V2 é o componente que recebe alterações de produto, incluindo `checkout_config`, `checkout_url_saida` e `redirect_url_after_payment`.

## Conteúdo externo exibido no Checkout

### Embed de iframe

O Checkout Styler aceita `video_type=iframe`. No salvamento, a regra remove tags `<script>` e confirma somente a presença de uma tag `<iframe>`. O HTML restante é persistido em `checkout_config.video_source`.

No Checkout público, `video_source` é concatenado ao HTML da página quando o tipo é `iframe`. Não há, nesse fluxo, lista de provedores, validação central de origem, exigência de HTTPS, bloqueio de `srcdoc`, configuração de `sandbox` ou restrição de atributos do iframe.

O efeito prático é que uma página em domínio da Lowify pode mostrar conteúdo hospedado por terceiro. Esse conteúdo pode mudar no servidor externo sem uma nova alteração no produto dentro da Lowify.

| Campo persistido | Uso no Checkout |
| --- | --- |
| `checkout_config.video_type` | Define que o conteúdo é tratado como iframe. |
| `checkout_config.video_source` | Contém o HTML que é emitido na página pública. |
| `checkout_config.video_position` | Define a posição do bloco de vídeo no Checkout. |

### Vídeos, banners, imagens e pixels

O Checkout também carrega vídeos, banners, imagens e pixels de origens externas. MP4/MOV usam URL; YouTube e Vimeo usam URL para extrair o identificador do vídeo; banners e imagens existem como dados do produto; pixels carregam scripts de provedores de tracking.

Há validações específicas em alguns pontos, mas não há uma política única no modelo de produto que relacione origem, seller, domínio aprovado e tipo de recurso. Caminhos de vídeo aceitam URL genérica e há validações que permitem URLs com `http://`.

HTTPS protege o transporte, mas não demonstra que um domínio é legítimo, controlado pelo seller ou apropriado para um fluxo de pagamento.

## Redirecionamentos externos

### URL de saída

`checkout_url_saida` pertence ao produto. Quando o popup de saída não está ativo, o Checkout verifica se o valor é uma URL válida e executa `window.location.replace(exitUrl)` quando o comprador move o mouse para fora da tela ou usa o botão Voltar.

O campo pode conter um destino externo. O fluxo não associa esse destino a uma lista de domínios do seller, a uma aprovação administrativa ou a uma verificação de controle de domínio.

### URL pós-pagamento

`redirect_url_after_payment` pertence ao produto. Após identificar uma venda como paga, o Commerce V2 devolve essa URL como ação `redirect`. O endpoint do `front-checkout` entrega a mesma ação ao navegador, que navega para o destino.

A validação do contrato de atualização de produto trata esse valor como `string`. O navegador recebe uma URL externa em vez de um identificador interno de destino ou de uma rota da própria Lowify.

### Consequências dos fluxos

| Fluxo | Momento | O que o navegador recebe | Registro atual |
| --- | --- | --- | --- |
| Saída | tentativa de deixar o Checkout | `checkout_url_saida` | não há evento de navegação associado à venda; |
| Pós-pagamento | venda aprovada | `redirect_url_after_payment` | há a venda, mas não há registro de que o browser seguiu o destino; |
| Upsell | etapas do funil | URL da próxima etapa ou destino final | a rota pode representar página interna ou destino externo, conforme o contexto persistido. |

O banco permite identificar produtos configurados com esses campos e as vendas desses produtos. Ele não permite concluir, pelo modelo atual, se um comprador chegou ao destino externo, qual resposta recebeu lá ou se o conteúdo apresentado no destino foi alterado posteriormente.

## Reputação e cabeçalhos

O risco principal descrito neste relatório não é a ausência de um cabeçalho: é a relação entre o domínio de pagamento e recursos ou destinos externos sem uma política única de confiança.

Uma `Content-Security-Policy` pode restringir carregamentos permitidos pelo navegador. Ela não altera, por si só, URLs persistidas, a autorização do seller para usar um domínio ou a lógica de redirecionamento pós-pagamento.

O Checkout usa serviços externos legítimos, como pixels, reCAPTCHA, players de vídeo e mídia. Uma CSP efetiva tem impacto funcional dependente das origens incluídas na política. O modo `Report-Only` permite observar origens antes de bloquear recursos, caso essa seja a direção escolhida.

## Dados disponíveis para inventário

| Tabela/campo | Conteúdo |
| --- | --- |
| `tbl_produtos.checkout_url_saida` | destino acionado ao sair do Checkout; |
| `tbl_produtos.redirect_url_after_payment` | destino devolvido após pagamento aprovado; |
| `tbl_produtos.checkout_config` | JSON de vídeo, aparência e outras personalizações; |
| `tbl_produtos.checkout_banner_url` | banner ou lista de banners do Checkout; |
| `sales` | venda, status, método de pagamento, data e pedido; |
| `tbl_sale_items` | vínculo entre venda e produto. |

### Produtos com destino, iframe ou mídia HTTP

```sql
SELECT
  p.id_produto,
  p.id_usuario AS seller_id,
  p.titulo,
  p.status,
  p.checkout_url_saida,
  p.redirect_url_after_payment,
  JSON_UNQUOTE(JSON_EXTRACT(p.checkout_config, '$.video_type')) AS video_type,
  JSON_UNQUOTE(JSON_EXTRACT(p.checkout_config, '$.video_source')) AS video_source,
  p.checkout_banner_url,
  p.data_atualizacao
FROM tbl_produtos AS p
WHERE NULLIF(TRIM(p.checkout_url_saida), '') IS NOT NULL
   OR NULLIF(TRIM(p.redirect_url_after_payment), '') IS NOT NULL
   OR JSON_UNQUOTE(JSON_EXTRACT(p.checkout_config, '$.video_type')) = 'iframe'
   OR JSON_UNQUOTE(JSON_EXTRACT(p.checkout_config, '$.video_source')) LIKE 'http://%'
   OR p.checkout_banner_url LIKE '%http://%'
ORDER BY p.data_atualizacao DESC, p.id_produto DESC;
```

No banco de homologação atual, essa consulta é compatível com o schema e retornou 2.175 produtos. O total representa registros com ao menos um dos campos selecionados; ele não classifica, por si só, um produto ou domínio como malicioso.

### Vendas associadas aos produtos classificados

```sql
SELECT
  s.sale_id,
  s.order_id,
  s.id_usuario AS seller_id,
  s.status,
  s.payment_method,
  s.sale_timestamp,
  si.id_produto,
  si.item_type,
  p.titulo
FROM sales AS s
INNER JOIN tbl_sale_items AS si ON si.sale_id = s.sale_id
INNER JOIN tbl_produtos AS p ON p.id_produto = si.id_produto
WHERE si.id_produto IN (/* IDs classificados no inventário */)
ORDER BY s.sale_timestamp DESC, s.sale_id DESC;
```

Essa consulta também é compatível com o schema atual. Executada com um produto classificado que possui venda associada, ela retornou resultado. O placeholder `IN (/* IDs classificados no inventário */)` deve ser substituído por IDs reais da primeira consulta.

As consultas são somente-leitura e não exigem dados de comprador no resultado. Elas permitem conhecer a exposição configurada e o volume de vendas relacionado a cada produto, sem afirmar que o redirect foi efetivamente seguido.

## Alternativas que dependem de decisão

| Tema | Situação atual | Efeito de manter como está | Alternativas possíveis |
| --- | --- | --- | --- |
| Redirects externos | seller informa URL do produto; browser navega diretamente | a Lowify continua sem vínculo entre destino e domínio aprovado | manter livre, limitar por domínio, ou resolver por rota interna; |
| Iframe | seller fornece HTML de embed | conteúdo de terceiro permanece dentro da página de pagamento | manter embed livre, restringir provedores, ou migrar para configuração estruturada; |
| Domínios | não há cadastro central de origem aprovada | não há comprovação de que o seller controla o destino | aprovação manual, verificação DNS/HTTPS, allowlist por seller/produto; |
| Registros legados | URLs e embeds existentes podem estar em uso | alteração brusca pode interromper funis | exceção temporária, migração gradual, remoção ou bloqueio administrativo; |
| CSP | não há política aplicada pelo código do Checkout | o navegador não dispõe dessa camada de restrição | nenhuma CSP, `Report-Only`, ou política efetiva após inventário; |
| Auditoria de navegação | não há evento de redirect concluído | não há prova de qual destino foi usado pelo comprador | registrar a resolução pelo backend ou manter ausência de trilha. |

## Escopo separado: Construtor de Páginas

O Construtor de Páginas é uma frente independente. O workspace contém integração externa de usuários, mas não contém o código, a configuração, os domínios ou o conteúdo publicado pelo construtor. Portanto, este relatório não classifica as páginas do construtor como seguras ou inseguras.

Uma avaliação desse produto envolve inventário próprio de domínios publicados, redirecionamentos, scripts, iframes, uploads, permissões de edição e vínculo entre a página e o domínio da Lowify.

## Referências

- [Revisão de reputação do Checkout](../../security/2026-11-12_CHECKOUT_REPUTATION_REVIEW.md)
- `front-checkout/views/checkout/_components/checkout_exit_redirect.php`
- `front-checkout/checkout_support/product.php`
- `front-checkout/functions.php`
- `dashboard-seller/api/save_checkout_settings.php`
- `service-commerce-v2/app/Http/Request/UpdateProductRequest.php`
- `service-commerce-v2/app/Application/UseCase/Product/GetCheckoutPaymentStatusUseCase.php`
- `front-checkout/api/check_payment_status.php`
