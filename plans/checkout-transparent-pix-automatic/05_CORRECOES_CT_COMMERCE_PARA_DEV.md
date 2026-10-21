# Correções CT + Commerce V2 — briefing para implementação

## Objetivo

Corrigir as inconsistências encontradas no fluxo de Pix Automático e cartão do Checkout Transparente antes da liberação. Este documento é o ponto de partida para desenvolvimento; não é um roteiro de deploy.

## Escopo obrigatório

| ID | Correção | Componentes prováveis |
| --- | --- | --- |
| RC01 | Identidade única de cada pagamento recorrente | CT API, edge-webhook, Commerce V2 |
| RC02 | Cancelamento sincronizado e pagamento tardio sem reativação | CT API, edge-webhook, Commerce V2 |
| RC03 | Rate limit comercial e por IP para cartão CT | Public API, CT API, Commerce V2 se reutilizar o limitador existente |
| RC04 | Idempotência da criação inicial de Pix Automático | Public API, Commerce V2, CT API |
| RC05 | Consistência entre parcela paga, venda recorrente e billing CT | CT API, Billing, edge-webhook, Commerce V2 |

## RC01 — evento único por parcela recorrente

### Falha atual

O CT usa a referência estável da assinatura como `reference_id`/`correlation_id` ao enviar `subscription.charge.paid`. O edge-webhook usa essa referência como `external_event_id` e deduplica por ela. A primeira parcela entra; parcelas posteriores da mesma assinatura podem ser descartadas antes da fila `sales:subscriptions:actions`.

### Implementar

- Preservar a referência da assinatura como correlação de negócio.
- Introduzir um ID externo único por pagamento, baseado no mínimo em assinatura + `end_to_end_id`, ou em um ID imutável de evento do provedor.
- Transportar esse ID explicitamente no contrato CT → edge-webhook.
- Deduplicar reentregas da mesma parcela, mas nunca pagamentos diferentes da mesma assinatura.

### Aceite

1. Duas parcelas da mesma assinatura, com E2E distintos, geram duas ações no Commerce V2.
2. Reenviar cada parcela não cria segunda venda, acesso, entrega ou billing.

## RC02 — cancelamento é definitivo até reativação explícita

### Falha atual

O CT cancela a assinatura local, mas não envia cancelamento ao Commerce V2. Uma confirmação tardia ainda pode ser publicada e o Commerce V2 altera a assinatura de volta para `active`.

### Implementar

- Criar ação idempotente de cancelamento CT → edge-webhook → Commerce V2.
- Ao receber pagamento tardio de assinatura cancelada, manter ambos os lados em `canceled`.
- Se o histórico financeiro precisar ser guardado, fazê-lo sem criar venda recorrente, acesso, entrega, notificação de venda aprovada ou próxima cobrança.
- Impedir que operações pendentes de criação/agendamento prossigam depois do cancelamento.

### Aceite

1. Cancelamento repetido não tem efeito duplicado.
2. Cancelar e depois confirmar pagamento tardio mantém CT e Commerce V2 cancelados.
3. Nenhuma venda, acesso, entrega ou cobrança futura é criada pelo pagamento tardio.

## RC03 — rate limit de cartão por contexto comercial e por IP

### Falha atual

O checkout normal aplica `CheckoutCardFailureRateLimitService` e registra recusas. No CT, a tentativa é executada no CT API e as recusas não preservam esse mesmo controle. Também é necessário limitar abuso por IP.

### Implementar

- Manter o limite comercial de falhas por contexto seguro da tentativa (seller/cliente/produto, conforme política existente), sem PAN, CVV, token ou envelope de cartão na chave.
- A Public API resolve o IP efetivo do comprador em proxy/borda confiável e o encaminha no contrato interno para o CT API.
- O CT API aplica rate limit por IP antes de chamar o provedor.
- Não usar `X-Forwarded-For` recebido diretamente do navegador como fonte confiável.
- Registrar recusa CT no limitador; aprovação e expiração devem seguir a política já adotada no checkout normal.

### Aceite

1. Recusas repetidas no mesmo contexto comercial são bloqueadas antes do provedor.
2. Muitas tentativas de um mesmo IP são bloqueadas mesmo variando o contexto comercial.
3. Header de IP forjado pelo navegador não altera a chave aplicada pelo CT API.
4. Nenhum dado de cartão é persistido ou publicado em fila para suportar o limitador.

## RC04 — uma adesão inicial de Pix Automático por intenção de compra

### Falha atual

Ao contrário de Pix comum e cartão CT, a criação inicial de `pix_automatic` não possui deduplicação temporal explícita no Commerce V2. Reenvio, timeout ou duas abas podem criar mais de uma pendência/assinatura.

### Implementar

- Definir chave idempotente estável para a intenção de adesão.
- Garantir atomicamente a relação intenção → venda pendente → assinatura local → criação no CT/provedor.
- Em repetição, devolver a mesma venda/referência sem criar autorização ou cobrança adicional.

### Aceite

1. Dois submits simultâneos resultam em uma venda local, uma assinatura local e uma autorização/cobrança no provedor.
2. Repetir após timeout devolve o resultado já criado.

## RC05 — parcela, venda recorrente e billing devem convergir

### Falha atual

O CT publica os itens de billing depois de o edge aceitar a notificação de pagamento. Um `2xx` do edge não comprova que o consumidor do Commerce V2 criou a venda recorrente. Hoje RC01 pode causar justamente essa divergência: existe taxa de billing sem a venda/acesso correspondente.

### Implementar

- Vincular de maneira consultável a parcela CT, a venda recorrente do Commerce V2 e os itens de billing da parcela.
- Não usar apenas o `2xx` do edge como prova final de venda criada.
- Criar reconciliação/alerta idempotente para parcela com billing e sem venda recorrente, ou venda recorrente sem efeito financeiro esperado.
- Preservar a unicidade atual de billing por `subscription_charge` e a unicidade de venda por pagamento.

### Aceite

1. Para cada parcela paga existem, no máximo, uma venda recorrente e um conjunto de itens de billing.
2. Um item de billing sem venda correspondente é detectado e reconciliado/alertado.
3. Reprocessar CT, edge, Commerce ou Billing converge para o mesmo estado.

## Fora deste corte

A reconciliação automática de uma criação externa cuja resposta se perdeu é uma evolução futura. Ela não autoriza reenviar criação de autorização ou cobrança sem antes consultar o provedor.

## Entrega esperada

- Alterações e migrations novas quando necessárias; não reescrever migrations já aplicadas.
- Testes focados ou evidência técnica dos critérios de aceite acima.
- Contratos de HTTP/fila compatíveis entre CT API, edges, Commerce V2 e Billing.
- Sem dados sensíveis de cartão em logs, banco, payloads ou chaves de rate limit.
