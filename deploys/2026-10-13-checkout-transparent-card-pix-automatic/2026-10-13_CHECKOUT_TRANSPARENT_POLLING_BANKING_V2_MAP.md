# CT — mapa do polling Banking V2 e adaptação por conta

Data: 2026-10-13. Pedido: mapear o padrão Banking V2 para ajustar o CT, sem implementar serviços neste passo.

Referência examinada: `services-banking-v2/main`, commit `112062fcbb1d20dde6a72f7f6300cd4a7629ee59`; worktree limpo e `origin/main` no mesmo commit. CT: versões da feature registradas no [roteiro de revisão](2026-10-13_CHECKOUT_TRANSPARENT_CARD_PIX_AUTOMATIC_REVIEW.md).

## 1. O que o Banking V2 faz hoje

Há duas rotinas complementares, e não uma única rotina que consulta cada cobrança local.

| Rotina | Consulta / processamento | Controle de progresso |
| --- | --- | --- |
| `EfiBankCashInPollingProcess` | Chama `EfiBankCashInReconciler`, que pagina `GET /v2/pix` para listar recebimentos no intervalo. Publica em `dashboard:cashing:events`. | Redis: `banking:efi:cash-in:poll:last-end-utc`; cursor atualizado depois que o reconciler retorna. |
| `EfiBankPixAutomaticPollingProcess` | Consulta listas `GET /v2/cobr` e `GET /v2/rec`; relaciona `idRec` com assinatura local e publica em `banking:subscriptions:actions`. | Redis: cursores independentes `banking:efi:pix-automatic:poll:cobr:cursor` e `...:rec:cursor`; avança depois de enfileirar os itens do intervalo. |

Esses processos usam o cliente Efí configurado no serviço. `EfiBankClientBase` recebe as opções de credenciais/certificado da configuração; os processos não iteram sellers ou integrações. O padrão é consulta pela conta configurada, mas a seleção de múltiplas contas de sellers precisa ser acrescentada no CT.

### Recebimentos Pix

1. Processo habilitado pela configuração `efibank_cash_in_polling` (configuração padrão habilitada; isso não comprova o valor efetivo do ambiente).
2. Intervalo padrão de 60 segundos; lock Redis `SET NX EX`, com TTL de pelo menos 120 segundos ou duas vezes o intervalo.
3. Primeira rodada parte de `now - 5 minutes`, salvo configuração diferente. Nas seguintes, parte do último fim menos 60 segundos de sobreposição.
4. O reconciler consulta todas as páginas de até 100 itens, usando `paginacao.paginaAtual` e `paginacao.itensPorPagina`.
5. Descarta registros sem txid e repetições de txid dentro daquela execução (`seenTxids`). Essa deduplicação é temporária, não garante deduplicação entre rodadas ou com webhook.
6. Enfileira cada recebimento. Falha da consulta/publicação interrompe a execução; sem retorno completo do reconciler, o processo não grava o novo cursor.
7. Depois do retorno, grava o fim do intervalo no Redis.

### Autorizações e cobranças recorrentes

1. Processo habilitado por `EFIBANK_PIX_AUTOMATIC_POLLING_ENABLED`; padrão desabilitado. A configuração não prova que esteja executando em homologação/produção.
2. Intervalo padrão de 60 segundos e lock global Redis com TTL de 110 segundos.
3. Recuperação histórica começa em `2026-09-10 00:00:00 UTC`, com até 10 janelas de 60 minutos por execução.
4. Próximo do presente, usa janelas de 2 minutos, sobreposição de 60 segundos e limite superior de `now - 60 seconds`.
5. Se a resposta informar mais de uma página, reduz o intervalo pela metade e consulta novamente. Não percorre as páginas nessa rotina. Se ainda houver múltiplas páginas na janela mínima de 1 minuto, lança erro e não avança.
6. Só enfileira itens cujo `idRec` pertence a assinatura local (`findByCorrelationId(idRec, 3)`).
7. Para autorizações: `APROVADA → active`, `CRIADA → pending`, `REJEITADA → rejected`; demais estados caem em `canceled`.
8. Para parcelas: `CONCLUIDA → paid`, `EXPIRADA → expired`, `CRIADA/ATIVA → pending`; demais estados caem em `canceled`. O end-to-end é obtido das tentativas.
9. Publica em `banking:subscriptions:actions`, consumida por `SubscriptionActionsQueueProcess`. Esse consumidor usa `BLPOP` e retry em memória; não é um modelo de ACK durável a copiar sem ajustes.

