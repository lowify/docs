# Arquitetura, fila e contrato alvo

## Fila e configuração propostas

Criar configuração dedicada, por exemplo `config/autoload/subscription_actions.php`, com:

- `SUBSCRIPTION_ACTIONS_PROCESS_ENABLED=true`
- `SUBSCRIPTION_ACTIONS_QUEUE=sales:subscriptions:actions`
- `SUBSCRIPTION_ACTIONS_TIMEOUT_SECONDS=5`

O processo deve estender `Hyperf\Process\AbstractProcess`, ter nome operacional explícito, usar `RedisFactory->get('default')`, consumir via `BLPOP` e ser registrado em `config/autoload/processes.php`, como os demais processos do Commerce V2. O valor efetivo da fila deve ser validado como não vazio na construção do processo.

## Envelope recomendado

O Banking deve publicar um evento por transição relevante, em vez de reutilizar o envelope de múltiplas `instructions` do legado:

```json
{
  "event_id": "uuid-gerado-no-produtor",
  "event": "subscription.charge.paid",
  "occurred_at": "2026-09-04T12:34:56+00:00",
  "correlation_id": "id-da-assinatura-no-provedor",
  "installment_number": 2,
  "end_to_end_id": "E2E-obrigatorio",
  "paid_at": "2026-09-04T12:34:56+00:00"
}
```

Para mudanças de status da assinatura, usar um evento separado, por exemplo `subscription.status.updated`, com `correlation_id`, `status`, `occurred_at` e `event_id`. Campos desconhecidos devem ser ignorados; campos obrigatórios e tipos devem ser validados antes de efeitos persistentes.

`event_id` permite auditoria e deduplicação de entrega. Para `subscription.charge.paid`, `correlation_id`, `installment_number` positivo e `end_to_end_id` não vazio são obrigatórios.

## Compensação local proposta

```text
SubscriptionActionsProcess
  -> SubscriptionActionMessage (validação/normalização)
  -> ProcessSubscriptionChargePaidUseCase (transação)
       -> localiza assinatura por correlation_id
       -> cria ou confirma parcela idempotentemente
       -> atualiza valid_until somente para frente
       -> parcela 1: aprova venda original
       -> parcela > 1: cria/encontra venda recorrente determinística e a aprova
  -> ProcessPaidSaleEventUseCase
       -> ativação, financeiro, entrega, integrações, notificações e contadores
```

A aprovação não deve reimplementar efeitos já tratados em `ProcessPaidSaleEventUseCase`. O novo caso de uso prepara a venda correta e então invoca integralmente esse fluxo, inclusive para recorrências. A implementação precisa checar a semântica de venda de checkout transparente antes de disparar transferências.

## Idempotência e consistência

1. Localizar e reutilizar a estrutura de parcelas já existente; criar migration aditiva somente se faltarem chaves únicas em `(subscription_id, installment_number)` ou, quando aplicável, em `end_to_end_id`.
2. Persistir uma chave de deduplicação de evento, ou garantir que as chaves únicas e a busca de venda recorrente por transação determinística cubram reentrega do mesmo evento.
3. Executar em uma transação de banco a parcela, a validade e a criação/associação da venda recorrente. Não marcar uma mensagem como concluída antes desses efeitos.
4. `ProcessPaidSaleEventUseCase` já tolera venda paga na ativação; ainda assim, as filas que ele dispara devem ser auditadas para garantir que a reentrega não duplique financeiro, entrega, integrações ou notificações.
5. Mensagem inválida deve gerar log estruturado e ser descartada de modo explícito. Falha transitória deve ser observável e ter política definida de retry/DLQ; uma lista Redis com `BLPOP` não oferece confirmação nativa.

## Decisão operacional pendente: retry/DLQ

Antes de implementar, escolher e documentar uma das opções:

- mover a mensagem para uma fila de retry com contador e atraso, e depois para uma DLQ; ou
- migrar este consumidor para Redis Streams/grupo de consumidores, com ack e pendências.

A recomendação inicial é manter Redis list para compatibilidade com os processos V2 atuais, mas adicionar filas explícitas de retry e DLQ. Sem isso, um erro depois do `BLPOP` pode perder a mensagem, que é precisamente o risco que a migração pretende reduzir.
