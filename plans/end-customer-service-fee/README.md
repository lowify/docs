# Plano — taxa de serviço cobrada do cliente final

Status: planejamento atualizado com decisões de produto; nenhuma implementação aprovada por este documento.

## 1. Objetivo

Adicionar uma taxa de serviço ao valor cobrado do cliente final, mantendo essa taxa integralmente na Lowify e sem aumentar o valor econômico atribuído ao seller.

Para uma venda faturável, a proposta parte das seguintes grandezas:

- `gross_amount`: valor dos produtos após descontos, incluindo order bumps aplicáveis, sem a taxa de serviço;
- `service_fee_amount`: taxa de serviço cobrada do cliente e retida pela Lowify;
- `charged_amount`: valor efetivamente enviado ao PSP, igual a `gross_amount + service_fee_amount`;
- `sale_amount`: mantém a semântica atual de valor usado na liquidação do seller e nunca incorpora `service_fee_amount`.

Exemplo conceitual:

```text
Produtos após descontos e order bumps       R$ 100,00
Taxa de serviço                             R$   2,00
Total cobrado do cliente                    R$ 102,00

Valor considerado para seller e afiliado    R$ 100,00
Receita da taxa de serviço da Lowify         R$   2,00
```

O plano considera checkout avulso, recorrência, split, estorno, disputa, relatórios e caminhos legados. O Checkout Transparent foi explicitamente excluído da cobrança da taxa de serviço. As decisões ainda indicadas como P0 precisam ser aprovadas antes da implementação.

Decisões já confirmadas:

- Checkout Transparent sempre usa taxa de serviço zero;
- o Commerce identifica o valor da taxa enquanto monta o contexto do checkout;
- a alteração de schema será entregue por SQL manual, sem migration executável da aplicação;
- o override por seller será administrado na tela **Visão geral do seller** do admin;
- os novos valores da venda serão exibidos no backoffice somente em `admin_sale_detail`, nunca em `sale_detail`;
- RDC e compra embutida na área de membros também exibirão valor dos produtos, taxa de serviço e total;
- em disputa, o valor informado pelo PSP pode ser o total cheio, mas o saldo do seller será bloqueado somente pelo valor ainda devolvível, sem a taxa de serviço.

## 2. Leitura do comportamento atual

### 2.1 Checkout canônico

O fluxo principal observado é:

```text
front-checkout
  -> edge-gateway
  -> edge-public-api
  -> services-commerce-v2
  -> services-banking-v2 ou services-checkout-transparent
```

O `services-commerce-v2` calcula produtos, ofertas, desconto de saída e order bumps. Hoje, o total resultante é enviado diretamente ao meio de pagamento. A interface recalcula o valor no navegador, mas o backend continua sendo a autoridade que deve determinar o valor cobrável.

No `front-checkout`, o resumo exibe hoje preço/total e, para Pix, o texto de valor à vista. O valor também alimenta parcelas de cartão. A nova taxa precisa participar de todas essas recomputações, inclusive após desconto de saída e inclusão ou remoção de order bump.

### 2.2 Semântica atual de `sales`

A tabela `sales` já possui, entre outras, as colunas:

- `gross_amount`;
- `fee_amount`;
- `sale_amount`;
- `order_bump_fee`;
- `taxa_seller`.

No fluxo canônico do Commerce V2, `gross_amount` já recebe o total comercial antes da liquidação, enquanto `fee_amount` representa uma taxa já existente da plataforma/seller. Portanto, `fee_amount` não deve ser reutilizada para a nova taxa cobrada do cliente.

`sale_amount` não é imutável: no evento de venda paga, parte dos fluxos deduz `order_bump_fee` e `taxa_seller`. O Checkout Transparent possui comportamento diferente, e caminhos legados também atualizam essa coluna. Logo, hoje ela não é uma fonte confiável para descobrir quanto foi originalmente enviado ao PSP.

Além disso, chamar `sale_amount` de “lucro do seller” seria impreciso em todos os cenários: com afiliado, split e outras deduções, existem cálculos posteriores. Neste plano, ela continua sendo um valor do domínio de liquidação do seller, excluindo sempre a nova taxa.

### 2.3 Configuração existente

Os nomes reais das tabelas de variáveis são `system_vars` e `user_system_vars`. Para esta feature, a decisão é não criar valor global em `system_vars`: o padrão virá da `.env` do Commerce, enquanto apenas o override por seller será persistido em `user_system_vars`.

### 2.4 Recorrência existente

Existem ao menos os seguintes fluxos recorrentes ativos no código atual:

- Pix Automático;
- cartão recorrente Cielo, incluindo split e processamento de ciclos posteriores.

O valor da assinatura é fixado na criação e reutilizado nas cobranças. Em ciclos posteriores, uma nova venda pode ser clonada a partir da venda original. Isso exige persistir a taxa e o total cobrado como snapshot; recalcular a `.env`/override vigente a cada webhook causaria divergência entre venda, assinatura e PSP.

### 2.5 Estorno existente

O estorno de cartão normalmente reconstrói o valor dos itens e não depende somente de `sale_amount`. Há diferenças específicas no caminho Cielo e na disponibilidade reportada pelo PSP. O débito da carteira do seller e a taxa de estorno são tratados separadamente.

Esse comportamento ajuda a manter a taxa de serviço fora do reembolso ao cliente, mas não garante isso sozinho: o valor disponível no PSP passará a ser maior, e void/refund de transações com split pode reverter a distribuição completa se não houver instrução explícita.

### 2.6 Flow financeiro atual

O relatório administrativo de cash flow considera vendas pagas, exclui Checkout Transparent do bloco padrão e deriva valores e taxas a partir de `sale_amount`, `order_bump_fee` e `taxa_seller`. O Checkout Transparent é contabilizado em bloco próprio a partir das cobranças de billing pagas.

