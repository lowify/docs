# Deploy — webhooks por oferta

## Objetivo

Permitir que um único produto tenha destinos de webhook globais e destinos
restritos a cada oferta. Uma configuração com `offer_id = NULL` continua
recebendo eventos de qualquer oferta do produto; uma configuração com
`offer_id` preenchido recebe somente o item vendido com aquela oferta.

O payload publicado pelo caminho ativo passa a identificar a oferta em
`product.offer.id` e `product.offer.name`. O comportamento vale tanto para o
checkout convencional quanto para o Checkout Transparente, pois ambos chegam
à mesma venda persistida no Commerce V2.

```text
front-checkout / Checkout Transparente
  -> Commerce V2 (sale + sale item + id_product_offer)
  -> sales:events:pending|paid|refunded
  -> DispatchSaleEventIntegrationsUseCase
  -> sales:integration:webhook
  -> consumidor HTTP externo
```

O consumidor HTTP não recebe código novo nesta publicação. Ele permanece
responsável apenas por entregar a mensagem que já foi selecionada pelo
Commerce V2.

## Componentes e referências

| Componente | Diretório de produção | Branch | Commit esperado | Ação |
| --- | --- | --- | --- | --- |
| `services-commerce-v2` | `/opt/lowify/services/service-commerce-v2` | `feat/webhooks-by-offer` | `d23ef62` | schema, seleção e publicação na fila ativa |
| `dashboard-seller` | `/opt/lowify/front/dashboard-seller` | `feat/webhooks-by-offer` | `65c0e7ff` | cadastro, edição e listagem por oferta |

Não publicar, reiniciar, trocar branch ou aplicar migration em `front-checkout`,
`edge-gateway`, `edge-public-api`, Checkout Transparente, `edge-webhook`,
`services-commerce-worker` ou worker/filas legadas por causa desta entrega.
Em especial, `services-commerce-worker` e `webhook_queue` não participam do
caminho ativo confirmado acima.

## Alterações incluídas

- `product_webhooks` recebe `offer_id` nullable, índice de consulta e FK para
  `tbl_product_offers(id)` com `ON UPDATE CASCADE` e `ON DELETE RESTRICT`.
- O Commerce V2 inclui `sale_item_id` e a oferta de cada item nos dados de
  venda e seleciona cada configuração pelo item que a qualificou.
- A mensagem de `sales:integration:webhook` passa os metadados
  `product_webhook_id`, `sale_item_id` e `offer_id`.
- O Dashboard permite escolher opcionalmente uma oferta quando exatamente um
  produto está selecionado; registros existentes continuam globais.

Não há backfill: registros existentes permanecem com `offer_id = NULL`.

## Pré-requisitos e bloqueadores

1. Registrar a revisão saudável atual dos dois componentes e confirmar que os
   clones de produção estão limpos antes de trocar de branch.
2. Ter backup aprovado do banco `lowify` e uma janela para o `ALTER TABLE`.
   A alteração é aditiva, mas a tabela pode ser bloqueada durante a operação.
3. Confirmar que o Commerce V2 usa o caminho de eventos:

   ```text
   SALE_EVENTS_QUEUE_ACTIVE=true
   USE_SALE_EVENTS_ONLY=true
   ```

   A segunda variável é obrigatória. Com ela desligada, o dispatcher de
   eventos filtra as plataformas `webhook` e `utmify`, portanto não publica em
   `sales:integration:webhook` mesmo que a seleção por oferta esteja correta.
4. O consumidor externo de `sales:integration:webhook` deve estar operacional
   para a validação do POST final. A publicação do Commerce V2 pode ser
   validada independentemente; não substituir essa fronteira pelo worker
   legado.
5. Não imprimir `.env`, senhas de banco/Redis, URLs de webhook com segredos,
   dados de cliente ou payloads completos em tickets e logs de deploy.

## Banco de dados

### Regra operacional

Embora o repositório contenha a migration
`20261117120000_add_offer_id_to_product_webhooks_table.php`, a imagem de
runtime atual do Commerce V2 não expõe `php bin/hyperf.php migrate`. Para este
serviço, aplicar somente o DDL abaixo pelo procedimento manual controlado do
banco. Não executar um `migrate` amplo, não registrar migration manualmente na
tabela de controle e não executar `down`.

