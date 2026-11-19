# Deploy — webhooks por oferta e assinatura automática em novos endpoints

## Objetivo

Permitir destinos globais por produto e destinos restritos por oferta, sem duplicar produto. Configuração com offer_id nulo recebe qualquer oferta do produto; com offer_id preenchido, recebe somente o item daquela oferta.

Cada URL passa a ser um endpoint lógico. Ao salvar ou editar um endpoint pelo
Dashboard, a plataforma gera automaticamente um segredo `whsec_…`; o POST é
assinado com HMAC-SHA256. O seller não informa esse valor no formulário.
Endpoints existentes permanecem sem segredo após o backfill e, portanto,
continuam recebendo o formato legado sem headers de assinatura até serem
salvos ou terem o segredo rotacionado.

~~~text
front-checkout / Checkout Transparente
  -> Commerce V2 (sale + sale item + id_product_offer)
  -> sales:events:pending|paid|refunded
  -> DispatchSaleEventIntegrationsUseCase
  -> Redis sales:integration:webhook
  -> services-sale-integrations / WebhookIntegrationProcess
  -> WebhookSender
  -> POST ao endpoint do seller
~~~

O payload identifica a oferta em product.offer.id e product.offer.name. Para endpoints protegidos, a assinatura é calculada sobre os mesmos bytes JSON enviados no corpo:

~~~text
Content-Type: application/json
Idempotency-Key: <chave por webhook e item vendido>
X-Lowify-Event: sale.paid
X-Lowify-Timestamp: <ISO-8601 UTC>
X-Lowify-Signature: sha256=<HMAC-SHA256 do corpo bruto>
~~~

Os headers X-Lowify existem somente quando há segredo ativo.

## Componentes e referências

| Componente | Diretório de produção | Branch | Ação |
| --- | --- | --- | --- |
| services-commerce-v2 | /opt/lowify/services/service-commerce-v2 | feat/webhooks-by-offer-security | schema, seleção por oferta/endpoint e publicação na fila |
| dashboard-seller | /opt/lowify/front/dashboard-seller | feat/webhooks-by-offer-security | seleção de ofertas por produto e segredo gerado/cifrado |
| services-sale-integrations | /opt/lowify/services/services-sale-integrations | feat/webhooks-by-offer-security | resolução do segredo, assinatura HTTP e histórico de tentativa |

Registrar a revisão exata liberada para cada branch antes da janela.

Não publicar, reiniciar, trocar branch ou aplicar migration em front-checkout, edge-gateway, edge-public-api, Checkout Transparente, edge-webhook, services-commerce-worker ou workers/filas legadas. Em especial, services-commerce-worker e webhook_queue não fazem parte deste fluxo; o consumidor ativo é services-sale-integrations na fila sales:integration:webhook.

## Alterações incluídas

- product_webhooks preserva offer_id nullable; NULL continua sendo o escopo global.
- webhook_endpoints representa a URL e é referenciado por product_webhooks.endpoint_id.
- webhook_endpoint_secrets guarda somente envelope cifrado; texto puro não entra no banco ou Redis.
- webhook_audit_logs registra ações administrativas sem registrar o segredo.
- webhook_delivery_attempts registra resultado, duração, código HTTP e resposta truncada.
- Commerce publica endpoint_id, product_webhook_id, sale_item_id e offer_id na mensagem.
- O serviço de integrações usa a conexão webhook_config para o banco operacional lowify, e não seu banco privado de tracking.
- Para endpoint protegido, segredo ou chave indisponível é falha fechada: não há POST sem assinatura.
- O Dashboard agrupa os vínculos por endpoint e evento; cada cartão de produto
  pode manter todas as ofertas ou um subconjunto delas.

## Pré-requisitos e bloqueadores

