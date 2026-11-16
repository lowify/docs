# Planejamento — repasse da taxa de venda para o comprador

Status: proposta para implementação. Este documento complementa o plano e o deploy publicados da taxa de serviço; não altera vendas, assinaturas ou cobranças já criadas.

## Objetivo e regra de negócio

Todo seller continua sujeito à **taxa de venda**. Por padrão, ela continua sendo paga pelo seller, como hoje. Para um seller previamente habilitado, o editor de um **produto principal** passa a oferecer a escolha:

- **Seller absorve a taxa**: o comprador paga o preço comercial; a taxa integra `taxa_seller`.
- **Repassar taxa ao comprador**: o comprador vê e paga a taxa de serviço calculada para aquela compra; a parte que corresponde à taxa de venda deixa `taxa_seller` e é gravada em uma coluna própria de taxa de serviço.

A opção é do produto principal. Order bumps, ofertas e demais produtos vinculados não têm toggle próprio e não podem alterar o pagador da taxa da venda principal.

Checkout Transparent permanece fora deste fluxo, com taxa de serviço igual a zero, conforme a regra publicada anteriormente.

## Flags e persistência

### Habilitação por seller

Criar uma chave em `user_system_vars`, proposta como `service_fee_pass_through_enabled`, administrada no contexto da conta do seller. Valores permitidos: `0` e `1`; ausência deve ser tratada como `0`.

- O controle administrativo é a única forma de habilitar a capacidade do seller.
- Enquanto a chave estiver em `0`, o editor não mostra a opção e o backend sempre aplica o comportamento de seller absorvendo a taxa.
- A habilitação não altera produtos, carrinhos, PIX pendentes, vendas nem assinaturas preexistentes.

### Escolha por produto

Adicionar a `tbl_produtos` a coluna booleana proposta `service_fee_pass_through`, `TINYINT(1) NOT NULL DEFAULT 0`.

- `0`: seller absorve a taxa;
- `1`: comprador recebe a taxa no checkout, desde que o seller esteja habilitado e o produto seja principal elegível.

A migration/DDL deve ser aditiva. Produtos existentes, clones e novos produtos sem escolha explícita começam em `0`. O backend deve ignorar/tratar como `0` qualquer valor `1` em produto não principal, Checkout Transparent ou seller sem a chave habilitada; a validação de UI não é a fronteira de segurança.

## Contrato de cálculo

O Banking é a fonte das regras de taxa para o cenário em que o comprador paga. O contrato retornado deve transportar uma lista ordenada de componentes — fixos e/ou percentuais — e o Commerce deve devolver ao checkout a composição canônica e os metadados suficientes para a mesma simulação visual.

Contrato a fechar com Banking, em forma normalizada:

```json
{
  "service_fee_rules": [
    { "type": "fixed", "amount": "0.99" },
    { "type": "percentage", "rate": "2.50" }
  ]
}
```

Para uma base comercial `gross_amount`, o cálculo é:

```text
service_fee_amount = arredondar_em_centavos(
  soma(componentes fixos) + gross_amount × soma(percentuais) / 100
)
charged_amount = gross_amount + service_fee_amount
```

O JavaScript calcula apenas a prévia, sempre com o mesmo contrato e arredondamento do Commerce. No submit, o Commerce recalcula autoritativamente a partir do produto, seller, método/contexto e regras recebidas do Banking; nunca aceita `service_fee_amount`, `charged_amount` ou regras enviados pelo navegador como verdade. Divergência deve interromper a criação da cobrança com erro tratável e log seguro.

Quando o seller absorve a taxa, a composição obrigatória é `service_fee_amount = 0`, `charged_amount = gross_amount` e a taxa comercial calculada permanece em `taxa_seller`. Quando repassa, o Commerce deve separar explicitamente:

```text
taxa_seller        parcela da taxa de venda paga pelo seller
service_fee_amount parcela repassada e cobrada do comprador
```

Não é permitido duplicar a mesma parcela nas duas colunas. `charged_amount` segue sendo o valor enviado ao PSP; split, carteira, afiliado e relatórios devem conservar a semântica já publicada para cada coluna.

## Componentes e tarefas

| Componente | Trabalho necessário |
| --- | --- |
| `dashboard-seller` | Criar o controle administrativo da chave do seller, com autorização e auditoria no padrão das taxas existentes. No editor de produto, mostrar o toggle somente se a chave estiver ativa e o produto for principal; carregar, validar, salvar e retornar a coluna. Ao desabilitar a conta, ocultar o input sem apagar a escolha persistida. |
| `front-dashboard-seller` | Espelhar a alteração do editor e da gestão de conta se o fluxo/arquivo correspondente existir, conforme a regra de paridade do repositório. |
| `edge-public-api` e `edge-gateway` | Propagar o novo campo do produto e a composição de taxa sem recalcular; preservar autenticação JWT e impedir que um caller forje a habilitação do seller. |
| `services-commerce-v2` | Atualizar modelo/repositório/DTOs de produto e a validação de produto principal. Resolver a flag do seller, consultar Banking somente no contexto de repasse e expor a cotação. No checkout, recalcular, persistir snapshots e separar `taxa_seller` de `service_fee_amount`; cobrir PIX, cartão, recorrência, retries, pendência, recuperação, order bump e split. |
| `services-banking-v2` / serviço Banking responsável | Expor o array versionado de regras de taxa, com tipos, valores, escopo e validação; garantir que componentes fixos e percentuais possam coexistir. Definir também qual fonte/endpoint é usada pelo Commerce e o tratamento de indisponibilidade. |
| `front-checkout` | Usar apenas a cotação/array recebidos; recalcular a prévia em JS quando preço, desconto ou order bump mudar; mostrar linha de taxa e total somente no repasse. Não substituir a cotação no submit. |
| `services-commerce-v2` + `dashboard-seller` (reembolso) | Manter a regra: reembolso com taxa de serviço não devolve a taxa; sem taxa de serviço devolve o valor integral comercial. Centralizar a resolução da taxa de reembolso para evitar interface, endpoint e worker com valores diferentes. |
| `product_changes_log` | Confirmar e implementar o evento `entity_type=product`, `field_key=service_fee_pass_through`, com valor anterior e novo, ator e timestamp. O log deve ser enviado após a persistência bem-sucedida e não ser criado em gravação sem mudança. |