## 2. O que aproveitar e o que não copiar literalmente

**Aproveitar:** consulta por conta e janela temporal; cursores separados por domínio; sobreposição para chegada tardia; bootstrap limitado; associação das operações externas com o banco local; normalização de eventos em um único caminho de aplicação.

**Melhorar no CT:**

- Escopo dos cursores/locks por provider, ambiente e conta/integração, nunca compartilhando estado entre sellers. Não gravar credenciais em nomes de chave ou logs.
- Paginação completa com limite de trabalho por rodada, em vez de falhar em conta com mais de 100 registros por minuto.
- Locks com token de propriedade e liberação condicional; TTL/renovação compatível com o tempo do lote.
- Persistência durável dos eventos recebidos antes de avançar o cursor; publicação em lista Redis não prova que a confirmação foi aplicada. Se o consumidor perder a mensagem após `BLPOP`, o cursor não volta automaticamente.
- Deduplicação persistente, por conta + ID da transação/evento, também entre polling e webhook. Não usar só `seenTxids` nem um lock com expiração.
- Estados desconhecidos não viram cancelamento. Em particular, expiração/inadimplência da parcela não cancela a assinatura. Regra do produto: somente cancelamento explícito.
- Confirmar a semântica de `inicio`/`fim` nas listas: criação, atualização ou recebimento. Uma autorização antiga cancelada hoje pode escapar se a consulta seleciona somente criações recentes. Manter consulta pontual/varredura de estados quando a listagem não oferece filtro de atualização adequado.

## 3. Adaptação proposta para CT

```text
Processo CT seleciona contas elegíveis com justiça
→ reserva conta + tipo de consulta
→ worker consulta provider com credenciais daquela integração
→ CT persiste resultados/eventos e progresso
→ aplicação idempotente de recebimento / cancelamento
→ Commerce e billing no evento correto
```

Preservar Redis/banco isolados do CT e o padrão existente de instruções de gateway. Não fazer o CT consumir as filas principais do Banking nem copiar suas credenciais globais.

### Três trilhas por conta

| Trilha | Finalidade | Identificação e aceite |
| --- | --- | --- |
| Recebimentos | Encontrar dinheiro efetivamente recebido, inclusive primeira cobrança Pix e pagamento de parcela antiga. Para Efí, adaptar a listagem `/v2/pix` já usada pelo Banking. | Correlacionar conta + txid/ID externo à parcela e deduplicar end-to-end. Cada pagamento elegível confirma a venda e gera billing uma vez. Sem correspondência, guardar pendência para reconciliação, sem atribuir ao seller errado. |
| Autorizações | Detectar aprovação, rejeição e cancelamento explícito. | Não confundir aprovação com pagamento nem ausência de recebimento com cancelamento. Consultar autorizações antigas quando necessário para recuperar mudança de estado. |
| Cobranças/recuperação pontual | Recuperar operação em estado desconhecido, parcela e criação parcial. | Inicial Efí usa `/v2/cob/{txid}`; recorrente usa `/v2/cobr/{txid}`. Listas são complemento; timeout não autoriza nova criação cega. |

Listar recebimentos resolve a recuperação de pagamento ausente, mas não resolve sozinho cadastro nunca enviado, recursos externos órfãos nem cancelamento. Esses problemas precisam de processos de recuperação e estado persistido próprios.

### Estado e justiça de execução

Proposta: persistir estado por conta/tipo com `last_successful_end`, `next_run_at`, cursor/página ou janela em curso, tentativas, erro seguro e lease. Índice orientado a `next_run_at`/conta para seleção; parâmetros finais dependem da query implementada.

Redis pode acelerar lock/agendamento, mas banco mantém checkpoints e unicidade para sobreviver a perda de cache. Avançar progresso apenas depois de persistir os itens retornados em uma inbox ou estrutura equivalente. Aplicação e publicação posterior podem ser retomadas por processo lendo essa estrutura.

Selecionar contas por próxima execução, com limite de páginas/tempo por conta; continuar a conta interrompida na próxima rodada e permitir progresso das demais. Uma conta volumosa ou indisponível não deve monopolizar o worker.

Uma integração desabilitada para novas vendas ainda pode ter obrigações abertas: continuar reconciliando pagamentos e cancelamentos das operações antigas com a conta original. Troca de gateway não migra assinatura automaticamente.

### Pagamento atrasado

