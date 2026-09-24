# Implementação e aceite

## Ordem proposta

1. Fechar o modelo de assinatura do Checkout Transparente, a criação provisória do mandato, o vínculo em duas etapas com Commerce V2 e o contrato de evento de parcela paga.
2. Estender disponibilidade, cadastro e Dashboard para `pix_automatic` somente em Woovi e Efí.
3. Implementar Woovi: criação de mandato, webhooks, estados, faturamento e entrega da parcela paga ao Commerce V2.
4. Implementar Efí: validar escopos de Pix Automático, registrar `webhookrec` e `webhookcobr`, criar recorrência, scheduler idempotente de `cobr`, consulta, atualizações, faturamento e entrega da parcela paga ao Commerce V2.
5. Adicionar monitoramento do cadastro de webhooks para Woovi e Efí; na Woovi, incluir a reconciliação limitada de assinaturas atrasadas e o tratamento de integração degradada.
6. Adicionar cancelamento do mandato pelo seller e reconciliação de assinaturas e cobranças pendentes.
7. Definir a jornada da primeira cobrança e a regra recorrente de oferta, desconto e bump antes de habilitar o método.

## Casos de aceite

| Caso | Resultado esperado |
| --- | --- |
| Produto `SUBSCRIPTION` sem integração elegível | `pix_automatic` não aparece nem é aceito. |
| Produto `SUBSCRIPTION` com Woovi ou Efí ativa | Venda pendente e mandato são criados uma única vez. |
| Requisição repetida ou resposta externa incerta | Não cria dois mandatos; o registro provisório permite retomar ou reconciliar a criação. |
| Mandato recusado ou cancelado | Assinatura local acompanha o estado; nenhuma venda é entregue. |
| Primeira parcela paga | A venda inicial, a entrega e o faturamento ocorrem uma única vez. |
| Parcela futura paga | Uma venda recorrente, a entrega e o faturamento ocorrem uma única vez. |
| Reentrega de webhook ou polling | Não duplica parcela, venda, entrega ou efeito financeiro. |
| Efí sem nova cobrança programada | Reconciliação detecta e programa a parcela faltante uma única vez. |
| Jornada Efí escolhida | A primeira cobrança acontece no momento definido para o produto: futura ou imediata com recorrência. |
| Troca de integração padrão | Assinaturas já ativas continuam usando a integração que autorizou o mandato. |
| Webhook Woovi removido pelo seller | O monitor detecta a divergência, marca a integração como degradada e recria o registro quando a credencial continua válida. |
| Evento Woovi não entregue | A reconciliação encontra a parcela terminal, publica seus efeitos uma única vez e registra o atraso. |
| AppID Woovi revogado ou inválido | O método deixa de aceitar novas adesões e a integração informa necessidade de correção da credencial. |
| Callback Efí removido ou alterado pelo seller | O monitor detecta a divergência e tenta restaurar o cadastro quando a credencial continua válida. |
| Efí sem scheduler, certificado ou credencial funcional | Nenhuma `cobr` futura é criada; a assinatura fica identificada como degradada e a recuperação não duplica uma cobrança já criada. |
| Callback Efí | Os dois endpoints de Pix Automático passam pela validação mTLS e preservam a rota configurada. |
| Bump ou desconto no produto de assinatura | O valor de cada parcela segue a política definida, sem aplicar ou remover itens por acidente. |

## Fora do primeiro corte

- Valor variável, juros, multa e retentativas configuráveis por seller.
- Migração de assinaturas existentes entre o checkout comum e o Transparente.
- Habilitar um provedor sem homologação do mandato, cancelamento, primeira parcela e renovação.