O período do bloco padrão usa hoje o timestamp de criação da venda. Isso pode colocar a receita no período de criação, embora o pagamento seja confirmado em outro período. A nova taxa torna essa diferença contábil mais visível.

## 3. Contrato de dados proposto

### 3.1 Colunas

Recomendação para atender às duas novas informações sem duplicar o que `gross_amount` já deveria representar:

| Coluna | Semântica | Mutável? |
| --- | --- | --- |
| `gross_amount` | valor comercial dos produtos após descontos e com order bumps aplicáveis, sem a nova taxa | não, após criar a cobrança |
| `service_fee_amount` | snapshot da taxa de serviço cobrada do cliente | não |
| `charged_amount` | valor exato solicitado ao PSP | não |
| `sale_amount` | valor usado no fluxo atual de liquidação do seller, sem a taxa de serviço | pode continuar seguindo as transições atuais |

Assim, as duas novas colunas seriam `service_fee_amount` e `charged_amount`. O “valor original da cobrança” pedido é representado de forma inequívoca pelo valor enviado ao PSP, e `gross_amount` permanece como o valor dos produtos sem a taxa.

Não é recomendado criar uma nova coluna chamada apenas `original_amount`, pois ela entraria em conflito semântico com `gross_amount`: “original” poderia significar preço de catálogo, total pós-desconto, total antes de order bump ou valor enviado ao PSP.

Alternativa, se a decisão de produto for manter literalmente `original_amount`: documentar que ela é o valor enviado ao PSP e não criar `charged_amount`. Ainda assim, `charged_amount` é o nome preferido por reduzir ambiguidade em pagamentos, estornos e conciliação.

### 3.2 Invariantes

Para vendas novas:

```text
charged_amount = gross_amount + service_fee_amount
service_fee_amount >= 0
sale_amount nunca inclui service_fee_amount
valor enviado ao PSP = charged_amount
base de comissão do afiliado = gross_amount, sem service_fee_amount
base da taxa atual do seller = gross_amount, sem service_fee_amount
```

Nos fluxos em que `gross_amount` inclui componentes que depois são separados em `order_bump_fee`, a implementação deve preservar o comportamento financeiro atual; a nova taxa não pode alterar a decomposição existente.

### 3.3 Alteração manual de schema e histórico

A alteração deve ser aditiva e executada manualmente. Não será criada migration em `services-commerce-v2` nem em outro serviço. O pacote de deploy deve fornecer SQL manual, validação pré/pós-execução e rollback compatível com a estratégia de implantação.

Proposta segura em duas etapas:

1. executar manualmente `ALTER TABLE sales` para adicionar `service_fee_amount DECIMAL(12,2) NOT NULL DEFAULT 0` e `charged_amount DECIMAL(12,2) NULL`;
2. validar existência, tipo, default e nulabilidade das colunas antes de publicar código que as escreva;
3. para vendas criadas após a ativação, exigir `charged_amount` antes de criar a cobrança;
4. tratar vendas anteriores como taxa zero;
5. não reconstruir nem preencher `charged_amount` histórico; manter `NULL` nas vendas anteriores à ativação;
6. considerar `NOT NULL` somente em uma futura alteração manual, preservando explicitamente a exceção dos registros históricos.

O SQL não deve ser executado automaticamente no boot, deploy ou startup dos serviços. A ordem operacional é: validar banco, executar SQL manual, validar schema e somente então publicar leitores/escritores dos novos campos.

Não se deve aplicar a taxa retroativamente a uma venda pendente que já tenha uma cobrança criada. Uma cobrança pendente reutilizada deve continuar com o snapshot persistido, mesmo se a `.env` ou o override mudar.

## 4. Configuração proposta

O valor padrão será fixo em BRL e lido da `.env` do `services-commerce-v2`. Nome proposto:

```text
CHECKOUT_SERVICE_FEE_AMOUNT=0.99
```

Se a variável estiver ausente, vazia ou inválida, o fallback da aplicação será `0.99`. Todas as instâncias do Commerce precisam receber o mesmo valor; a alteração operacional da `.env` deve ser acompanhada de reload/redeploy conforme o mecanismo de configuração do serviço.

O override por seller permanece em `user_system_vars`, com a chave sugerida:

```text
checkout_service_fee_fixed
```

Regra de resolução:

1. Checkout Transparent: sempre `0,00`;
2. override válido do seller em `user_system_vars`, inclusive zero;
3. `CHECKOUT_SERVICE_FEE_AMOUNT` da `.env` do Commerce;
4. fallback interno `0,99`.

Valor efetivo igual a zero significa taxa desabilitada para aquela cobrança. Não haverá flag adicional.

O resolvedor deve devolver pelo menos:

- valor efetivo;
- origem: `transparent`, `user`, `env` ou `fallback`.

O valor efetivo é convertido em snapshot monetário na criação da cobrança. Webhooks, retries, recuperação de carrinho, renovação e reprocessamento não consultam novamente a configuração para aquela cobrança.

O override será incluído no modal de taxas da tela **Visão geral do seller** do `dashboard-seller` administrativo, junto das configurações já exibidas em `views/dashboard/admin/seller_overview/_components/fees_modal.php`. O endpoint administrativo de taxas deverá tratar a nova chave em `user_system_vars` com auditoria da alteração.

O controle precisa oferecer duas ações diferentes:

- definir um valor específico para o seller;
- definir zero para desabilitar a taxa naquele seller;
- remover o override e voltar a herdar a `.env`.

Somente salvar o mesmo valor da `.env` como override elimina a herança futura e deve ser evitado. Alterações da `.env` não possuem auditoria na aplicação; dependem da trilha operacional de configuração/deploy. Alterações de override continuam auditáveis no admin.

