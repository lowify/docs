# Deploy — taxa de serviço do cliente e rateio de reembolso

## Objetivo

Publicar a taxa de serviço cobrada do comprador sem incorporá-la à receita do seller ou do afiliado. A entrega também corrige o rateio de reembolsos de vendas liquidadas na carteira Lowify e preserva a reversão pelo gateway em vendas de cartão com split.

A taxa inicia desativada. Ela só deve ser ativada depois da validação por meio da configuração global do Admin ou por override explícito de seller.

## Componentes e referências

| Repositório | Branch de deploy | Commit mínimo | Papel |
| --- | --- | --- | --- |
| `services-commerce-v2` | `feat/end-customer-service-fee` | `ab866fc` | Calcula, persiste e cobra a taxa; controla reembolso, rateio, disputa, split e recuperação de pagamento. |
| `front-checkout` | `feat/end-customer-service-fee` | `cecfc86` | Exibe a composição no checkout, RDC e upsell; calcula parcelas sobre o total cobrado. |
| `front-member-area` | `feat/end-customer-service-fee` | `f152c24` | Obtém a cotação canônica e apresenta a taxa na compra Pix da Área de Membros. |
| `dashboard-seller` | `feat/end-customer-service-fee` | `e5c9dd08` | Configura taxa global e override por seller; exibe valores no detalhe administrativo e no cashflow. |

Os quatro commits/branches precisam estar publicados em `origin` antes do início desta operação. Este roteiro não publica branches.

## Alterações incluídas

### Composição de cobrança

Para vendas novas, o Commerce persiste os snapshots abaixo:

```text
gross_amount        valor dos produtos, descontos e order bumps
service_fee_amount  taxa de serviço do comprador
charged_amount      gross_amount + service_fee_amount; valor enviado ao PSP
```

- `sale_amount`, seller e afiliado continuam baseados no valor comercial, sem a taxa.
- Checkout Transparent sempre recebe taxa zero.
- Pix, cartão, upsell, RDC, pagamento pendente e confirmação de pagamento usam os snapshots persistidos.
- Cartão calcula parcelas sobre `charged_amount`.
- Para split, a taxa é retida pela plataforma sem alterar o valor econômico de seller e afiliado.

### Configuração da taxa

Ordem de resolução:

1. Checkout Transparent: `R$ 0,00`;
2. override do seller em `user_system_vars.checkout_service_fee_fixed`;
3. configuração global em `system_vars.checkout_service_fee_default`;
4. variável `CHECKOUT_SERVICE_FEE_AMOUNT`;
5. fallback interno `R$ 0,00`.

O Admin pode alterar o valor global em **Configurações → Pagamentos → Checkout / Cash-in → Taxa de serviço padrão do checkout**. O valor `R$ 0,00` desativa a taxa global. O override por seller continua prevalecendo e também aceita zero.

### Reembolso, carteira e disputa

- O padrão é não devolver a taxa de serviço: `REFUND_SERVICE_FEE_ON_EXCEPTION=false`.
- Apenas com `REFUND_SERVICE_FEE_ON_EXCEPTION=true`, os motivos `legal_withdrawal` e `lowify_failure` podem devolver o total cobrado, incluindo a taxa. Reembolso voluntário nunca inclui a taxa.
- Independentemente da flag, seller e afiliado respondem somente pela parcela comercial (`gross_amount`) ainda não reembolsada.
- Em reembolso de carteira, a comissão liberada do afiliado é debitada proporcionalmente e o restante é debitado do seller. Os lançamentos usam `banking_refund_id` para idempotência.
- Em cartão Cielo/Pagar.me e em `gateway_split`, não há consulta nem lançamento na carteira Lowify: o gateway é responsável pela reversão do split.
- A disputa registra o valor cheio contestado no PSP, mas bloqueia localmente somente o valor comercial ainda exposto ao seller; a taxa não entra no bloqueio.

### Alterações já incorporadas da `main`

- Cielo 3DS pode ser exigido a partir de `system_vars.cielo_3ds_minimum_amount`; a comparação usa o total efetivamente cobrado.
- Reembolsos externos confirmados pela Cielo passam por fila confiável, refletem `sales_refund` e têm deduplicação por `banking_refund_id`.
- Recuperação de venda passa a exigir código Pix apenas para Pix/Pix Automático e libera crédito/saldo reservado quando um envio é ignorado.

## Pré-requisitos

