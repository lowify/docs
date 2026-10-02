# Deploy — Referência externa da venda

## Objetivo

Publicar o campo opcional `external_reference` no checkout. Quando uma URL de checkout o receber, o valor válido deve ser persistido em `lowify.sales`, incluído no webhook de integração da venda e exibido no detalhe da venda para seller e administração.

Esta entrega não habilita refund por seller e não inclui mudanças em saque, Wallet, Public API ou Banking.

## Componentes e referências

| Componente | Host | Repositório | Branch de deploy | Papel |
| --- | --- | --- | --- | --- |
| Checkout | `144.126.149.57` | `front-checkout` | `feat/external-reference-seller-refund` | Recebe e preserva `external_reference`, inclusive em URL com `offer`. |
| Commerce V2 | `144.126.149.57` | `services-commerce-v2` | `feat/external-reference-seller-refund` | Valida, persiste o campo em `sales`, disponibiliza-o no contrato da venda e o propaga para upsells. |
| Integrações de venda | `147.93.180.183` | `services-sale-integrations` | `feat/external-reference-seller-refund` | Inclui o campo no payload de webhook. |
| Dashboard Seller | `144.126.149.57` | `dashboard-seller` | `feat/external-reference-seller-refund` | Exibe o campo no detalhe seller e administrativo. |

As quatro branches estão publicadas no remoto. Checkout, Commerce V2 e Dashboard incluem a `main` remota atual; `services-sale-integrations` inclui a `master` remota atual, pois o repositório não possui branch `main`.

## Alterações incluídas

### Contrato e validação

- Nome canônico: `external_reference`. Não há compatibilidade com o nome `external_id`.
- O campo é opcional, com no máximo 100 caracteres.
- O primeiro caractere precisa ser alfanumérico; os demais aceitos são letras, números, `.`, `_`, `:`, `@`, `/` e `-`.
- Valor ausente ou inválido não é persistido.

### Fluxo publicado

```text
URL do checkout com external_reference
-> front-checkout valida e mantém o parâmetro
-> checkout com offer preserva o valor no redirecionamento
-> services-commerce-v2 valida novamente e grava sales.external_reference
-> venda de upsell herda external_reference da venda original
-> services-sale-integrations envia external_reference no webhook
-> dashboard-seller mostra o valor quando preenchido
```

Não há nova rota, JWT, variável de ambiente, fila ou segredo. O payload de webhook é compatível: apenas recebe um novo campo opcional.

## Pré-requisitos e bloqueadores

1. Confirmar que as quatro branches remotas indicadas na tabela foram revisadas antes da janela.
2. `services-sale-integrations` foi iniciado a partir de `master`; confirmar com o responsável se essa é a base produtiva correta antes de publicar.
3. O host produtivo de `services-sale-integrations` é `147.93.180.183`, no diretório `/opt/lowify/services/services-sale-integrations`.
4. Confirmar que os diretórios participantes estão limpos, que `origin` é o remoto esperado e que existe uma referência anterior aprovada para rollback.
5. Reservar uma janela para o `ALTER TABLE` aditivo em `lowify.sales`. Não executar SQL ou migrations automáticas fora da sequência abaixo.

## Banco de dados

Commerce V2 contém a migration `20260930000000_add_external_reference_to_sales_table.php`. Para este deploy, o operador deve aplicar manualmente o SQL aditivo no banco compartilhado `lowify`; não executar migrations automáticas no Commerce.

1. Antes de subir qualquer componente, rodar [VALIDATE.sql](sql/lowify/VALIDATE.sql). A consulta de pré-check deve retornar **0 linhas** para `external_reference`.
2. Executar uma única vez [DEPLOY.sql](sql/lowify/DEPLOY.sql).
3. Reexecutar [VALIDATE.sql](sql/lowify/VALIDATE.sql). A coluna deve existir como `varchar(100)` e aceitar `NULL`.
4. Se a pré-checagem já retornar a coluna, interromper e registrar o resultado; não executar o `ALTER TABLE` novamente.

A alteração é aditiva. Registros existentes permanecem com `external_reference = NULL`; o código anterior ignora a coluna, portanto ela não deve ser removida em rollback operacional.

## Sequência de deploy

