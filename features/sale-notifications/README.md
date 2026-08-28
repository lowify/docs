# Feature — comunicações de venda

> Status: em evolução
> Última atualização: 2026-08-28
> Confiança: parcialmente confirmada

## Objetivo

Unificar a entrega pós-compra e a recuperação de venda pendente (RDC) sob uma carteira de créditos monetários de comunicação. A implementação ainda não foi iniciada; as regras de negócio abaixo foram confirmadas pelo produto.

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
| Notification | WhatsApp Meta, e-mail, templates, callback e fila de resultados. |
| Gateway / Public API | Caminho autenticado entre Dashboard e serviços. |
| Dashboard Seller | Configuração, recargas, saldo, histórico e reenvios. |

## Dados e filas

O código atual já possui `sales_delivery`, callbacks Meta e fluxo de e-mail condicionado ao resultado do WhatsApp. O plano prevê `sale_delivery_attempts`, carteira de créditos e uma fila genérica de resultado para entrega e RDC. Esses novos dados e contratos ainda não existem no código.

## Limitações e pendências

- Definir administração de pacotes, expiração de créditos e estorno PIX.
- Implementar configuração por produto/afiliação, créditos e reenvios.
- Evolution será descontinuado no novo fluxo.

## Referências

- [Plano de comunicações de venda](../../plans/sale-notifications/README.md)
- `services-commerce-v2/app/Application/UseCase/Sale/ProcessPaidSaleEventDeliveryUseCase.php`
- `services-notification/app/Process/WhatsappMetaDeliveryStatusQueueProcess.php`