1. Confirmar que as quatro branches e seus commits mínimos estão publicados em `origin`.
2. Registrar os commits atualmente ativos de cada componente para rollback.
3. Garantir acesso administrativo ao banco `lowify` e ao Admin para configurar a taxa global após a publicação.
4. Configurar no Commerce, antes do restart:

```env
CHECKOUT_SERVICE_FEE_AMOUNT=0.00
REFUND_SERVICE_FEE_ON_EXCEPTION=false
```

Não omitir `CHECKOUT_SERVICE_FEE_AMOUNT`: embora o fallback interno atual seja zero, o valor explícito evita ativação inesperada por configuração antiga do ambiente.

5. Confirmar que Redis e os consumidores de extrato de `services-wallet` estão saudáveis. Não limpar filas, chaves Redis ou extratos.

## Banco de dados

### Colunas de vendas

Antes de atualizar qualquer front que consulte os novos valores, executar o pré-check no banco `lowify`:

```sql
SELECT column_name, column_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'sales'
  AND column_name IN ('service_fee_amount', 'charged_amount')
ORDER BY FIELD(column_name, 'service_fee_amount', 'charged_amount');
```

Se não houver linhas, executar uma única vez:

```sql
ALTER TABLE sales
    ADD COLUMN service_fee_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00 AFTER gross_amount,
    ADD COLUMN charged_amount DECIMAL(12,2) NULL AFTER service_fee_amount;
```

Se as colunas já existirem com os tipos acima, não executar DDL novamente. Vendas históricas permanecem com `service_fee_amount = 0.00` e `charged_amount = NULL`; não fazer backfill.

### Idempotência de reembolso

A branch também contém a migration `20261029190000_add_sales_refund_banking_refund_unique_index.php`, já incorporada da `main`. Confirmar que o mecanismo normal de migrations do Commerce foi executado ou que o índice correspondente já existe antes de habilitar reembolsos. Não criar um índice manual sem validar o estado atual e possíveis duplicidades.

## Sequência de deploy

### 1. Schema e configuração segura

1. Executar e validar o pré-check de `sales`.
2. Aplicar o DDL somente se ele for necessário.
3. Definir as duas variáveis do Commerce conforme os pré-requisitos, mantendo taxa e devolução de taxa desativadas.

### 2. Commerce V2