Modo de rebuild: incremental. Commerce V2 e Integrações exigem build/restart; Checkout e Dashboard usam o código montado e exigem somente atualização Git. Primeiro concluir todas as etapas do host `144.126.149.57`; atualizar Integrações por último no host `147.93.180.183`.

### Etapa 1 — Atualizar e construir o Commerce V2

No servidor principal, em `/opt/lowify/services/service-commerce-v2`:

```bash
git fetch origin --prune
git switch feat/external-reference-seller-refund
git pull --ff-only origin feat/external-reference-seller-refund
docker compose build
```

### Etapa 2 — Aplicar o ajuste de banco

Executar os SQLs da seção **Banco de dados** no banco `lowify`, depois dos builds concluírem e antes de iniciar os containers novos.

### Etapa 3 — Iniciar Commerce V2

Iniciar Commerce V2:

```bash
cd /opt/lowify/services/service-commerce-v2
docker compose up -d
docker compose ps
docker compose logs --tail=100 service-commerce-v2
```

Não consumir, apagar ou reprocessar filas como parte desta etapa.

### Etapa 4 — Atualizar Checkout e Dashboard (`144.126.149.57`)

1. Checkout, em `/opt/lowify/front/front-checkout`:

   ```bash
   git fetch origin --prune
   git switch feat/external-reference-seller-refund
   git pull --ff-only origin feat/external-reference-seller-refund
   ```

2. Dashboard, em `/opt/lowify/front/dashboard-seller`:

   ```bash
   git fetch origin --prune
   git switch feat/external-reference-seller-refund
   git pull --ff-only origin feat/external-reference-seller-refund
   ```

Não executar build ou restart nos fronts nesta entrega. Atualizá-los depois de Commerce V2 estar saudável.

### Etapa 5 — Atualizar Integrações por último (`147.93.180.183`)

Somente após concluir as etapas no host principal, atualizar e reconstruir o consumer de integrações:

```bash
cd /opt/lowify/services/services-sale-integrations
git fetch origin --prune
git switch feat/external-reference-seller-refund
git pull --ff-only origin feat/external-reference-seller-refund
docker compose up -d --build
docker compose ps
```

Não consumir, apagar ou reprocessar filas durante esta etapa.

## Validação pós-deploy

Usar uma venda de teste e uma integração webhook de teste, sem dados reais de cliente.

1. Abra uma URL de checkout com `external_reference=REF-20261001-A`.
   - Resultado esperado: o checkout abre normalmente.
2. Repita usando uma URL que use `offer`, mantendo o mesmo parâmetro.
   - Resultado esperado: após o redirecionamento, o checkout abre na oferta correta e preserva a referência.
3. Conclua uma compra de teste.
   - Resultado esperado: a venda é criada normalmente.
4. Conclua um upsell da mesma compra de teste.
   - Resultado esperado: a venda de upsell é criada com a mesma referência externa da venda original.
5. Abra o detalhe da venda principal e do upsell como seller e como administrador.
   - Resultado esperado: ambos exibem `REF-20261001-A` somente quando o campo foi enviado.
6. Confirme no endpoint receptor de webhook de teste que os payloads da venda principal e do upsell contêm `external_reference` com o mesmo valor.
7. Repita com um valor inválido, por exemplo ` ref com espaço`.
   - Resultado esperado: a compra continua possível, mas o campo não aparece no detalhe nem no webhook.
8. Se algum resultado não ocorrer, interrompa a aprovação, registre URL, horário, `order_id` de teste e comportamento observado. Não apagar vendas, filas ou registros para forçar nova tentativa.

## Rollback

1. Retornar os componentes de código na ordem inversa: Dashboard, Checkout, Integrações e Commerce V2, usando a referência anterior aprovada e `git pull --ff-only`.
2. Reconstruir/reiniciar os mesmos containers que foram atualizados.
3. Não remover `sales.external_reference`. A coluna é aditiva e versões anteriores do código a ignoram.
4. Não apagar valores já gravados e não tentar reemitir ou remover webhooks já enviados. O payload de webhook com o campo adicional permanece válido para consumidores tolerantes a campos desconhecidos.

## Fora de escopo

- Refund por seller, PIN financeiro, reserva de saldo, saque e Wallet.
- Qualquer alteração em `seller_balance_holds`.
- Alteração de contratos de webhook além do campo opcional `external_reference`.
