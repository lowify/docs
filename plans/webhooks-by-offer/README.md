# Plano — Webhooks por endpoint, evento e oferta

> Status: planejado
> Última atualização: 2026-11-17
> Confiança: modelo atual confirmado; modelo alvo pendente de implementação

## Objetivo

Evoluir a configuração de webhooks para separar o cadastro do endpoint da
seleção de eventos, produtos e ofertas. O endpoint permanece auditável mesmo
quando não possui eventos ativos.

O escopo também prevê um segredo único ativo por endpoint, usado para
autenticar as entregas, e a interface de documentação do contrato.

## Estado atual confirmado

O modelo ativo usa product_webhooks, com uma linha por produto, URL e evento.
Na branch feat/webhooks-by-offer, o escopo de oferta é adicionado por offer_id
nullable:

~~~~text
product_webhooks
  user_id + product_id + offer_id? + event_type + webhook_url
~~~~

offer_id NULL significa todas as ofertas do produto. A referência de deploy e
o DDL confirmado estão em
deploys/2026-11-17-webhooks-by-offer/2026-11-17_WEBHOOKS_BY_OFFER_DEPLOY.md.

## Modelo alvo

~~~~text
webhook_endpoints
  ├─ webhook_endpoint_secrets
  └─ webhook_events
       └─ webhook_event_products
            └─ webhook_event_product_offers
~~~~

### webhook_endpoints

| Campo | Regra |
| --- | --- |
| id | identificador interno |
| user_id | dono do endpoint |
| name | nome editável apresentado na interface |
| url | URL de entrega |
| status, deleted_at | exclusão lógica |
| timestamps | auditoria de criação e alteração |

Não há remoção física pela aplicação. Apagar o endpoint apenas o inativa.

### webhook_endpoint_secrets

| Campo | Regra |
| --- | --- |
| id, endpoint_id | associação ao endpoint |
| secret_encrypted | segredo cifrado; nunca texto puro no banco |
| encryption_key_id | referência para rotação da chave de cifragem |
| status | apenas um registro ativo por endpoint |
| rotated_at, deleted_at | histórico |

Rotacionar cria uma nova versão ativa e inativa a anterior. O segredo é
usado para calcular a assinatura HMAC-SHA256 do corpo bruto.

### webhook_events

| Campo | Regra |
| --- | --- |
| endpoint_id | endpoint pai |
| event_type | sale.paid, sale.pending ou sale.refunded |
| status, deleted_at | inativação lógica |

Excluir um evento não exclui o endpoint.

### webhook_event_products

| Campo | Regra |
| --- | --- |
| webhook_event_id | evento pai |
| product_id | produto selecionado |
| all_offers | true para todas as ofertas |
| status, deleted_at | inativação lógica |

Cada vínculo representa um produto por vez dentro de um evento.

### webhook_event_product_offers

| Campo | Regra |
| --- | --- |
| webhook_event_product_id | vínculo produto × evento |
| offer_id | oferta específica |
| status, deleted_at | inativação lógica |

Esta tabela só é usada quando all_offers é false. Se uma oferta for apagada,
os vínculos específicos correspondentes devem ser inativados, preservando o
histórico.

### Auditoria e entregas

webhook_audit_logs registra alterações de endpoint, evento, produto, oferta e
segredo. webhook_delivery_attempts registra entregas reais e de teste,
incluindo order_id, is_test, código HTTP, duração e resposta truncada.

## Contrato de autenticação planejado

~~~~text
Content-Type: application/json
X-Lowify-Event: sale.paid
X-Lowify-Timestamp: <ISO-8601>
X-Lowify-Signature: sha256=<HMAC_SHA256 do corpo bruto>
~~~~

O consumidor recalcula o HMAC com o segredo ativo. O timestamp deve ser usado
para rejeitar entregas fora da janela permitida. O contrato é planejado: o
worker legado atual ainda envia apenas Content-Type e Idempotency-Key.

## Migração

1. Criar endpoints únicos por user_id + webhook_url.
2. Criar eventos únicos por endpoint_id + event_type.
3. Migrar cada produto atual para webhook_event_products com all_offers true.
4. Gerar um segredo cifrado ativo por endpoint.
5. Manter product_webhooks em leitura durante a transição; só removê-la após
   dupla escrita, validação de entregas e plano de rollback aprovado.

## Interface planejada

- **Webhook**: painel Endpoints, com nome, URL, badges dos eventos e uma ação
  para abrir.
- **Detalhes de endpoint**: visão geral com nome e segredo; painel de eventos
  em abas, cada qual com produto, ofertas e ações.
- **Documentação**: página corrida em Markdown, com contrato de payload e
  autenticação, além de ação para copiar o prompt de integração.

## Pendências

- Definir o serviço responsável pela entrega assinada e pela persistência de
  tentativas.
- Definir a política de revelação do segredo na interface.
- Definir retenção de logs de entrega e resposta HTTP.
- Planejar rollout sem coexistência ambígua entre o worker legado e o caminho
  de eventos ativo.