```bash
cd /opt/lowify/services/service-commerce-v2
git status --short
git fetch origin --prune
git switch feat/end-customer-service-fee
git pull --ff-only origin feat/end-customer-service-fee
git rev-parse --short HEAD
docker compose up -d --build service-commerce-v2
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

Confirmar que o commit é `ab866fc` ou descendente aprovado e que o serviço iniciou sem erro de banco, Redis, fila ou injeção de dependências.

### 3. Front Checkout

```bash
cd /opt/lowify/front/front-checkout
git status --short
git fetch origin --prune
git switch feat/end-customer-service-fee
git pull --ff-only origin feat/end-customer-service-fee
git rev-parse --short HEAD
```

Confirmar o commit `cecfc86` ou descendente aprovado.

### 4. Área de Membros

Executar somente após o schema e Commerce estarem atualizados:

```bash
cd /opt/lowify/front/front-member-area
git status --short
git fetch origin --prune
git switch feat/end-customer-service-fee
git pull --ff-only origin feat/end-customer-service-fee
git rev-parse --short HEAD
```

Confirmar o commit `f152c24` ou descendente aprovado.

### 5. Dashboard Seller

```bash
cd /opt/lowify/front/dashboard-seller
git status --short
git fetch origin --prune
git switch feat/end-customer-service-fee
git pull --ff-only origin feat/end-customer-service-fee
git rev-parse --short HEAD
```

Confirmar o commit `e5c9dd08` ou descendente aprovado. Se o ambiente executar o Dashboard em imagem em vez de bind mount, reconstruir o serviço conforme o procedimento local aprovado.

### 6. Ativação gradual

1. Acessar **Configurações → Pagamentos → Checkout / Cash-in** como administrador.
2. Confirmar que **Taxa de serviço padrão do checkout** está em `R$ 0,00`.
3. Para piloto, configurar um override em um seller específico pelo modal de taxas, sem editar `user_system_vars` diretamente.
4. Validar os cenários abaixo.
5. Somente após aceite técnico, financeiro, jurídico e operacional, definir o valor global aprovado na tela de configurações. Para interromper novas cobranças, retornar esse valor para `R$ 0,00`.

## Validação pós-deploy

1. No Admin, abra as configurações de pagamento, defina temporariamente `R$ 0,00` e salve. Reabra a tela e confirme que o valor persistiu.
2. Crie uma venda Pix de teste para seller sem override. Confirme que o comprador vê somente o valor dos produtos e que o total cobrado é igual a ele.
3. Defina um override piloto maior que zero no seller. Crie uma nova venda Pix e uma nova venda de cartão. Confirme que a interface mostra taxa e total, e que o valor do Pix/parcelas corresponde ao total cobrado.
4. Abra o detalhe administrativo da venda e confirme produtos, taxa do cliente e total. O detalhe no contexto do seller não deve exibir essa taxa.
5. Abra o RDC de uma venda pendente e a compra Pix da Área de Membros. Confirme que ambos mostram o mesmo total registrado na venda, sem recotar um Pix pendente.
6. Para uma venda de carteira com afiliado e comissão liberada, solicite reembolso total em ambiente de homologação. Confirme que seller e afiliado recebem débitos proporcionais cuja soma é o valor comercial da venda.
7. Para uma venda de cartão Cielo/Pagar.me com split, solicite reembolso no sandbox. Confirme que não há débito na carteira Lowify de seller ou afiliado; a reversão deve aparecer no gateway.
8. Reenvie uma confirmação de reembolso de teste e confirme que não há lançamento duplicado para seller nem afiliado.

Se qualquer valor ficar duplicado, ausente ou incluir a taxa indevidamente, interromper a ativação global e preservar IDs de venda/reembolso para conciliação. Não ajustar saldos manualmente.

## Rollback

1. Definir imediatamente a taxa global como `R$ 0,00` no Admin e manter `CHECKOUT_SERVICE_FEE_AMOUNT=0.00`.
2. Registrar vendas e reembolsos criados após a ativação; eles precisam de conciliação, não de apagamento.
3. Retornar cada componente ao commit registrado antes do deploy, seguindo o processo operacional aprovado, e reconstruir somente o Commerce V2 quando seu código for revertido.
4. Não remover `service_fee_amount`, `charged_amount`, `sales_refund`, migrations, filas Redis, extratos ou configurações de seller. As colunas são aditivas e versões anteriores as ignoram.

## Registro de homologação

### 2026-11-06 — pré-checagem e validação remota

Escopo solicitado: somente `services-commerce-v2`, `front-checkout`, `front-member-area` e `dashboard-seller`. Todos os outros targets oficiais foram mantidos como estavam por solicitação explícita; não receberam Git, Docker ou pré-checagem.

| Target | Estado inicial na VPS | Resultado da pré-checagem | Referência remota da feature | Resultado |
| --- | --- | --- | --- | --- |
| `services-commerce-v2` | `feat/checkout-apple-google-pay` | limpo | `664748e` | bloqueado: não contém `ab866fc` |
| `front-checkout` | `feat/checkout-apple-google-pay` | limpo | `4e9ae77` | bloqueado inicialmente: não continha a referência então documentada |
| `front-member-area` | `feat/end-customer-service-fee` | limpo | `f152c24` | apto; contém o commit esperado |
| `dashboard-seller` | `feat/checkout-apple-google-pay` | limpo | `cabb114c` | bloqueado: não contém `e5c9dd08` |

Foi executado `git fetch origin --prune` apenas nos quatro participantes. A operação foi interrompida antes de `git switch`, `git pull`, DDL, alteração de `.env`, Docker ou testes de compatibilidade, pois os commits necessários ainda não foram publicados em `origin`.

Para retomar, publicar as branches `feat/end-customer-service-fee` de `services-commerce-v2`, `front-checkout` e `dashboard-seller` contendo ao menos os commits listados na tabela **Componentes e referências**. Depois, reiniciar a pré-checagem completa dos quatro targets; não reutilizar este resultado como autorização para pular validações.

### 2026-11-06 — correção da referência do Front Checkout

O Front Checkout foi publicado como `cecfc86`, com histórico diferente do commit local originalmente registrado (`ba780eb`). A comparação direta entre as árvores dos dois commits não apresentou diferença. A referência de deploy foi atualizada para `cecfc86` e a validação completa deve ser repetida antes de qualquer alteração na VPS.

## Referências

- [Plano da taxa de serviço](../../plans/end-customer-service-fee/README.md)
- [Deploy anterior da taxa de serviço](../2026-11-03-end-customer-service-fee/2026-11-03_END_CUSTOMER_SERVICE_FEE_DEPLOY.md)
- [Deploy de rateio de reembolso](../2026-11-04-card-refund-wallet-allocation/2026-11-04_CARD_REFUND_WALLET_ALLOCATION_DEPLOY.md)
