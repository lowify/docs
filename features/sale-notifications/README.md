# Feature — comunicações de venda

> Status: em evolução
> Última atualização: 2026-10-13
> Confiança: parcialmente confirmada

## Objetivo

Unificar a entrega pós-compra e a recuperação de venda pendente (RDC) sob uma carteira de créditos monetários de comunicação. Há implementação parcial nas branches `feat/sale-notifications`; ela ainda requer correções funcionais, telas e testes antes da homologação.

## Fluxo principal planejado

```text
Dashboard Seller → Gateway → Public API → Commerce / Account / Wallet
Venda → Commerce cria tentativa ou dispatch → Notification → Meta/e-mail
Meta callback → Notification → Commerce → Wallet consome ou libera créditos
Recarga PIX → Banking V2 → Wallet credita carteira
```

## Componentes e responsabilidades

| Componente | Responsabilidade planejada |
| --- | --- |
| Commerce V2 | Regras por produto/afiliação, tentativas de entrega, RDC e integração com Wallet. |
| Account | Feature flags, preço padrão e overrides por usuário. |
| Wallet | Créditos, hold, consume, release, saldo e alertas de insuficiência. |
| Banking V2 | Cobrança PIX de pacotes e crédito idempotente após pagamento. |
| Notification | WhatsApp Meta, e-mail, templates, callback e fila de resultados. O e-mail de RDC (`sale/recovery_dispatch`) usa o layout base compartilhado da plataforma e direciona para `/rdc?cod={order}`. |
| Gateway / Public API | Caminho autenticado entre Dashboard e serviços. |
| Dashboard Seller | Configuração, recargas, saldo, histórico e reenvios. Para administradores, o status de serviços mostra os 500 registros mais recentes de cada canal e abre os detalhes de e-mail/WhatsApp. |

## Dados e filas

O código da feature já adiciona `sale_delivery_attempts`, regras de produto/afiliação, créditos de comunicação, recarga PIX, outcomes genéricos e callbacks Meta. A aplicação do SQL manual da Wallet e a validação integrada ainda não foram comprovadas.

O endpoint administrativo de status de serviços retorna, para e-mail e WhatsApp Meta, o estado interno, estado de entrega, erro normalizado, datas, template e destinatário; e-mail inclui também o provedor. O dashboard não expõe os parâmetros/conteúdo personalizado da comunicação. Push permanece no painel resumido, sem modal de detalhes.

## Operação e validação

O Commerce V2 disponibiliza `sales-delivery:resend-failed-emails` para recuperar e-mails de entrega. O operador deve informar `--confirmed-from` no formato `YYYY-MM-DD HH:MM:SS`, sempre interpretado como `America/Sao_Paulo`; `--confirmed-until` restringe opcionalmente o fim do intervalo. O comando filtra `sales.status = paid` por `sales.confirmed_at`, que é uma coluna `DATETIME` sem offset, portanto usa o mesmo valor de relógio de São Paulo na consulta, sem conversão UTC. Ele só coloca na fila uma venda cuja última tentativa de e-mail esteja em `fail` e não tenha nenhum e-mail em `success`, `delivered` ou `read`. Sem `--execute`, é uma simulação; o reenvio efetivo é administrativo, gratuito e apenas pelo canal e-mail.

## Limitações e pendências

- Definir administração de pacotes, expiração de créditos e estorno PIX.
- Corrigir cobrança do e-mail de RDC: ele não é gratuito e precisa usar hold/release/consume.
- Implementar reenvio administrativo com seleção de canais, telas de créditos/status/histórico e configuração por afiliação.
- Cobrir contratos e fluxos assíncronos com testes.
- Evolution está fora do novo RDC.

## Referências

- [Plano de comunicações de venda](../../plans/sale-notifications/README.md)
- [Auditoria de implementação e pendências](../../plans/sale-notifications/09_IMPLEMENTATION_AUDIT_AND_REMAINING_TASKS.md)
- `services-commerce-v2/app/Application/UseCase/Sale/ProcessPaidSaleEventDeliveryUseCase.php`
- `services-commerce-v2/app/Command/ResendFailedSaleDeliveryEmailsCommand.php`
- `services-notification/app/Process/WhatsappMetaDeliveryStatusQueueProcess.php`