Antes de aplicar, conectar interativamente ao banco sem expor a senha:

```bash
cd /opt/lowify/data_layer/mariabd
docker compose exec mariadb mariadb -u root -p lowify
```

Executar a pré-checagem abaixo. Ela deve mostrar ausência da coluna, do índice
e da FK. Se qualquer estrutura já existir parcialmente, parar e reconciliar o
estado antes de executar o `ALTER TABLE`; não tentar compensar com DDL parcial.

```sql
SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'product_webhooks'
  AND COLUMN_NAME = 'offer_id';

SELECT INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columns_in_index
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'product_webhooks'
  AND INDEX_NAME = 'idx_product_webhooks_offer_lookup'
GROUP BY INDEX_NAME;

SELECT CONSTRAINT_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'product_webhooks'
  AND CONSTRAINT_NAME = 'fk_product_webhooks_offer_id';
```

Com as três consultas vazias, aplicar exatamente uma vez:

```sql
ALTER TABLE product_webhooks
  ADD COLUMN offer_id INT NULL AFTER product_id,
  ADD INDEX idx_product_webhooks_offer_lookup
    (user_id, product_id, offer_id, event_type),
  ADD CONSTRAINT fk_product_webhooks_offer_id
    FOREIGN KEY (offer_id) REFERENCES tbl_product_offers(id)
    ON UPDATE CASCADE ON DELETE RESTRICT;
```

Em seguida, repetir as consultas e confirmar: coluna `int` nullable, índice na
ordem indicada e FK para `tbl_product_offers(id)`. Não alterar linhas
existentes: `NULL` é precisamente a compatibilidade dos webhooks por produto.

## Sequência de deploy

### 1. Pré-checagem dos repositórios

Em cada diretório, a primeira saída precisa estar vazia. Caso não esteja, parar
e preservar a alteração local para análise; não usar `reset --hard`.

```bash
cd /opt/lowify/services/service-commerce-v2
git status --porcelain=v1
git fetch origin --prune
git show --quiet --oneline d23ef62

cd /opt/lowify/front/dashboard-seller
git status --porcelain=v1
git fetch origin --prune
git show --quiet --oneline 65c0e7ff
```

Também registrar o valor anterior de `USE_SALE_EVENTS_ONLY`, sem revelar
outros valores do arquivo de ambiente. Ele será necessário se houver rollback.

### 2. Preparar o Commerce V2 e aplicar o schema

Atualizar o código, confirmar a revisão e construir a imagem antes de mudar o
tráfego. A construção não reinicia o container em execução.

```bash
cd /opt/lowify/services/service-commerce-v2
git switch feat/webhooks-by-offer
git pull --ff-only origin feat/webhooks-by-offer
git merge-base --is-ancestor d23ef62 HEAD
git rev-parse --short HEAD
docker compose build service-commerce-v2
```

Aplicar e validar o DDL da seção **Banco de dados** depois do build e antes de
subir o novo processo. A versão anterior ignora a coluna nova, portanto esse
intervalo é compatível.

### 3. Ativar o caminho de eventos e publicar o Commerce V2

No `.env` do Commerce V2, manter `SALE_EVENTS_QUEUE_ACTIVE=true` e definir
`USE_SALE_EVENTS_ONLY=true`. Não substituir o arquivo inteiro nem copiar seu
conteúdo para o terminal. Depois, recriar somente o serviço alterado:

```bash
cd /opt/lowify/services/service-commerce-v2
docker compose up -d --no-deps --force-recreate service-commerce-v2
docker compose ps
docker compose logs --tail=200 service-commerce-v2
docker compose exec -T service-commerce-v2 sh -lc 'test "$SALE_EVENTS_QUEUE_ACTIVE" = true && test "$USE_SALE_EVENTS_ONLY" = true'
docker compose exec -T service-commerce-v2 sh -lc 'curl -fsS http://127.0.0.1:9501/'
```

O último comando deve retornar a resposta HTTP saudável do Hyperf. Se a
checagem das flags falhar, não liberar o Dashboard: corrigir o ambiente e
recriar o container antes de continuar.