1. Confirmar clones limpos e registrar as revisões saudáveis dos três componentes. Não usar reset --hard para contornar alteração local.
2. Ter backup aprovado do banco operacional lowify e janela para os ALTER TABLE.
3. Guardar uma chave forte em cofre e configurar o mesmo WEBHOOK_SECRETS_ENCRYPTION_KEY somente no Dashboard e no serviço de integrações. Configurar também WEBHOOK_SECRETS_ENCRYPTION_KEY_ID no Dashboard.
4. Preparar para services-sale-integrations uma credencial de menor privilégio no banco operacional, configurada por WEBHOOK_CONFIG_DB_*. Não apontá-la para o banco privado do serviço. Configurar também a autenticação Redis do ambiente.
5. Confirmar no Commerce V2:

   ~~~text
   SALE_EVENTS_QUEUE_ACTIVE=true
   USE_SALE_EVENTS_ONLY=true
   ~~~

   Com a segunda flag desligada, o dispatcher filtra webhook e não publica na fila ativa.
6. Não imprimir .env, senha, chave de cifragem, segredo de endpoint, URL com token, dados de cliente nem payload completo em tickets ou logs.
7. Ter endpoint de captura controlado para a validação final, registrando somente headers e o hash do corpo necessários.

## Banco de dados

### Regra operacional

As migrations pertencem à revisão, mas a imagem atual do Commerce V2 não expõe php bin/hyperf.php migrate. Aplicar o DDL manual abaixo pelo procedimento controlado. Não executar migration ampla, não inserir registro manual no controle de migrations e não executar down.

Conectar interativamente sem expor senha:

~~~bash
cd /opt/lowify/data_layer/mariabd
docker compose exec mariadb mariadb -u root -p lowify
~~~

Pré-checagem: se qualquer objeto existir parcialmente, parar e reconciliar o estado antes de aplicar DDL.

~~~sql
SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN (
    'webhook_endpoints',
    'webhook_endpoint_secrets',
    'webhook_audit_logs',
    'webhook_delivery_attempts'
  );

SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'product_webhooks'
  AND COLUMN_NAME IN ('offer_id', 'endpoint_id', 'status', 'updated_at', 'deleted_at')
ORDER BY COLUMN_NAME;
~~~

Em instalação que ainda não recebeu a parte por oferta, aplicar primeiro:

~~~sql
ALTER TABLE product_webhooks
  ADD COLUMN offer_id INT NULL AFTER product_id,
  ADD INDEX idx_product_webhooks_offer_lookup
    (user_id, product_id, offer_id, event_type),
  ADD CONSTRAINT fk_product_webhooks_offer_id
    FOREIGN KEY (offer_id) REFERENCES tbl_product_offers(id)
    ON UPDATE CASCADE ON DELETE RESTRICT;
~~~

Depois, aplicar uma única vez o schema de endpoint e segurança. A collation explícita da URL é necessária para um backfill previsível, independente do padrão do servidor.