## 5. Regra de preço e apresentação no checkout

### 5.1 Identificação no contexto e autoridade de cálculo

O valor da taxa deve ser identificado no `services-commerce-v2` no momento em que o contexto do checkout é montado. O ponto canônico atual é `LoadCheckoutContextUseCase`, chamado por `ProductController::loadCheckout` antes de devolver produto, integrações e `checkout_options`.

O contexto deve devolver uma composição monetária explícita, por exemplo:

```json
{
  "gross_amount": "100.00",
  "service_fee_amount": "2.00",
  "charged_amount": "102.00"
}
```

O frontend pode recalcular para resposta visual imediata, mas o valor oculto enviado pelo navegador não pode ser aceito como fonte da taxa ou do total. No submit, o backend recalcula ou recupera a cotação persistida e valida a igualdade antes de chamar o PSP.

Regras do contexto:

- resolver primeiro o seller e o modo do checkout;
- se o modo for Checkout Transparent, devolver `service_fee_amount = 0` e `charged_amount = gross_amount`, sem consultar/aplicar override;
- nos demais modos elegíveis, resolver override do seller e depois `.env`/fallback;
- manter a origem da configuração em metadado interno para diagnóstico, sem permitir que o frontend escolha a taxa;
- reaplicar a mesma política no processamento da venda, pois o contexto não substitui a validação autoritativa no submit;
- em preview administrativo, mostrar exatamente a mesma taxa que seria aplicada a uma venda nova daquele seller e modo.

Como a primeira versão usa taxa fixa, o contexto já consegue informar o valor efetivo. Mudanças posteriores para percentual exigiriam nova cotação após desconto e order bumps.

### 5.2 Texto proposto

Quando `service_fee_amount > 0`:

Para Pix e Pix Automático:

```text
Valor dos produtos    R$ 100,00
Taxa de serviço       R$   2,00
Total à vista         R$ 102,00
```

Para cartão:

```text
Valor dos produtos    R$ 100,00
Taxa de serviço       R$   2,00
Total                 R$ 102,00
```

As parcelas são calculadas sobre `charged_amount`. Se o parcelamento incluir juros do adquirente ou outra regra futura, a taxa deve permanecer identificável e não ser confundida com juros.

Quando a taxa for zero, recomenda-se manter a apresentação compacta atual e ocultar a linha da taxa. O texto final deve ser validado com jurídico/produto para deixar claro que a taxa não é reembolsável, se essa for a política aprovada.

### 5.3 Eventos que exigem recomposição

- escolha de oferta;
- desconto do exit popup;
- inclusão ou remoção de order bump;
- troca de método de pagamento, caso a taxa venha a ser específica por método;
- reabertura de checkout pendente;
- upsell, downsell e cross-sell, quando criam uma nova cobrança.

### 5.4 RDC e área de membros

O detalhamento também deve ser mostrado nas superfícies de pagamento fora da página principal do checkout.

#### RDC

O RDC em `front-checkout/rdc.php` recupera uma venda pendente e um PIX já criado. Ele não deve resolver novamente `.env` ou override. `GetCartRecoveryUseCase` deve devolver os snapshots persistidos:

```json
{
  "gross_amount": "100.00",
  "service_fee_amount": "2.00",
  "charged_amount": "102.00"
}
```

A tela deve substituir o valor único atual pela composição:

```text
Valor dos produtos    R$ 100,00
Taxa de serviço       R$   2,00
Total à vista         R$ 102,00
```

O total exibido precisa ser o mesmo valor do PIX pendente. Alterações posteriores na `.env` ou no override não modificam o RDC existente. Para histórico sem snapshot completo, a API deve aplicar fallback compatível e nunca inventar uma taxa retroativa.

#### Compra na área de membros

A compra PIX embutida na área de membros, atendida por `front-member-area/api/member_purchase.php`, também deve exibir a composição antes de o membro gerar a cobrança. Os modais atualmente duplicados em `membros_view_standard_layout.php` e `membros_view_premium.php` precisam apresentar:

```text
Valor do produto      R$ 100,00
Taxa de serviço       R$   2,00
Total à vista         R$ 102,00
```

A área de membros não pode ler `.env`/`user_system_vars` nem calcular a taxa localmente. Ela deve obter a cotação do contexto produzido pelo Commerce. O processamento continua autoritativo e deve devolver a composição persistida para que o modal confirme o mesmo total do PIX.

Ao reutilizar um PIX pendente na área de membros, a resposta deve usar os snapshots daquela venda, assim como no RDC, sem recalcular a taxa atual. Links da loja da área de membros que apenas redirecionam ao checkout principal herdam a apresentação do checkout e não precisam de cálculo próprio.

## 6. Retenção da taxa por meio de pagamento

### 6.1 PSP com split

Somente aumentar o valor cobrado não garante retenção pela Lowify. O split precisa manter o seller e afiliado com os mesmos valores econômicos anteriores e atribuir a diferença à plataforma.

Para cada builder de split:

- a soma dos recebedores deve ser igual a `charged_amount`;
- seller e afiliado continuam calculados sobre `gross_amount`;
- `service_fee_amount` vai integralmente para a Lowify;
- a comissão do afiliado não incide sobre a taxa;
- retries usam o mesmo snapshot e a mesma composição.

No Cielo Split, a composição de recebedores e `Fares` precisa incorporar a taxa sem aumentar o líquido do subordinado. No Pagar.me, o recebedor da plataforma precisa absorver a taxa e a soma do split deve fechar com o novo total.

### 6.2 PSP sem split ou conta master

