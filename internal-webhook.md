# Webhook Interno da Lowify

Documentation version: `1.0.0`

Este documento apresenta o webhook nativo da plataforma para notificações de venda em URLs cadastradas na Lowify.

Quando um evento configurado acontece em um produto, a Lowify envia uma request HTTP `POST` para a URL cadastrada, com um payload JSON contendo os dados da venda, do produto e do comprador.

## Como funciona

1. Você cadastra uma URL de webhook no painel da Lowify.
2. Escolhe quais eventos deseja receber para cada produto.
3. Quando o evento ocorre, a Lowify envia um `POST` para sua URL.
4. Sua aplicação processa o payload recebido.

## Eventos disponiveis

Hoje os eventos suportados são:

| Evento | Descricao |
| --- | --- |
| `sale.pending` | Enviado quando a venda foi criada e o pagamento ainda está pendente, como em pedidos com PIX gerado aguardando confirmação. |
| `sale.paid` | Enviado quando a venda foi aprovada e o pagamento foi confirmado com sucesso. |

## Request format

HTTP method:

```http
POST
```

Headers:

```http
Content-Type: application/json
Idempotency-Key: {order_id}:{event}:{product_id}
```

Exemplo:

```http
Idempotency-Key: ord_abcd1234:sale.paid:321
```

Esse header pode ser usado para evitar processamento duplicado no seu sistema.

## Payload structure

Todos os eventos seguem a mesma estrutura base:

```json
{
  "event": "sale.paid",
  "order_id": "ord_xxxxxxxxx",
  "sale_amount": 199.90,
  "status": "paid",
  "timestamp": "2026-03-10 14:30:00",
  "product": {
    "id": 321,
    "name": "Produto X",
    "price": 199.90,
    "type": "main"
  },
  "customer": {
    "name": "Cliente Exemplo",
    "email": "cliente@dominio.com",
    "phone": "11999999999"
  },
  "tracking": {
    "click_id": 10,
    "campaign_id": 20,
    "utm_source": "facebook",
    "utm_medium": "cpc",
    "utm_campaign": "campanha",
    "utm_content": "criativo-a",
    "utm_term": "keyword"
  }
}
```

## Field description

| Campo | Tipo | Descrição |
| --- | --- | --- |
| `event` | `string` | Nome do evento disparado. |
| `order_id` | `string` | Identificador público do pedido. |
| `sale_amount` | `number` | Valor total da venda. |
| `status` | `string` | Status atual da venda no momento do disparo. |
| `timestamp` | `string` | Data e hora do evento no formato `Y-m-d H:i:s`. |
| `product` | `object` | Object com os dados do produto relacionado ao webhook. |
| `product.id` | `integer` | ID interno do produto. |
| `product.name` | `string` | Nome do produto. |
| `product.price` | `number` | Valor do item referente a este disparo. |
| `product.type` | `string` | Tipo do item na venda. |
| `customer` | `object` | Object com os dados do comprador. |
| `customer.name` | `string` | Nome do comprador. |
| `customer.email` | `string` | E-mail do comprador. |
| `customer.phone` | `string \| null` | Telefone do comprador no padrão brasileiro, enviado com DDD + número, sem o prefixo `55`. |
| `tracking` | `object` | Object com os dados de tracking e campanha, quando disponíveis. |
| `tracking.click_id` | `integer \| null` | Identificador do clique associado à venda. |
| `tracking.campaign_id` | `integer \| null` | Identificador da campanha. |
| `tracking.utm_source` | `string \| null` | Origem da campanha. |
| `tracking.utm_medium` | `string \| null` | Mídia da campanha. |
| `tracking.utm_campaign` | `string \| null` | Nome da campanha. |
| `tracking.utm_content` | `string \| null` | Conteúdo da campanha. |
| `tracking.utm_term` | `string \| null` | Termo da campanha. |