~~~sql
CREATE TABLE webhook_endpoints (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id INT UNSIGNED NOT NULL,
  webhook_url VARCHAR(2048) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT NULL,
  deleted_at TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_webhook_endpoints_user_url (user_id, webhook_url),
  KEY idx_webhook_endpoints_active (user_id, status, deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE webhook_endpoint_secrets (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  endpoint_id INT UNSIGNED NOT NULL,
  secret_encrypted MEDIUMTEXT NOT NULL,
  encryption_key_id VARCHAR(100) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  rotated_at TIMESTAMP NULL DEFAULT NULL,
  deleted_at TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_webhook_endpoint_secrets_active (endpoint_id, status, deleted_at),
  CONSTRAINT fk_webhook_endpoint_secrets_endpoint
    FOREIGN KEY (endpoint_id) REFERENCES webhook_endpoints(id)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE webhook_audit_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id INT UNSIGNED NOT NULL,
  endpoint_id INT UNSIGNED NULL,
  action VARCHAR(50) NOT NULL,
  metadata JSON NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_webhook_audit_logs_user_created (user_id, created_at),
  KEY idx_webhook_audit_logs_endpoint_created (endpoint_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE webhook_delivery_attempts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  endpoint_id INT UNSIGNED NULL,
  product_webhook_id INT UNSIGNED NULL,
  sale_id INT UNSIGNED NULL,
  sale_item_id INT UNSIGNED NULL,
  event_type VARCHAR(50) NOT NULL,
  is_test TINYINT(1) NOT NULL DEFAULT 0,
  status VARCHAR(20) NOT NULL,
  http_status INT NULL,
  duration_ms INT NULL,
  response_body TEXT NULL,
  error_code VARCHAR(100) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_webhook_delivery_attempts_endpoint_created (endpoint_id, created_at),
  KEY idx_webhook_delivery_attempts_sale_event (sale_id, event_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE product_webhooks
  ADD COLUMN endpoint_id INT UNSIGNED NULL AFTER user_id,
  ADD CONSTRAINT fk_product_webhooks_endpoint_id
    FOREIGN KEY (endpoint_id) REFERENCES webhook_endpoints(id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'active' AFTER event_type,
  ADD COLUMN updated_at TIMESTAMP NULL DEFAULT NULL AFTER created_at,
  ADD COLUMN deleted_at TIMESTAMP NULL DEFAULT NULL AFTER updated_at,
  ADD KEY idx_product_webhooks_endpoint_status (endpoint_id, status),
  ADD KEY idx_product_webhooks_active (user_id, status, deleted_at);
~~~

Fazer o backfill sem criar segredo. A collation explícita no JOIN evita comparação implícita entre tabelas com collations diferentes.

~~~sql
INSERT INTO webhook_endpoints (user_id, webhook_url, status, created_at)
SELECT user_id, webhook_url, 'active', NOW()
FROM product_webhooks
WHERE webhook_url IS NOT NULL
  AND TRIM(webhook_url) <> ''
GROUP BY user_id, webhook_url
ON DUPLICATE KEY UPDATE id = id;

UPDATE product_webhooks AS product_webhook
JOIN webhook_endpoints AS endpoint
  ON endpoint.user_id = product_webhook.user_id
 AND endpoint.webhook_url COLLATE utf8mb4_unicode_ci
       = product_webhook.webhook_url COLLATE utf8mb4_unicode_ci
SET product_webhook.endpoint_id = endpoint.id
WHERE product_webhook.endpoint_id IS NULL
  AND product_webhook.webhook_url IS NOT NULL
  AND TRIM(product_webhook.webhook_url) <> '';
~~~

Validar antes de publicar código:

~~~sql
SELECT COUNT(*) AS active_bindings_without_endpoint
FROM product_webhooks
WHERE status = 'active'
  AND deleted_at IS NULL
  AND endpoint_id IS NULL;

SELECT COUNT(*) AS legacy_secrets_created_by_backfill
FROM webhook_endpoint_secrets;

SELECT CONSTRAINT_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'product_webhooks'
  AND CONSTRAINT_NAME IN (
    'fk_product_webhooks_offer_id',
    'fk_product_webhooks_endpoint_id'
  );
~~~

As duas primeiras consultas devem retornar 0; a última deve apresentar as duas FKs. Não alterar offer_id nem criar segredo para endpoint legado.

## Sequência de deploy

### 1. Pré-checagem dos repositórios

A primeira saída em cada diretório deve ser vazia. Caso contrário, parar e preservar a alteração local.

~~~bash
cd /opt/lowify/services/service-commerce-v2
git status --porcelain=v1
git fetch origin --prune
git show --quiet --oneline origin/feat/webhooks-by-offer-security

cd /opt/lowify/front/dashboard-seller
git status --porcelain=v1
git fetch origin --prune
git show --quiet --oneline origin/feat/webhooks-by-offer-security

cd /opt/lowify/services/services-sale-integrations
git status --porcelain=v1
git fetch origin --prune
git show --quiet --oneline origin/feat/webhooks-by-offer-security
~~~

Registrar ainda o valor anterior de USE_SALE_EVENTS_ONLY e as revisões em execução, sem copiar arquivos de ambiente.

### 2. Preparar chave e conexão operacional

No ambiente de services-sale-integrations, configurar sem revelar valores:

~~~text
WEBHOOK_CONFIG_DB_DRIVER=mysql
WEBHOOK_CONFIG_DB_HOST=<host do banco operacional>
WEBHOOK_CONFIG_DB_PORT=3306
WEBHOOK_CONFIG_DB_DATABASE=lowify
WEBHOOK_CONFIG_DB_USERNAME=<credencial de menor privilégio>
WEBHOOK_CONFIG_DB_PASSWORD=<segredo externo>
WEBHOOK_CONFIG_DB_CHARSET=utf8mb4
WEBHOOK_CONFIG_DB_COLLATION=utf8mb4_unicode_ci
WEBHOOK_SECRETS_ENCRYPTION_KEY=<mesma chave do Dashboard>
REDIS_HOST=<host Redis do ambiente>
REDIS_PORT=6379
REDIS_AUTH=<segredo externo>
REDIS_DB=0
SALE_INTEGRATIONS_WEBHOOK_PROCESS_ENABLED=true
SALE_INTEGRATIONS_WEBHOOK_QUEUE=sales:integration:webhook
~~~

No Dashboard, configurar a mesma WEBHOOK_SECRETS_ENCRYPTION_KEY e um WEBHOOK_SECRETS_ENCRYPTION_KEY_ID não vazio. Não liberar o salvamento de endpoint antes de confirmar a chave nos dois processos: o Dashboard cifra o segredo gerado e o serviço de integrações o decifra para assinar a entrega.

### 3. Aplicar e validar o schema

Aplicar a seção **Banco de dados** depois do backup e antes de subir qualquer código novo. A revisão anterior do Commerce V2 ignora as colunas aditivas, portanto esse intervalo é compatível.

### 4. Publicar o consumidor de integrações

Publicar o consumidor antes de permitir que o Dashboard gere segredos. Ele mantém a entrega de mensagens legadas sem assinatura enquanto o Commerce ainda estiver na revisão anterior.

~~~bash
cd /opt/lowify/services/services-sale-integrations
git switch feat/webhooks-by-offer-security
git pull --ff-only origin feat/webhooks-by-offer-security
docker compose config --quiet
docker compose build service-sale-integrations
docker compose up -d --no-deps --force-recreate service-sale-integrations
docker compose ps
docker compose logs --tail=200 service-sale-integrations
docker compose exec -T service-sale-integrations sh -lc \
  'test -n "$WEBHOOK_CONFIG_DB_HOST" && test -n "$WEBHOOK_CONFIG_DB_DATABASE" && test -n "$WEBHOOK_SECRETS_ENCRYPTION_KEY" && test -n "$REDIS_HOST" && test -n "$REDIS_AUTH"'
docker compose exec -T service-sale-integrations sh -lc \
  'curl -fsS http://127.0.0.1:9501/health/redis'
~~~

Não prossiga se o healthcheck Redis falhar por DNS, autenticação ou conexão: o
consumidor não deve ficar em execução acumulando falhas de fila.

### 5. Publicar o Commerce V2

No .env, manter SALE_EVENTS_QUEUE_ACTIVE=true e definir USE_SALE_EVENTS_ONLY=true. Depois:

~~~bash
cd /opt/lowify/services/service-commerce-v2
git switch feat/webhooks-by-offer-security
git pull --ff-only origin feat/webhooks-by-offer-security
docker compose build service-commerce-v2
docker compose up -d --no-deps --force-recreate service-commerce-v2
docker compose ps
docker compose logs --tail=200 service-commerce-v2
docker compose exec -T service-commerce-v2 sh -lc \
  'test "$SALE_EVENTS_QUEUE_ACTIVE" = true && test "$USE_SALE_EVENTS_ONLY" = true'
docker compose exec -T service-commerce-v2 sh -lc \
  'curl -fsS http://127.0.0.1:9501/'
~~~

Se a checagem falhar, não publicar o Dashboard.

### 6. Publicar o Dashboard Seller

Publicar somente depois de schema, consumidor e Commerce V2 estarem saudáveis.
Como esta entrega introduz WEBHOOK_SECRETS_ENCRYPTION_KEY no ambiente do
Dashboard, recriar somente o container web para que ele leia a variável nova:

~~~bash
cd /opt/lowify/front/dashboard-seller
git switch feat/webhooks-by-offer-security
git pull --ff-only origin feat/webhooks-by-offer-security
git rev-parse --short HEAD
docker compose up -d --no-deps --force-recreate front-dashboard-seller
docker compose ps front-dashboard-seller
~~~

O Dashboard usa o diretório do projeto montado como volume; não há build nesta
etapa. A recriação acima é necessária apenas para carregar a variável de
ambiente nova.

## Validação pós-deploy

1. Conferir schema, flags do Commerce e presença não vazia da chave no Dashboard e no serviço de integrações, sem revelar valor.
2. Criar um produto de teste com ofertas A e B. No mesmo cartão, salvar um
   endpoint global e, em outro endpoint, selecionar somente a oferta A.
   Confirmar que “Ofertas: Todas” é o padrão, que produto com uma única oferta
   não mostra esse filtro, e que o backend rejeita oferta de outro seller ou
   produto.
3. Confirmar que cada endpoint salvo recebe segredo gerado automaticamente,
   exibido apenas mascarado em “Meus endpoints”. Revelar e copiar devem
   funcionar somente para o dono autenticado; a rotação deve exigir a
   confirmação financeira, substituir a versão ativa e invalidar a anterior.
   Conferir no banco somente envelope cifrado e identificador da chave.
4. Processar venda normal com oferta A. Confirmar entrega global e da oferta
   A, sem entrega da oferta B, e presença dos headers X-Lowify no endpoint
   criado pelo Dashboard.
5. Processar venda de Checkout Transparente com oferta B para endpoint
   protegido. Confirmar product.offer.id, product.offer.name,
   product_webhook_id, sale_item_id e endpoint_id; endpoint da oferta A não
   pode ser selecionado.
6. No capturador controlado, recalcular HMAC-SHA256 do corpo bruto com o
   segredo revelado ao dono. O resultado deve coincidir com
   X-Lowify-Signature; X-Lowify-Event e X-Lowify-Timestamp devem existir. Não
   registrar segredo ou corpo completo.
7. Configurar dois endpoints para a mesma oferta e confirmar um POST por
   vínculo elegível. Idempotência e tentativa devem distinguir
   product_webhook_id e sale_item_id.
8. Preservar ao menos um endpoint legado sem segredo e confirmar sua entrega
   sem X-Lowify, mantendo a compatibilidade até que ele seja salvo ou tenha o
   segredo rotacionado.
9. Consultar webhook_delivery_attempts para status, duração e HTTP. A falha de persistir histórico não pode mascarar o resultado do POST.
10. Consultar somente o tamanho da fila; nunca executar LPOP, RPOP, BLPOP ou limpeza de chave:

   ~~~bash
   redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --user default --askpass \
     LLEN sales:integration:webhook
   ~~~

11. Remover somente dados de teste pelo fluxo permitido. Não apagar mensagens operacionais, segredos reais ou schema.

## Rollback

1. Impedir criação de endpoints protegidos retornando primeiro o dashboard-seller à revisão saudável.
2. Se a falha for de seleção/publicação, retornar services-commerce-v2, reconstruir e recriar somente esse serviço. A revisão anterior ignora as colunas novas.
3. Se a falha for na entrega, retornar services-sale-integrations somente depois de avaliar mensagens em sales:integration:webhook. Não substituir o consumidor por services-commerce-worker.
4. Restaurar USE_SALE_EVENTS_ONLY ao valor anterior somente após reverter o Commerce e validar integrações existentes.
5. Não executar down, não remover colunas, índices, FKs, endpoints, envelopes de segredo, tentativas ou mensagens Redis. A reversão é por código/configuração, não por perda de dados.

## Evidência de homologação deste roteiro

No ambiente de teste, schema aditivo e backfill foram verificados: as configurações existentes receberam endpoint e nenhum segredo foi criado para elas. A seleção do Commerce V2 foi exercitada em imagem descartável e confirmou metadados de endpoint do vínculo escolhido.

O consumidor services-sale-integrations foi exercitado contra endpoint de captura controlado em dois cenários: endpoint protegido produziu assinatura HMAC válida sobre o corpo bruto; endpoint sem segredo realizou POST sem X-Lowify. Endpoints e tentativas temporários foram removidos ao fim do teste. Os arquivos PHP alterados passaram em verificação de sintaxe e as imagens novas foram construídas; isto não representa publicação de produção.

Na revisão visual posterior, o Dashboard foi conferido estaticamente contra o
mockup aprovado: seleção múltipla de ofertas dentro do cartão, segredo fora do
formulário, máscara, revelar, copiar e rotação. No ambiente de teste, seis
segredos ativos de endpoints foram verificados cifrados e decifráveis sem
expor seus valores. A execução do POST final continua condicionada ao
healthcheck Redis e às credenciais WEBHOOK_CONFIG_DB_* do consumidor descritos
acima; sem eles, o serviço deve permanecer parado em vez de acumular falhas.