O PSP recebe `charged_amount`, mas a carteira do seller continua sendo creditada somente pelos componentes atuais de `gross_amount`. Não deve ser criado crédito seguido de débito da taxa na carteira do seller: a taxa não pertence ao seller em nenhum instante.

### 6.3 Checkout Transparent

Checkout Transparent não terá taxa de serviço. Essa é uma regra permanente do escopo atual, não apenas uma limitação de rollout.

Ao montar o contexto, o Commerce deve identificar `CheckoutMode::TRANSPARENT` e impor:

```text
service_fee_amount = 0
charged_amount = gross_amount
```

O backend de processamento deve repetir essa validação antes de criar a charge. Não basta ocultar a taxa no frontend, porque a `.env` ou o override do seller não pode vazar para esse modo.

As taxas próprias do Checkout Transparent — fixa, percentual e a regra chamada de mínima — continuam no billing atual contra o seller e não são alteradas por esta feature. Elas também não devem ser copiadas para `service_fee_amount`.

Uma venda do Checkout Transparent pode persistir `service_fee_amount = 0` e `charged_amount = gross_amount` para manter o contrato de dados uniforme, mas não deve gerar receita de taxa de serviço no cash flow.

## 7. Recorrência

Na criação da assinatura:

- calcular `gross_amount`, `service_fee_amount` e `charged_amount` uma vez;
- enviar `charged_amount` como valor recorrente ao PSP;
- persistir o snapshot na assinatura e na venda inicial;
- persistir a composição do split que retém a taxa.

Em cada ciclo:

- clonar os três valores para a nova venda;
- manter a liquidação do seller baseada em `gross_amount`;
- reter novamente `service_fee_amount` na Lowify;
- não recalcular `.env`/override em webhook, retry ou reprocessamento;
- garantir idempotência para não registrar a taxa duas vezes para a mesma cobrança do PSP.

Recomendação: alterações futuras de configuração afetam apenas novas assinaturas. Assinaturas existentes mantêm a taxa contratada durante toda a vida, pois o valor recorrente já foi informado ao cliente e ao PSP. Uma alteração de assinatura deve ser uma operação explícita, com nova comunicação/aceite quando necessário.

O Pix Automático deve agendar o valor cheio. Na Cielo recorrente, o split pós-transação de todos os ciclos deve carregar a retenção. Checkout Transparent recorrente mantém taxa de serviço zero em todos os ciclos.

## 8. Estorno, cancelamento e disputa

### 8.1 Regra para estorno normal

No estorno voluntário, o comprador recebe somente o valor ainda devolvível dos produtos; a taxa de serviço não faz parte do refund:

```text
reembolso integral do produto = gross_amount
service_fee_amount reembolsada = 0
valor total retido pela Lowify = service_fee_amount
```

O texto ao cliente, termos, comprovante e atendimento devem refletir que a taxa não é devolvida.

O fluxo deve:

- limitar o refund solicitado ao valor reembolsável dos itens, sem usar automaticamente toda a disponibilidade do PSP;
- registrar em `sales_refund.value` somente o valor efetivamente devolvido ao cliente;
- não debitar `service_fee_amount` da carteira do seller;
- preservar as taxas de estorno atuais, sem usar a nova taxa como substituta;
- garantir que void/refund com split reverta somente as parcelas correspondentes ao produto;
- manter a soma de estornos parciais limitada ao valor reembolsável do produto.

### 8.2 Disputa e chargeback

O valor recebido no evento do PSP é o valor cheio da transação. Esse valor deve ser preservado para auditoria, mas não pode ser usado diretamente como bloqueio do seller.

Separação obrigatória:

```text
disputes.payment_amount = charged_amount informado/confirmado pelo PSP
disputes.amount_seller_blocked = remaining_refundable_amount
remaining_refundable_amount = máximo(gross_amount - refunds_pending_or_approved, 0)
```

`remaining_refundable_amount` é o valor que ainda poderia ser devolvido ao cliente naquele instante, sem `service_fee_amount`. Estornos legados pendentes/aprovados e registros de `sales_refund` pendentes/aprovados devem participar da dedução para evitar bloqueio duplo.

Exemplo:

```text
gross_amount                         R$ 100,00
service_fee_amount                  R$   2,00
charged_amount / payment_amount     R$ 102,00
refund já pendente                  R$  20,00
amount_seller_blocked               R$  80,00
exposição da Lowify na taxa         R$   2,00
```

Mudanças necessárias no fluxo atual:

- centralizar o cálculo do valor ainda devolvível em um resolver compartilhado por refund e disputa;
- em `ProcessSaleDisputeEventUseCase`, persistir o total cheio em `payment_amount`, mas passar somente o devolvível para `buildBlockedAmounts`;
- ao perder uma disputa, `CreateDisputeLostExtractOperationUseCase` deve debitar do seller o snapshot de `amount_seller_blocked`, e não o total cheio recebido do PSP;
- atualizar os produtores legados de disputa que hoje usam `payment_amount` como `amount_seller_blocked`;
- garantir que toda disputa nova grave `amount_seller_blocked`, pois `services-wallet` ainda usa `payment_amount` como fallback para registros antigos;
- manter o fallback apenas para histórico e não para eventos criados depois da feature;
- não atribuir `service_fee_amount` ao bloqueio do seller nem do afiliado;
- quando o PSP retirar o total cheio em uma disputa perdida, a diferença correspondente à taxa de serviço é perda/exposição da Lowify;
- ao ganhar ou cancelar a disputa, o bloqueio desaparece pelo status atual sem gerar crédito extra da taxa ao seller;
- em evento repetido, reutilizar o snapshot já registrado e não aumentar o bloqueio com a configuração vigente.