## Taxa de reembolso

A intenção recebida é que `refund_fee`, quando não estiver definido, herde o mesmo valor da taxa de serviço global. A implementação deve usar um resolvedor único nos endpoints, modal e workers:

1. `refund_fee` explicitamente positivo: usar esse valor;
2. `refund_fee` ausente/nulo: usar a taxa de serviço global efetiva;
3. configurar `refund_fee = 0`: manter o comportamento/valor de fallback acordado de `R$ 0,99`.

O item 3 é ambíguo em relação à semântica usual de zero como desabilitado. Antes de implementar, produto/financeiro precisa confirmar se o enunciado quer literalmente `0 => R$ 0,99`, ou se `0` deve desabilitar a taxa. O comportamento não deve ser inferido em código.

## Ordem segura de implementação

1. Fechar contrato Banking, regras de arredondamento e decisão sobre `refund_fee=0`.
2. Adicionar a coluna de produto com default `0`, atualizar modelos e leitores tolerantes a coluna ausente somente durante a janela de deploy.
3. Criar a chave administrativa do seller, com default efetivo `0`, auditoria e paridade entre dashboards.
4. Implementar edição de produto, validação server-side e log de alteração.
5. Publicar a cotação no Commerce/edges e a prévia no checkout atrás das duas flags (seller e produto), mantendo o submit autoritativo.
6. Persistir e usar a separação monetária em criação de venda, PSP, split, recorrência e recuperação; só então habilitar sellers de teste.
7. Ajustar refund e validar conciliação, carteira, afiliado, cash flow e logs antes de qualquer ativação ampla.

## Matriz de aceite

- Seller sem chave, com produto marcado indevidamente: toggle oculto e cobrança normal do seller.
- Seller habilitado, produto principal em `0`: sem taxa para comprador; `taxa_seller` preservada.
- Seller habilitado, produto principal em `1`: taxa fixa, percentual e combinação das duas são mostradas e o total enviado ao PSP fecha em centavos com o Commerce.
- Troca de oferta, desconto e inclusão/remoção de order bump atualizam a prévia; o submit não aceita valor adulterado no browser.
- Produto não principal, Checkout Transparent, venda administrativa e produto gratuito não aplicam repasse.
- PIX, cartão, split, afiliado, recorrência, retry, PIX pendente e RDC preservam snapshots e nunca contam a taxa duas vezes.
- Reembolso com `service_fee_amount > 0` não devolve essa parcela; sem taxa devolve o total comercial. Testar `refund_fee` explícito, ausente e zero após a decisão pendente.
- Alteração do toggle cria uma única entrada de histórico com antes/depois; salvar o mesmo valor não cria log.
- Desabilitar a chave do seller impede novas escolhas/repasse, sem alterar vendas ou cobranças já criadas.

## Decisões pendentes que bloqueiam código financeiro

1. Nome e contrato exatos do endpoint/resposta do Banking, incluindo se o percentual incide só sobre `gross_amount` e a regra de arredondamento por componente ou apenas no total.
2. O significado de `refund_fee = 0`: fallback de `R$ 0,99` (como solicitado) ou taxa zero.
3. A nova coluna `service_fee_pass_through` deve ser a fonte de verdade no produto, como proposto, e a chave `service_fee_pass_through_enabled` a permissão de conta; confirmar os nomes para não criar chaves duplicadas.
4. Em recorrência, a escolha e as regras de taxa ficam congeladas por assinatura, como os snapshots monetários já publicados, ou podem mudar em ciclos futuros.

## Referências confirmadas

- Plano e deploy publicados: [taxa de serviço](README.md) e [deploy de 06/11](../../deploys/2026-11-06-end-customer-service-fee/2026-11-06_END_CUSTOMER_SERVICE_FEE_DEPLOY.md).
- Produto principal: `services-commerce-v2/app/Domain/Product/Repository/ProductRepository.php::findActivePrimaryById`.
- Modelo de produto: `services-commerce-v2/app/Model/Product.php`.
- Cotação/processamento atual: `services-commerce-v2/app/Application/UseCase/Product/LoadCheckoutContextUseCase.php` e `ProcessProductCheckoutUseCase.php`.
- Log de produto: `services-commerce-v2/app/Application/UseCase/Product/CreateProductChangeLogUseCase.php` e `product_changes_log`.
- Resolução atual de reembolso: `services-commerce-v2/app/Application/UseCase/Sale/RequestSaleRefundUseCase.php::resolveRefundFee`.
