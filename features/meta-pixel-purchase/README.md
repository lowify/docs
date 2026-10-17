# Feature — Meta Pixel Purchase

> Status: ativo
> Última atualização: 2026-10-16
> Confiança: confirmada no código

## Objetivo

Enviar eventos de funil ao Meta Pixel associado a um produto, preservando `Purchase` como a confirmação de uma venda paga.

## Fluxo principal

```text
Checkout -> InitiateCheckout -> criação da venda pendente/PIX -> confirmação do gateway -> sales.status = paid -> success.php -> Meta Purchase
```

## Componentes e responsabilidades

| Componente | Responsabilidade | Entrada/saída relevante |
| --- | --- | --- |
| `dashboard-seller/checkout.php` | Inicia o rastreio no checkout. | Envia `InitiateCheckout` com `currency: BRL` e o preço do produto. |
| `dashboard-seller/thank_you.php` | Exibe instruções e código PIX de uma venda pendente. | Não envia `Purchase` ao Meta. |
| `dashboard-seller/success.php` | Exibe o pedido confirmado. | Só continua quando `sales.status` é `paid`; envia `Purchase` em BRL. |
| `dashboard-seller/pixels/lib.php` | Busca pixels ativos associados ao produto e cria um ID de evento por pedido. | `tbl_facebook_pixels`, associações de produtos e `tbl_fb_event_keys`. |

## Contratos e autorização

O evento `Purchase` é emitido no navegador com `fbq('trackSingle', pixelId, 'Purchase', data, {eventID})`. O payload contém:

- `currency: 'BRL'`;
- `value`: total bruto da venda paga, incluindo itens relacionados;
- `content_type: 'product'`, `content_ids` e `num_items`.

O `eventID` é persistido por `order_id`, permitindo que a Meta deduplique reaberturas da página de sucesso.

## Dados e processamento assíncrono

Não há chamada server-side à Conversion API nesse fluxo. A venda é criada como pendente e o status é atualizado pelo fluxo de pagamento; a página de sucesso rejeita pedidos cujo status não seja `paid`.

## Operação e validação

Validar em homologação com um PIX gerado e não pago, seguido do mesmo PIX confirmado:

1. No Meta Pixel Helper/Test Events, confirmar `InitiateCheckout` com o preço exibido no checkout.
2. Confirmar que a página de PIX pendente não registra `Purchase`.
3. Após a confirmação, abrir a URL de sucesso e confirmar um único `Purchase` com `currency = BRL` e o valor bruto da venda.

## Limitações e pendências

O evento é browser-side; caso seja adicionada Conversion API, ela deve reutilizar o mesmo `eventID` para deduplicação. O valor enviado é derivado dos dados registrados em `sales`; qualquer integração que grave valores em centavos deve convertê-los antes de criar a venda.

## Referências

- `dashboard-seller/checkout.php`
- `dashboard-seller/thank_you.php`
- `dashboard-seller/success.php`
- `dashboard-seller/pixels/lib.php`