Para venda com afiliado ou split, a soma bloqueada entre seller e afiliado nunca pode incluir a taxa de serviço. As regras atuais que dispensam bloqueio local quando o PSP já controla o split devem ser preservadas e testadas separadamente.

### 8.3 Outros casos que precisam de regra própria

- cancelamento antes da captura: alguns PSPs podem cancelar a transação inteira, impossibilitando reter a taxa;
- fraude confirmada;
- erro operacional da Lowify;
- estorno parcial e repetido;
- reembolso de apenas um order bump;
- assinatura cancelada depois de uma cobrança já paga.

Não se deve tratar cancelamento antes de captura ou erro operacional como se fosse o estorno voluntário normal sem confirmar o comportamento permitido pelo PSP.

## 9. Flow financeiro, conciliação e integrações

### 9.1 Relatório de cash flow

No bloco de vendas padrão, adicionar ao menos:

- `taxa_servico_cliente`;
- inclusão dessa taxa em `taxas_recebidas`;
- inclusão no lucro/resultado líquido da Lowify;
- manutenção do valor do seller sem a taxa.

Expor a composição, e não apenas aumentar um total, facilita conciliação e auditoria.

Checkout Transparent não reconhece receita de taxa de serviço, pois `service_fee_amount` é sempre zero. O billing próprio desse checkout permanece no bloco atual e não se mistura com a nova coluna.

Recomendação contábil para as vendas elegíveis: usar a data de confirmação/captura. Se o relatório precisar manter o timestamp de criação por compatibilidade, a coluna e o filtro devem deixar isso explícito.

Quando uma disputa for perdida e o PSP retirar também a taxa, o flow deve registrar a reversão/perda da taxa como efeito da Lowify, sem transferi-la ao seller. Uma disputa pendente representa exposição/bloqueio, não receita adicional nem reversão definitiva.

### 9.2 Conciliação

Adicionar validações automáticas:

```text
valor solicitado ao PSP = sales.charged_amount
gross_amount + service_fee_amount = charged_amount
soma do split = charged_amount
seller/afiliado não receberam service_fee_amount
taxa reconhecida uma única vez no flow financeiro
```

### 9.3 Contratos externos

Webhooks, UTMify, pixels, LowTrack, Husky e demais integrações hoje podem consumir `sale_amount`, itens ou total. A recomendação é manter receita de produto/comissão baseada em `gross_amount` e não inflar métricas do seller com a taxa.

Os campos `service_fee_amount` e `charged_amount` serão apenas internos no primeiro release. Não serão adicionados a APIs públicas, webhooks ou payloads das integrações.

A gestão ainda precisa decidir se o campo monetário já existente em cada integração mantém o valor atual dos produtos ou passa a representar o total pago pelo cliente. Até essa decisão, não alterar silenciosamente o significado de `amount`, `sale_amount`, `value` ou `total` e não publicar a composição abaixo externamente:

```json
{
  "gross_amount": "100.00",
  "service_fee_amount": "2.00",
  "charged_amount": "102.00"
}
```

Se a gestão optar futuramente por expor a composição, isso exige contrato versionado e campos opcionais explícitos.

### 9.4 Visibilidade no detalhe da venda

Dentro do backoffice do `dashboard-seller`, os valores novos serão exibidos somente em `dashboard-seller/admin_sale_detail.php`, no componente administrativo de pagamento. Essa restrição não se aplica às superfícies do comprador: checkout, RDC e compra na área de membros precisam mostrar a composição antes do pagamento. O detalhe administrativo deve mostrar:

- valor dos produtos (`gross_amount`);
- taxa de serviço (`service_fee_amount`), inclusive zero quando útil para diagnóstico;
- total cobrado (`charged_amount`).

`dashboard-seller/sale_detail.php`, acessível no contexto do seller, não deve exibir `service_fee_amount` nem `charged_amount`. Essa restrição é de interface do seller: APIs internas, superfícies do comprador e o banco ainda carregam os campos necessários para processamento, exibição, disputa, relatório e auditoria.

O detalhe administrativo deve diferenciar a nova taxa das atuais `taxa_seller`, `order_bump_fee` e `fee_amount`, sem reutilizar o rótulo genérico “Taxa”. Para histórico com `charged_amount IS NULL`, mostrar “N/A” em vez de reconstruir silenciosamente um valor.

## 10. Impactos por componente

| Componente | Alteração principal |
| --- | --- |
| `services-commerce-v2` | modelo de `sales`, resolução no contexto, cotação autoritativa, persistência do snapshot, disputa e invariantes de venda paga; sem migration automática |
| `front-checkout` | resumo com produtos/taxa/total e parcelas sobre o total; RDC com snapshots da venda pendente |
| `front-member-area` | cotação vinda do Commerce e composição nos modais de compra PIX standard/premium, inclusive ao reutilizar pendência |
| `edge-gateway` | transportar os novos campos sem recalcular valores |
| `edge-public-api` | contrato de checkout, orquestração e validação do valor enviado aos destinos |
| `services-banking-v2` | valor cobrado, builders de split, recorrência, refund/void e conciliação por PSP |
| `services-banking` | Pix Automático ou outros caminhos ainda atendidos pelo serviço legado |
| `services-checkout-transparent` | nenhuma cobrança nova; manter billing atual e validar que o Commerce sempre envia taxa de serviço zero |
| `services-commerce` | clonagem/processamento recorrente e produtores legados de venda ainda ativos |
| `services-wallet` | bloquear/debitar em disputa somente `amount_seller_blocked`, garantir que a taxa nunca gera crédito nem débito do seller |
| `dashboard-seller` | override na Visão geral do seller, composição apenas em `admin_sale_detail`, cash flow, produtores legados de disputa e correção/bloqueio dos checkouts legados |
| integrações de venda | manter métricas do seller sem taxa; expor novos campos apenas de forma compatível |

