# Implementação e aceite

## Ordem proposta

1. Fechar o agregado de assinatura: registro provisório da autorização recorrente, criação externa idempotente, vínculo em duas etapas com Commerce V2 e contrato de evento de parcela paga.
2. Estender disponibilidade, cadastro e Dashboard para `pix_automatic` somente em Woovi e Efí.
3. Implementar Woovi: criação de autorização recorrente, webhooks, estados, faturamento e entrega da parcela paga ao Commerce V2.
4. Implementar Efí: validar escopos de Pix Automático, registrar `webhookrec` e `webhookcobr`, criar autorização recorrente, scheduler idempotente de `cobr`, polls diretos, faturamento e entrega da parcela paga ao Commerce V2.
5. Adicionar monitoramento do cadastro de webhooks para Woovi e Efí. Na Efí, implementar polls por `idRec` e `txid`; na Woovi, incluir reconciliação limitada de assinaturas atrasadas e estado de integração degradada.
6. Adicionar cancelamento pelo seller e reconciliação de autorizações e cobranças pendentes.
7. Definir a jornada da primeira cobrança e a regra recorrente de oferta, desconto e bump antes de habilitar o método.

## Casos de aceite

| Caso | Resultado esperado |
| --- | --- |
| Produto `SUBSCRIPTION` sem integração elegível | `pix_automatic` não aparece nem é aceito. |
| Produto `SUBSCRIPTION` com Woovi ou Efí ativa | Venda pendente e autorização recorrente são criadas uma única vez. |
| Requisição repetida ou resposta externa incerta | Não cria duas autorizações; o registro provisório permite retomar ou reconciliar a criação. |
| Autorização recorrente recusada ou cancelada | Assinatura local acompanha o estado; nenhuma venda é entregue. |
| Primeira parcela paga | A venda inicial, a entrega e o faturamento ocorrem uma única vez. |
| Parcela futura paga | Uma venda recorrente, a entrega e o faturamento ocorrem uma única vez. |
| Reentrega de webhook ou poll | Não duplica parcela, venda, entrega ou efeito financeiro. |
| Efí sem nova cobrança programada | A verificação encontra a parcela faltante e a programa uma única vez. |
| Jornada Efí escolhida | A primeira cobrança acontece no momento definido para o produto: futura ou imediata com recorrência. |
| Troca de integração padrão | Assinaturas já ativas continuam usando a integração que criou a autorização do cliente. |
| Webhook Woovi removido pelo seller | O monitor percebe que o provedor não aponta mais para a Lowify, marca a integração com problema e tenta restaurar o cadastro quando a credencial continua válida. |
| Evento Woovi não entregue | A verificação encontra o pagamento ou cancelamento, aplica seus efeitos uma única vez e registra o atraso. |
| AppID Woovi revogado ou inválido | O método deixa de aceitar novas adesões e a integração informa necessidade de correção da credencial. |
| Callback Efí removido ou alterado pelo seller | O monitor percebe a divergência e tenta restaurar o cadastro quando a credencial continua válida. |
| Credencial, escopo ou certificado Efí removido pelo seller | Novas adesões e renovações ficam bloqueadas; o método informa a correção necessária sem criar efeito local parcial. |
| `rec` ou `cobr` Efí cancelada fora da Lowify | O poll direto por `idRec` ou `txid` atualiza o estado local antes de uma nova entrega ou renovação. |
| Chave Pix Efí removida ou substituída | Homologação comprova o efeito sobre autorizações, cobranças e callbacks existentes antes da ativação do método. |
| Poll Efí | Consulta cada autorização por `idRec` e cada cobrança por `txid`; não depende de ordenação ou do primeiro item de uma listagem. |
| Efí sem scheduler, certificado ou credencial funcional | Nenhuma `cobr` futura é criada; a assinatura fica marcada com problema e a recuperação não duplica uma cobrança já criada. |
| Callback Efí | Os dois endpoints de Pix Automático passam pela validação mTLS e preservam a rota configurada. |
| Bump ou desconto no produto de assinatura | O valor de cada parcela segue a política definida, sem aplicar ou remover itens por acidente. |

## Fora do primeiro corte

- Valor variável, juros, multa e retentativas configuráveis por seller.
- Migração de assinaturas existentes entre o checkout comum e o Transparente.
- Habilitar um provedor sem homologação da autorização, cancelamento, primeira parcela e renovação.
