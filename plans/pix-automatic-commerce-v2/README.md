# Migração de assinaturas PIX Automático para Commerce V2

## Objetivo

Transferir o processamento assíncrono de assinaturas e cobranças PIX Automático do Commerce legado para o `services-commerce-v2`. O Banking continuará sendo a origem dos eventos confirmados pelo provedor, mas passará a publicar uma nova fila consumida por um `Process` do Commerce V2. A compensação de venda, validade e efeitos posteriores ocorrerá no próprio container do Commerce V2, sem encaminhamento à fila/processo do `dashboard-seller`.

## Estado

Planejamento iniciado em 2026-09-04. Nenhuma alteração de código, migration, contrato de produtor ou configuração foi implementada por este plano.

## Documentos

1. [Estado atual e fronteiras](01_ESTADO_ATUAL_E_FRONTEIRAS.md)
2. [Arquitetura, fila e contrato alvo](02_ARQUITETURA_E_CONTRATO_ALVO.md)
3. [Implementação, rollout e rollback](03_IMPLEMENTACAO_ROLLOUT_E_ROLLBACK.md)
4. [Aceite, observabilidade e tarefas](04_ACEITE_OBSERVABILIDADE_E_TASKS.md)

## Decisões propostas

| Tema | Proposta |
| --- | --- |
| Fila legada | `commerce:subscriptions:actions` continua sendo consumida exclusivamente para drenar mensagens já publicadas. O Banking deixa de publicá-la no corte. |
| Nova fila | Usar `sales:subscriptions:actions`, configurável por ambiente no Commerce V2. O nome segue o padrão atual de filas de domínio do serviço (`sales:*`) e não reutiliza a fila legada. |
| Produtor | O Banking publica o novo contrato somente após persistir a mudança de estado da assinatura/cobrança. |
| Consumidor | Criar um `AbstractProcess` registrado em `config/autoload/processes.php`, configurável e com `BLPOP`, no padrão dos processos atuais do Commerce V2. |
| Compensação | O processo chama casos de uso/repositórios do Commerce V2 para registrar a parcela, ativar a primeira venda, clonar/aprovar recorrências, atualizar validade e disparar os efeitos de venda paga já centralizados no serviço. |
| Dashboard Seller | Não publicar `commerce:sales:actions` nem depender de `dashboard-seller/scripts/queues/commerce_sales_actions_worker.php` para esse caminho novo. |
| Idempotência | A identidade de processamento é a assinatura + número da parcela, com `end_to_end_id` como identificador de pagamento. A persistência deve impedir parcela/venda/efeitos duplicados em reentregas. |

## Fluxo alvo

```text
Woovi/provedor
  -> Banking processa e persiste assinatura/cobrança
  -> Redis list sales:subscriptions:actions
  -> Commerce V2 SubscriptionActionsProcess
  -> transação local: assinatura, parcela, venda e validade
  -> ProcessPaidSaleEventUseCase / filas internas já existentes
  -> entrega, integrações, notificações e financeiro do Commerce V2
```

## Fora do escopo desta entrega

- Migrar dados históricos entre os bancos ou reprocessar automaticamente todas as mensagens antigas.
- Desativar ou remover o worker/fila do Commerce legado antes de comprovada a drenagem.
- Alterar criação de assinatura no checkout, contrato público de checkout ou o provedor PIX Automático além do necessário para trocar a publicação da fila.
- Remover o `dashboard-seller` de fluxos não relacionados a assinaturas PIX Automático.
