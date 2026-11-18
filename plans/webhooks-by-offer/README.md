# Plano — Webhooks por endpoint e oferta

> Status: planejado
> Última atualização: 2026-11-17
> Confiança: modelo atual confirmado; evolução de endpoint e segredo pendente

## Decisão

Manter product_webhooks como a configuração operacional e preservar uma linha
por combinação de endpoint, evento, produto e oferta.

Não haverá, nesta evolução, uma tabela de vínculos múltiplos de ofertas nem
uma tabela de eventos. A interface agrupa os registros por endpoint, mas cada
oferta específica continua sendo um registro independente.

~~~~text
endpoint + event_type + product_id + offer_id? = 1 linha em product_webhooks
~~~~

offer_id NULL significa todas as ofertas do produto. offer_id preenchido
restringe o webhook àquela oferta.

## Estado atual confirmado

O deploy atual já adiciona offer_id nullable a product_webhooks e usa
tbl_product_offers como fonte de verdade das ofertas:

~~~~text
product_webhooks
  user_id + product_id + offer_id? + event_type + webhook_url
~~~~

No dashboard, uma oferta específica só pode ser escolhida após selecionar um
único produto. O backend confirma que a oferta pertence ao produto e ao
seller; uma configuração global pode continuar abrangendo mais de um produto.

O dispatcher seleciona tanto a configuração global do produto quanto a
configuração específica da oferta vendida. O contrato e o DDL atuais estão em
deploys/2026-11-17-webhooks-by-offer/2026-11-17_WEBHOOKS_BY_OFFER_DEPLOY.md.

## Modelo alvo

~~~~text
webhook_endpoints
  └─ webhook_endpoint_secrets

product_webhooks
  └─ endpoint_id + event_type + product_id + offer_id?
~~~~

### webhook_endpoints

Esta tabela representa o endpoint lógico e permite que uma URL exista mesmo
sem eventos ativos.

| Campo | Regra |
| --- | --- |
| id | identificador interno |
| user_id | dono do endpoint |
| webhook_url | URL de entrega |
| status, deleted_at | exclusão lógica |
| timestamps | auditoria de criação e alteração |

Não há nome editável de endpoint nesta etapa. A interface mostra a própria
URL. Apagar o endpoint apenas o inativa.

### webhook_endpoint_secrets

| Campo | Regra |
| --- | --- |
| id, endpoint_id | associação ao endpoint |
| secret_encrypted | segredo cifrado; nunca texto puro no banco |
| encryption_key_id | referência para rotação da chave de cifragem |
| status | apenas um segredo ativo por endpoint |
| rotated_at, deleted_at | histórico de rotação |

Rotacionar cria uma nova versão ativa e inativa a anterior. O segredo é usado
para calcular a assinatura HMAC-SHA256 do corpo bruto.

### product_webhooks

Esta tabela continua contendo uma linha por escopo de entrega.

| Campo | Regra |
| --- | --- |
| endpoint_id | novo pai lógico; FK para webhook_endpoints |
| event_type | sale.paid, sale.pending ou sale.refunded |
| product_id | produto que qualifica a entrega |
| offer_id | NULL para todas as ofertas; ID para uma oferta específica |
| status, deleted_at | substituem DELETE físico |
| timestamps | preservam auditoria do vínculo |

Uma oferta específica não é agrupada no banco. Por exemplo, duas ofertas para
o mesmo produto e evento resultam em duas linhas de product_webhooks.

Quando uma oferta for inativada ou removida pelo fluxo de produto, os
webhooks específicos dela devem ser inativados. Eles não podem ser convertidos
automaticamente para globais, pois isso alteraria o escopo de entrega.

## Exclusão lógica

| Ação | Efeito |
| --- | --- |
| Remover produto de um evento | inativa a linha correspondente em product_webhooks |
| Remover oferta específica | inativa somente a linha com aquele offer_id |
| Remover evento | inativa as linhas ativas do endpoint com aquele event_type |
| Apagar endpoint | inativa endpoint, segredo ativo e todas as linhas ativas do endpoint |

Todas as operações devem executar em transação e preservar timestamps.

## Auditoria e entregas

webhook_audit_logs registra criação, atualização, inativação, revelação e
rotação de segredo. webhook_delivery_attempts registra entregas reais e de
teste, incluindo order_id, is_test, código HTTP, duração e resposta truncada.

## Contrato de autenticação planejado

~~~~text
Content-Type: application/json
X-Lowify-Event: sale.paid
X-Lowify-Timestamp: <ISO-8601>
X-Lowify-Signature: sha256=<HMAC_SHA256 do corpo bruto>
~~~~

O consumidor recalcula o HMAC com o segredo ativo. O timestamp deve ser usado
para rejeitar entregas fora da janela permitida. Este contrato ainda é
planejado: o worker legado envia Content-Type e Idempotency-Key, sem assinatura
por segredo.

## Migração

1. Criar um endpoint único por user_id + webhook_url.
2. Adicionar endpoint_id em product_webhooks e preencher cada linha com o
   endpoint correspondente.
3. Preservar offer_id existente; offer_id NULL continua significando todas as
   ofertas.
4. Adicionar status e deleted_at sem remover registros existentes.
5. Gerar um segredo cifrado ativo por endpoint.
6. Migrar o dispatcher para selecionar por endpoint_id e ignorar vínculos e
   endpoints inativos.

Durante a transição, webhook_url permanece em product_webhooks para
compatibilidade de leitura. Sua remoção só pode ocorrer após dupla escrita,
validação das entregas e um rollback aprovado.

## Interface planejada

- **Webhook**: painel Endpoints, com URL, badges de eventos e uma ação para
  abrir.
- **Detalhes de endpoint**: visão geral com URL e segredo; painel de eventos
  em abas, cada qual com produto, oferta e ações.
- **Ofertas**: badge Todas quando offer_id for NULL; caso contrário, nome da
  oferta.
- **Documentação**: página corrida em Markdown, com payload, autenticação e
  ação para copiar o prompt de integração.

## Pendências

- Definir o serviço responsável pela entrega assinada e pelas tentativas.
- Definir retenção de logs de entrega e resposta HTTP.
- Definir o gancho transacional que inativa webhooks quando uma oferta é
  removida.
- Planejar o rollout sem coexistência ambígua entre o worker legado e o caminho
  de eventos ativo.