Há páginas legadas de checkout e processamento dentro do `dashboard-seller`, além do checkout principal. Antes do rollout, cada produtor de cobrança deve ser classificado como: migrado para a cotação canônica, adaptado com o mesmo contrato ou explicitamente bloqueado para sellers com taxa ativa. Deixar um bypass ativo permitiria cobranças sem taxa e registros incompletos.

## 11. Pontos em aberto

### Decisões fechadas nesta revisão

- Checkout Transparent fica fora da taxa e sempre recebe zero no contexto e no processamento;
- schema aplicado por SQL manual;
- resolução da taxa feita pelo Commerce ao montar o contexto;
- override editável na Visão geral do seller pelo admin, usando a permissão administrativa já aplicada à edição de taxas;
- composição monetária visível em `admin_sale_detail`, mas não em `sale_detail`;
- composição monetária também visível no RDC e na compra PIX embutida da área de membros;
- taxa fixa igual para Pix, Pix Automático e cartão;
- valor zero desabilita a taxa; não haverá flag separada;
- configuração padrão pela `.env` do Commerce, com fallback `0,99`, e override por seller em `user_system_vars`;
- aplicação somente em novas cobranças; cobranças já criadas nunca recebem taxa retroativa;
- produto gratuito, matrícula manual e venda administrativa permanecem sem taxa;
- os novos campos monetários são internos no primeiro release;
- vendas anteriores à ativação usam taxa zero; `charged_amount` permanece `NULL` quando o valor original não puder ser comprovado, sem reconstrução estimada;
- disputa registra o valor cheio do PSP, porém bloqueia/debita do seller somente o valor ainda devolvível, excluindo a taxa.

### P0 — bloqueiam desenho ou implementação

1. **Nome e semântica das colunas.** Aprovar `service_fee_amount` + `charged_amount`, reaproveitando `gross_amount` como base imutável, ou exigir `original_amount` com uma definição formal.
2. **Exceções de devolução.** A regra normal e de disputa exclui a taxa do seller; ainda é preciso definir cancelamento antes de captura, fraude e erro operacional da Lowify.
3. **Recorrências existentes.** Aprovar snapshot imutável por assinatura e decidir se assinaturas criadas antes do rollout continuam com taxa zero.
4. **Cobertura restante.** Área de membros e RDC já estão incluídos. Confirmar se “toda venda elegível” também inclui upsell, downsell, cross-sell e boleto legado. Checkout Transparent já está excluído.
5. **Split e recebedor Lowify.** Confirmar a conta/recipient de destino por PSP e o comportamento esperado quando split/void não permite retenção parcial.
6. **Reconhecimento no cash flow.** Confirmar regime/data de reconhecimento das vendas elegíveis e da perda da taxa em disputa perdida.

### P1 — decisões fechadas

1. Valor zero significa desabilitado.
2. A mesma taxa fixa é aplicada em Pix, Pix Automático e cartão.
3. Produto gratuito, matrícula manual e venda administrativa não recebem taxa.
4. A taxa vale somente para novas cobranças. Venda/PIX/charge já criada mantém o snapshot anterior, mesmo se estiver pendente.
5. Não haverá limite máximo específico nem bloqueio quando a taxa for maior que o produto; ainda se aplicam validação monetária não negativa e limites técnicos do PSP.
6. Não há hoje tratamento/comprovante fiscal específico para separar essa taxa; o primeiro release não cria um fluxo fiscal novo, sujeito à validação jurídica da gestão.
7. O padrão é editado diretamente na `.env` do Commerce, com fallback `0,99`; o override continua na Visão geral do seller.
8. `service_fee_amount` e `charged_amount` são apenas internos no primeiro release.

### P1 — encaminhamento jurídico para gestão

#### Comunicação, termos e reembolso

O trabalho é atualizar os Termos de Uso e a documentação jurídica relacionada à cobrança e ao reembolso da taxa de serviço. A revisão deve definir formalmente:

1. nome apresentado ao comprador: “Taxa de serviço”, “Taxa de serviço Lowify” ou outro;
2. texto que explica o serviço remunerado pela taxa;
3. comunicação de que a taxa não é reembolsável no estorno voluntário;
4. exceções para cancelamento antes de captura, fraude, erro da Lowify e determinação legal;
5. locais obrigatórios da informação: checkout, RDC, área de membros, página de sucesso, e-mail e recibo/comprovante;
6. necessidade de aceite específico ou atualização dos termos de uso/política de reembolso;
7. identificação de quem presta e recebe a taxa perante o cliente;
8. orientação ao suporte para reclamação ou solicitação de devolução.

O valor configurável não deve ser fixado como `R$ 0,99` nos Termos de Uso. O documento deve estabelecer a regra e informar que o valor efetivo será discriminado antes da confirmação de cada compra. A interface apresenta o valor monetário vigente.

Encaminhamento sugerido para gestão/jurídico:

> Qual deve ser o texto oficial da taxa de serviço e da política de não devolução, em quais pontos da jornada ele deve aparecer e quais exceções obrigam a Lowify a devolver a taxa?

### P1 — histórico anterior à feature: decisão fechada

Vendas antigas não possuem snapshot da taxa nem um `charged_amount` confiável, porque `sale_amount` muda de semântica durante o ciclo. Foi decidido:

- considerar `service_fee_amount = 0` para vendas anteriores à data de ativação;
- manter `charged_amount = NULL` quando não houver fonte confiável;
- exibir “N/A” no `admin_sale_detail` para o total cobrado histórico desconhecido;
- não executar backfill estimado nem alterar relatórios históricos.

### P2 — evolução posterior