### 4. Publicar o Dashboard Seller

Publicar a interface somente depois de o schema e o Commerce V2 estarem
saudáveis:

```bash
cd /opt/lowify/front/dashboard-seller
git switch feat/webhooks-by-offer
git pull --ff-only origin feat/webhooks-by-offer
git merge-base --is-ancestor 65c0e7ff HEAD
git rev-parse --short HEAD
```

O Dashboard usa o diretório do projeto montado como volume. Não há build nem
restart de container nesta etapa, salvo se a operação detectar uma configuração
local diferente desse modelo.

## Validação pós-deploy

1. Conferir novamente o schema e as duas flags sem revelar segredos.
2. No Dashboard, criar dados de teste exclusivos: um produto, as ofertas A e
   B, uma configuração global e pelo menos uma configuração para cada oferta.
   Confirmar que a oferta só aparece para um produto selecionado e que ela
   pertence ao seller e produto escolhidos.
3. Processar uma venda normal de teste com a oferta A. Sem consumir a fila,
   verificar que a mensagem em `sales:integration:webhook` contém somente o
   webhook global e o da oferta A; a outra oferta não pode aparecer. Confirmar
   `product.offer` e os metadados `product_webhook_id`, `sale_item_id` e
   `offer_id`.
4. Repetir com uma venda de Checkout Transparente para outra oferta. O mesmo
   critério deve valer porque a origem é `tbl_sale_items.id_product_offer`.
5. Confirmar vários endpoints para uma mesma oferta e os casos de venda sem
   oferta, que deve selecionar somente configurações globais.
6. Consultar somente o tamanho da fila, usando a autenticação Redis do
   ambiente e `--askpass`; não executar `LPOP`, `RPOP`, `BLPOP`, limpeza de
   chave ou qualquer consumo durante a verificação:

   ```bash
   redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --user default --askpass LLEN sales:integration:webhook
   ```

7. Quando o consumidor externo estiver disponível, usar endpoint de captura
   controlado e confirmar um POST por configuração elegível, com a oferta
   correta. A entrega final e a chave de idempotência devem distinguir
   `product_webhook_id` e `sale_item_id`.
8. Remover somente as configurações e vendas de teste pelo fluxo permitido;
   não apagar mensagens operacionais nem as estruturas de schema.

## Rollback

1. Interromper a criação de novos webhooks específicos retornando primeiro o
   `dashboard-seller` à revisão saudável registrada antes da janela.
2. Se o problema estiver no produtor, retornar `services-commerce-v2` à
   revisão saudável registrada, reconstruir e recriar somente esse serviço.
3. Restaurar `USE_SALE_EVENTS_ONLY` ao valor anotado na pré-checagem somente
   após o código ter voltado; validar o comportamento de integrações existente
   antes de encerrar a janela.
4. Não executar `down`, não remover `offer_id`, índice ou FK, não converter
   webhooks específicos em globais e não limpar `sales:integration:webhook`.
   O schema é aditivo e a versão anterior o ignora.
5. Preservar e analisar mensagens já publicadas e configurações criadas durante
   a janela. Não há compensação automática de entrega.

## Evidência de homologação deste roteiro

No ambiente de teste, as referências remotas foram confirmadas em `d23ef62`
(Commerce V2) e `65c0e7ff` (Dashboard). O schema final foi conferido com a
coluna, índice e FK previstos; o Commerce respondeu ao health check. O teste
manual isolado do dispatcher, com fila exclusiva e dados temporários, publicou
os destinos global e da oferta correspondente para `pending`, `paid` e
`refunded`, excluindo a oferta diferente, e foi limpo ao final.

A checagem atual de ambiente encontrou `SALE_EVENTS_QUEUE_ACTIVE=true`, mas
`USE_SALE_EVENTS_ONLY` ausente. Isso é um bloqueador deliberadamente exposto
neste roteiro: esta homologação comprovou o dispatcher com a flag ativada no
teste isolado, porém o ambiente não deve ser considerado publicado até que a
variável seja configurada e a validação pós-deploy seja executada.