Consultar recebimentos pelo horário do recebimento, não somente cobranças criadas/vencidas na janela recente. Um pagamento de parcela antiga encontrado hoje deve ser aplicado à parcela antiga, não à mais recente. Não alterar seu valor para o valor atual da assinatura.

A regra de negócio permite atraso sem cancelamento automático. Retentativas e formas efetivamente suportadas de pagamento tardio devem respeitar o contrato do provider; não presumir que débito automático possa ser repetido indefinidamente. Caso uma autorização deixe de ser tecnicamente utilizável, registrar motivo distinto de cancelamento por inadimplência e reconciliar o estado explicitamente informado.

## 4. Processo de recuperação lendo o banco

É viável usar um `Process` com o banco como fonte de trabalho, em vez de depender de uma lista Redis para lembrar operações pendentes. Precisa selecionar registros com estado recuperável e `next_retry_at`, reservá-los com lease/locking transacional, executar e gravar progresso/IDs antes de liberá-los.

Ele cobre cadastro salvo sem publicação, etapa interrompida e retomada após reinício. Operação com resultado desconhecido vai primeiro para consulta/reconciliação; não para nova cobrança. Para passos que exigem entrada sensível não persistida (ex.: CVV), não salvar esse dado para facilitar retry: solicitar nova entrada quando realmente necessário, sem duplicar a operação anterior.

Pode substituir a fila em partes do fluxo ou funcionar como recuperador da fila existente. Só adicionar um loop lendo `pending` sem reserva, checkpoints e idempotência não fecha o problema.

## 5. Roteiro de validação do ajuste

- Duas contas com txids semelhantes; resultado e cursor nunca se misturam.
- Mais de 100 recebimentos por minuto e múltiplas páginas: todos persistidos/aplicados, sem bloquear outras contas.
- Rodadas sobrepostas e webhook simultâneo: uma confirmação, uma venda e um billing por pagamento elegível.
- Reinício após consulta, durante paginação, após persistência e antes/depois da publicação: recuperação sem perda ou cobrança duplicada.
- Conta indisponível e retorno após horas: bootstrap retoma do checkpoint sem prejudicar contas saudáveis.
- Pagamento de parcela antiga recebido hoje: confirma a parcela correta e não cancela assinatura por atraso anterior.
- Cancelamento explícito de autorização antiga: detectado sem depender de criação recente; trava novos ciclos e não é revertido por pagamento atrasado.
- Rotação de credenciais da mesma conta e troca para outra conta: continuidade/novo checkpoint definidos, sem compartilhamento indevido.

Não executados: APIs financeiras, teste de carga, banco/Redis reais ou homologação. Este mapa foi produzido por leitura do código e dos contratos públicos.

## Evidências

- [Banking: recebimentos](https://github.com/lowify/services-banking-v2/blob/112062fcbb1d20dde6a72f7f6300cd4a7629ee59/app/Process/EfiBankCashInPollingProcess.php), [reconciler e paginação](https://github.com/lowify/services-banking-v2/blob/112062fcbb1d20dde6a72f7f6300cd4a7629ee59/app/Infrastructure/Services/EfiBankCashInReconciler.php) e [cliente Pix](https://github.com/lowify/services-banking-v2/blob/112062fcbb1d20dde6a72f7f6300cd4a7629ee59/app/Infrastructure/Gateways/EfiBank/Client/EfiBankPixClient.php).
- [Banking: Pix Automático](https://github.com/lowify/services-banking-v2/blob/112062fcbb1d20dde6a72f7f6300cd4a7629ee59/app/Process/EfiBankPixAutomaticPollingProcess.php), [cliente de recorrência](https://github.com/lowify/services-banking-v2/blob/112062fcbb1d20dde6a72f7f6300cd4a7629ee59/app/Infrastructure/Gateways/EfiBank/Client/EfiBankSubscriptionClient.php) e [escopo das credenciais](https://github.com/lowify/services-banking-v2/blob/112062fcbb1d20dde6a72f7f6300cd4a7629ee59/app/Infrastructure/Gateways/EfiBank/Client/EfiBankClientBase.php).
- Contratos: [Efí — recebimentos Pix](https://dev.efipay.com.br/docs/api-pix/gestao-de-pix/) e [autorizações/cobranças Pix Automático](https://dev.efipay.com.br/docs/api-pix/pix-automatico/). Confirmar a semântica temporal dos filtros e formas de atraso na homologação.