- taxa por método de pagamento;
- taxa percentual/híbrida com mínimo e máximo;
- alteração consentida do valor de assinaturas existentes;
- dashboards de margem e conciliação por PSP;
- política configurável de devolução da taxa por motivo de estorno.

## 12. Sequência de implementação proposta

### Fase 0 — decisões e contratos

- aprovar todos os P0;
- fechar glossário monetário e exemplos por método;
- aprovar e publicar a atualização dos Termos de Uso, da política de reembolso e dos textos apresentados ao comprador;
- definir política jurídica de estorno e suas exceções;
- inventariar todos os produtores de venda/cobrança;
- registrar contratos de API e eventos antes de alterar consumidores.

### Fase 1 — fundação sem cobrança

- preparar, revisar e executar manualmente o SQL aditivo; não criar migration da aplicação;
- validar o schema antes do deploy dos escritores e atualizar os modelos;
- implementar resolvedor `.env`/override/fallback com origem e validação;
- propagar campos com taxa zero;
- adicionar invariantes, logs e métricas de divergência;
- manter histórico anterior com taxa zero e `charged_amount = NULL`, sem backfill estimado.

### Fase 2 — contexto, cotação e UI atrás de flag

- Commerce resolve a taxa em `LoadCheckoutContextUseCase` e devolve a composição no contexto;
- modo transparente recebe taxa zero no contexto e na validação do submit;
- Commerce recalcula e persiste a cotação autoritativa no processamento;
- checkout exibe produtos, taxa e total;
- RDC recebe os snapshots persistidos e exibe produtos, taxa e total do PIX pendente;
- área de membros consulta a cotação do Commerce e atualiza os modais standard/premium antes de gerar o PIX;
- card/Pix/Pix Automático usam `charged_amount`;
- pendência e recuperação reutilizam snapshot;
- ativar apenas para sellers internos de teste.

### Fase 3 — liquidação, split, estorno e disputa

- adaptar builders Cielo e Pagar.me;
- validar carteira do seller e comissão de afiliado inalteradas;
- adaptar refund/void parcial e integral;
- separar `payment_amount` cheio de `amount_seller_blocked` devolvível em todos os produtores de disputa;
- usar o valor bloqueável no débito de disputa perdida e validar os fallbacks da wallet;
- homologar cada PSP com conciliação de centavos.

### Fase 4 — recorrência e exclusão do Checkout Transparent

- snapshot na assinatura e em todos os ciclos;
- split recorrente e idempotência;
- testar que Checkout Transparent avulso e recorrente sempre usa taxa zero e mantém seu billing atual;
- testar cancelamento, falha, retry e webhook duplicado.

### Fase 5 — relatório, administração e rollout

- editar override na Visão geral do seller com opção de herdar a `.env`;
- mostrar composição somente em `admin_sale_detail` e garantir ausência em `sale_detail`;
- incluir taxa no cash flow sem dupla contagem;
- ativar gradualmente por seller;
- monitorar cobrança, split, refund e conciliação antes do rollout geral.

## 13. Matriz mínima de testes

### Preço e persistência

- SQL manual validado antes do deploy e nenhuma migration automática criada;
- taxa da `.env`, fallback `0,99`, override, override zero e retorno à herança;
- contexto padrão com taxa resolvida no Commerce;
- contexto Checkout Transparent sempre com taxa zero, mesmo com `.env`/override positivos;
- Pix/cartão com e sem order bump;
- desconto de saída antes da taxa;
- taxa zero sem mudança visual;
- duas submissões idempotentes;
- pendência criada antes e depois de mudança de configuração;
- falha de leitura da configuração sem valor incorreto no PSP.

### Liquidação

- seller sem afiliado;
- seller com afiliado;
- Cielo Split e Pagar.me Split;
- conta master sem split;
- soma de recebedores igual ao total cobrado;
- wallet do seller idêntica ao cenário sem taxa.

### Recorrência

- primeira cobrança e ciclo seguinte em Pix Automático;
- primeira cobrança e ciclo seguinte em Cielo;
- retry e webhook duplicado;
- mudança de `.env`/override depois de criar a assinatura;
- cancelamento antes e depois da cobrança;
- recorrência com afiliado e split.

### Estorno e disputa

- integral do produto mantendo taxa;
- parcial e múltiplos parciais;
- somente order bump;
- saldo insuficiente do seller;
- void antes da captura;
- disputa recebe `payment_amount` cheio e bloqueia somente o restante devolvível;
- disputa depois de refund parcial ou pendente sem bloqueio duplo;
- disputa perdida debita do seller somente `amount_seller_blocked` e atribui a perda da taxa à Lowify;
- disputa ganha/cancelada libera o bloqueio sem crédito da taxa ao seller;
- evento de disputa duplicado não recalcula nem aumenta o bloqueio;
- refund em cada PSP com e sem split;
- relatório sem estornar a receita quando a política mandar reter.

### Compatibilidade

- Checkout Transparent avulso e recorrente sempre sem taxa de serviço;
- upsell/downsell/cross-sell;
- área de membros;
- carrinho recuperado;
- checkout legado;
- RDC exibe o snapshot sem recalcular taxa depois de mudança de `.env`/override;
- modais standard e premium da área de membros exibem a cotação antes de gerar o PIX;
- reutilização de PIX pendente na área de membros mantém o snapshot original;
- override criado e removido na Visão geral do seller do admin;
- composição visível em `admin_sale_detail` e ausente em `sale_detail`;
- webhooks e integrações sem aumento indevido da receita do seller.

## 14. Critérios de aceite

