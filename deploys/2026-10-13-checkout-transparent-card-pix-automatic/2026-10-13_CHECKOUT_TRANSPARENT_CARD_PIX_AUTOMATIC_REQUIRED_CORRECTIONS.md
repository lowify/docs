# Checkout Transparente — correções necessárias antes da liberação

Este documento reúne exclusivamente as correções encontradas na revisão atual do fluxo entre Checkout Transparente (CT), Edge e Commerce V2. Ele não substitui o roteiro de deploy nem reabre decisões já aceitas para operação, como reprocessar um webhook bruto já persistido.

## Escopo e regra financeira confirmada

| Cenário | Efeito exigido após pagamento confirmado |
| --- | --- |
| Venda fora do CT | O Commerce V2 deve publicar o crédito líquido do seller na Wallet, com referência única da venda. |
| Cobrança avulsa CT | O CT deve gerar os itens de faturamento das taxas da cobrança uma única vez. |
| Parcela de Pix Automático CT | O CT deve gerar os itens de faturamento das taxas daquela parcela uma única vez, e o Commerce V2 deve criar/refletir a venda recorrente correspondente. |

O crédito do seller e o faturamento de taxa CT são efeitos distintos: no fluxo CT não se deve disparar o crédito normal da Wallet pelo `ProcessPaidSaleEventTransferUseCase`; o CT gera o item de billing. Essa separação já existe no desenho atual.

## Correções obrigatórias

### RC01 — usar uma identidade externa única por pagamento recorrente

**Problema confirmado.** A CT API envia `subscription.charge.paid` ao Commerce usando a referência estável da assinatura como `reference_id`/`correlation_id`. O edge registra o webhook com esse mesmo valor como `external_event_id`. Como a deduplicação é por identificador + `external_event_id`, a primeira parcela é aceita e as seguintes da mesma assinatura podem ser tratadas como duplicadas antes de entrarem na fila `sales:subscriptions:actions`.

**Correção necessária.** Construir o identificador externo do evento a partir de uma identidade de pagamento, no mínimo assinatura + `end_to_end_id` (ou um ID imutável de evento fornecido pelo provedor). A referência da assinatura deve continuar como correlação de negócio, não como identificador único do evento.

**Aceite mínimo.**

- Duas parcelas da mesma assinatura, com `end_to_end_id` distintos, chegam ao consumidor e criam/refletem duas vendas recorrentes.
- A reentrega da mesma parcela não cria nova venda, novo acesso, nova entrega nem novo item de faturamento.
- A mensagem persistida no webhook continua suficiente para reprocessamento operacional.

**Impacto financeiro.** A CT pode publicar o item de billing da parcela mesmo quando o edge responder sucesso para um evento deduplicado e o Commerce V2 não criar a venda recorrente. Sem esta correção, é possível faturar taxa do seller por uma recorrência que não foi refletida como venda/acesso no Commerce.

### RC02 — sincronizar cancelamento e impedir reativação por pagamento tardio

**Problema confirmado.** O cancelamento é gravado apenas no CT. Não há ação de cancelamento equivalente para o Commerce V2. Uma confirmação tardia ainda pode gerar `subscription.payment.notify`; no Commerce V2, `ProcessSubscriptionChargePaidUseCase` muda a assinatura para `active` ao receber a parcela.

**Correção necessária.** Criar uma ação idempotente de cancelamento CT → edge → Commerce V2. O processamento de pagamento tardio pode ser registrado para auditoria/reconciliação, mas não pode reativar assinatura cancelada, liberar acesso, criar venda recorrente, entregar produto ou agendar nova cobrança sem uma reativação explícita autorizada.

**Aceite mínimo.**

- Cancelar uma assinatura e reenviar o cancelamento não produz efeitos adicionais.
- Confirmar uma parcela após o cancelamento preserva o estado `canceled` nos dois lados.
- Não há nova venda, acesso, entrega, notificação de venda aprovada ou cobrança futura causada por esse pagamento tardio.

### RC03 — preservar o rate limit de falhas de cartão no caminho CT

