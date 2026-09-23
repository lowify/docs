# Implementação e aceite

## Ordem proposta

1. Fechar o modelo de assinatura CT, a criação em duas etapas com Commerce V2 e o contrato de evento de parcela paga.
2. Estender disponibilidade, cadastro e Dashboard para `pix_automatic` somente em Woovi e Efí.
3. Implementar Woovi: criação de mandato, webhooks, estados, faturamento e entrega da parcela paga ao Commerce V2.
4. Implementar Efí: criação de recorrência, scheduler idempotente de `cobr`, consulta, atualizações, faturamento e entrega da parcela paga ao Commerce V2.
5. Adicionar cancelamento do mandato pelo seller e reconciliação de assinaturas e cobranças pendentes.

## Casos de aceite

| Caso | Resultado esperado |
| --- | --- |
| Produto `SUBSCRIPTION` sem integração elegível | `pix_automatic` não aparece nem é aceito. |
| Produto `SUBSCRIPTION` com Woovi ou Efí ativa | Venda pendente e mandato são criados uma única vez. |
| Mandato recusado ou cancelado | Assinatura local acompanha o estado; nenhuma venda é entregue. |
| Primeira parcela paga | A venda inicial, a entrega e o faturamento ocorrem uma única vez. |
| Parcela futura paga | Uma venda recorrente, a entrega e o faturamento ocorrem uma única vez. |
| Reentrega de webhook ou polling | Não duplica parcela, venda, entrega ou efeito financeiro. |
| Efí sem nova cobrança programada | Reconciliação detecta e programa a parcela faltante uma única vez. |
| Woovi sem endereço válido | O checkout bloqueia a criação antes de chamar o provedor. |
| Troca de integração padrão | Assinaturas já ativas continuam usando a integração que autorizou o mandato. |

## Fora do primeiro corte

- Valor variável, juros, multa e retentativas configuráveis por seller.
- Migração de assinaturas existentes entre o checkout comum e o Transparente.
- Habilitar um provedor sem homologação do mandato, cancelamento, primeira parcela e renovação.