1. O cliente vê a taxa e o total antes de confirmar o pagamento.
2. O valor enviado ao PSP é exatamente `charged_amount` persistido.
3. `sale_amount`, carteira, comissão e métricas do seller não incluem a taxa.
4. A Lowify recebe integralmente a taxa no split das vendas elegíveis; Checkout Transparent sempre persiste taxa zero e mantém seu billing atual isolado.
5. Toda renovação cobra e retém o snapshot correto uma única vez.
6. Estornos respeitam a política aprovada e nunca usam por engano o total disponível do PSP.
7. O cash flow mostra a taxa separadamente e sem dupla contagem.
8. Vendas antigas e cobranças pendentes não recebem taxa retroativa.
9. Nenhum produtor de cobrança ativo consegue contornar o contrato monetário.
10. Divergências entre venda, PSP, split e relatório são detectáveis por logs/métricas e consultas de conciliação.
11. O contexto do Commerce identifica a taxa antes da renderização e o submit confirma a mesma política de forma autoritativa.
12. Em disputa, o valor cheio do PSP fica auditável, mas seller/afiliado nunca são bloqueados ou debitados pela taxa de serviço.
13. O override é gerenciado na Visão geral do seller; dentro do backoffice, os valores aparecem somente no detalhe administrativo, enquanto checkout, RDC e área de membros mostram a composição ao comprador.
14. O schema é alterado por procedimento manual validado e nenhuma migration da aplicação é adicionada.
15. RDC e área de membros exibem exatamente o `gross_amount`, `service_fee_amount` e `charged_amount` devolvidos ou persistidos pelo Commerce, sem cálculo local da taxa.
16. Termos de Uso, política de reembolso e textos da jornada estão aprovados e publicados antes da ativação da cobrança.
17. Vendas anteriores à ativação permanecem com taxa zero e `charged_amount = NULL`, exibindo “N/A” quando aplicável, sem backfill estimado.

## 15. Recomendação para aprovação inicial

Para reduzir ambiguidade e risco, recomenda-se aprovar o primeiro release com:

- taxa fixa em BRL;
- `service_fee_amount` + `charged_amount`;
- padrão na `.env` com fallback `0,99`, override por seller e zero como desabilitado;
- snapshot imutável por cobrança e por assinatura;
- comissão, taxas atuais e wallet calculadas sem a nova taxa;
- reembolso voluntário limitado ao produto, com taxa retida e comunicação explícita;
- disputa com `payment_amount` cheio e `amount_seller_blocked` limitado ao valor ainda devolvível;
- rollout gradual;
- Checkout Transparent permanentemente sem taxa de serviço neste escopo;
- SQL manual para alteração de `sales`;
- override no admin da Visão geral do seller e composição restrita a `admin_sale_detail` dentro do backoffice;
- composição também visível ao comprador no RDC e na compra PIX embutida da área de membros.

Essa definição entrega o comportamento central sem misturar a nova taxa com `fee_amount`, sem depender do `sale_amount` mutável e sem alterar silenciosamente a economia do seller.

## 16. Referências representativas da análise

Esta análise foi baseada no código atual do workspace, especialmente em:

- `front-checkout/views/checkout/form/_components/order_summary.php`;
- `front-checkout/views/checkout/form/_components/pricing_script.php`;
- `front-checkout/rdc.php`;
- `front-member-area/api/member_purchase.php`;
- `front-member-area/membros_view_standard_layout.php`;
- `front-member-area/membros_view_premium.php`;
- `services-commerce-v2/migrations/20260302111000_create_sales_table.php`;
- `services-commerce-v2/app/Application/UseCase/Product/LoadCheckoutContextUseCase.php`;
- `services-commerce-v2/app/Application/UseCase/Product/GetCartRecoveryUseCase.php`;
- `services-commerce-v2/app/Application/UseCase/Product/ProcessProductCheckoutUseCase.php`;
- `services-commerce-v2/app/Application/UseCase/Sale/CreateSaleUseCase.php`;
- `services-commerce-v2/app/Application/UseCase/Sale/ProcessPaidSaleEventActivationUseCase.php`;
- `services-commerce-v2/app/Application/UseCase/Sale/ProcessPaidSaleEventTransferUseCase.php`;
- `services-commerce-v2/app/Application/UseCase/Sale/RequestSaleRefundUseCase.php`;
- `services-commerce-v2/app/Application/UseCase/Dispute/ProcessSaleDisputeEventUseCase.php`;
- `services-commerce-v2/app/Application/UseCase/Dispute/CreateDisputeLostExtractOperationUseCase.php`;
- `services-commerce-v2/app/Application/UseCase/Subscription/ProcessSubscriptionChargePaidUseCase.php`;
- `services-banking-v2/app/Application/Service/CieloEcommerce/CieloSplitPaymentBuilder.php`;
- `services-banking-v2/app/Application/Service/PagarmePsp/PagarmePspSplitPaymentBuilder.php`;
- `services-checkout-transparent/services-checkout-transparent-api/app/Model/ChargeFeeRule.php`;
- `services-checkout-transparent/services-checkout-transparent-billing/app/Model/BillingItem.php`;
- `services-wallet/app/Domain/Extract/Repository/ExtractAvailabilityRepository.php`;
- `dashboard-seller/admin_sale_detail.php`;
- `dashboard-seller/sale_detail.php`;
- `dashboard-seller/api/admin/cashflow_report/step.php`;
- `dashboard-seller/views/dashboard/admin/seller_overview/_components/fees_modal.php`;
- `dashboard-seller/actions/admin/user/fees.php`;
- `dashboard-seller/webhooks/woovi/cash-in-med.php`;
- `dashboard-seller/app/services/WooviCashInMedService.php`.

Os caminhos são referências para o planejamento, não uma lista exaustiva de arquivos a modificar. Antes da implementação, o inventário da Fase 0 deve confirmar todos os produtores e consumidores ainda ativos.