**Problema confirmado.** O caminho normal do Commerce V2 aplica `CheckoutCardFailureRateLimitService` antes de criar pagamento e registra falhas de cartão. O caminho CT novo não preserva esse mesmo ciclo: a tentativa é executada no CT, mas a recusa do provedor não alimenta o limitador comercial do Commerce V2.

**Correção necessária.** Definir uma identidade segura da tentativa (seller/cliente/produto ou a chave comercial já adotada) e registrar a recusa CT no mecanismo que bloqueia novas tentativas. Manter também o rate limit por IP: a Public API deve resolver o IP real do comprador na borda confiável e encaminhá-lo ao CT API no contrato interno da tentativa; o CT API aplica o limite antes de chamar o provedor. O CT API não deve confiar em `X-Forwarded-For` ou cabeçalho equivalente enviado diretamente pelo navegador. Nenhum dos limites pode usar PAN, CVV ou o envelope de cartão como chave ou histórico.

**Aceite mínimo.**

- Recusas sucessivas CT alcançam o limite e uma tentativa adicional é bloqueada antes de chamar o provedor.
- Muitas tentativas de IPs distintos para o mesmo contexto comercial atingem o limite comercial; muitas tentativas de um mesmo IP também atingem o limite de IP.
- O IP efetivo é resolvido pela Public API a partir de proxy confiável e chega ao CT API no payload interno; um cabeçalho forjado pelo navegador não muda a chave de limitação.
- Uma aprovação e as regras de expiração/reabilitação seguem a política já usada pelo checkout normal.
- Nenhum dado sensível de cartão é persistido ou enviado entre filas para suportar o limite.

### RC04 — tornar idempotente a criação inicial de Pix Automático

**Problema confirmado.** A deduplicação de venda pendente de 20 horas no Commerce V2 cobre Pix comum e cartão CT, mas não `pix_automatic`. A referência de assinatura é a identidade pretendida, porém ainda precisa haver proteção explícita contra reenvio/concorrência da criação inicial antes de surgirem duas vendas ou duas assinaturas locais.

**Correção necessária.** Usar uma chave idempotente estável para a criação inicial e garantir atomicamente a relação compra → venda pendente → assinatura CT. Se uma chamada for repetida, retornar a mesma venda/referência, sem criar nova assinatura, nova autorização ou nova operação no provedor.

**Aceite mínimo.**

- Dois submits simultâneos da mesma intenção resultam em uma venda local, uma assinatura local e uma autorização/cobrança no provedor.
- Um timeout após sucesso pode ser repetido e devolve o resultado já criado.
- Falha antes da criação no CT não deixa pendência sem reconciliação; a recuperação a conclui ou a expira de forma rastreável.

### RC05 — garantir consistência entre venda recorrente e item de billing CT

**Problema confirmado.** O CT publica o item de billing de uma parcela após a notificação HTTP ao Commerce. Uma resposta HTTP de aceite não prova que a venda recorrente foi efetivamente processada na fila. RC01 é a causa hoje identificada, mas a consistência precisa permanecer protegida também para falhas futuras de consumidor/reprocessamento.

**Correção necessária.** Definir um vínculo verificável entre a parcela CT, a venda recorrente Commerce e o item de billing. O faturamento deve ser recuperável e idempotente, sem depender apenas de um `2xx` do edge como prova de que a venda foi criada. A implementação pode usar confirmação posterior/reconciliação; não deve bloquear o recebimento do pagamento do comprador.

**Aceite mínimo.**

- Para cada parcela paga há, no máximo, uma venda recorrente e um conjunto de itens de billing da parcela.
- Não é possível manter item de billing de uma parcela cuja venda recorrente esteja ausente sem gerar alerta/reconciliação.
- Reprocessar CT, edge, Commerce ou Billing converge para o mesmo estado.

## Ordem recomendada

1. RC01 e RC02, pois corrigem criação/reativação indevida de vendas, acesso e recorrência.
2. RC05 junto de RC01, para impedir divergência financeira entre CT e Commerce.
3. RC03 antes de habilitar cartão CT para sellers.
4. RC04 antes de liberar Pix Automático para tráfego real.

