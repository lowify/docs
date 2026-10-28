# Relatório — Fontes de confirmação no Checkout Transparente

**Período consultado:** último mês móvel (`NOW() - INTERVAL 1 MONTH`).
**Base:** `checkout_transparent_api`, tabela `charges`.
**Critério de aprovação:** `status = 'paid'`; a data usada é `confirmed_at`.

## Resumo por fonte de confirmação

| Fonte | Vendas confirmadas | Participação |
| --- | ---: | ---: |
| Webhook | 61.354 | 98,31% |
| Polling | 1.056 | 1,69% |
| **Total** | **62.410** | **100,00%** |

O webhook é o caminho predominante de confirmação. O polling corresponde a uma parcela residual das confirmações no recorte consultado.

## Confirmações por polling, por gateway

| Gateway | Vendas por polling | Participação no polling |
| --- | ---: | ---: |
| Woovi | 489 | 46,31% |
| Mercado Pago | 309 | 29,26% |
| Efibank | 147 | 13,92% |
| RisePay | 111 | 10,51% |
| **Total** | **1.056** | **100,00%** |

Woovi e Mercado Pago concentram 75,57% das confirmações feitas por polling.

## Vendas aprovadas e fonte de confirmação, por gateway

| Gateway | Vendas aprovadas | Via webhook | Via polling | % via polling | Via manual | Sem origem |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Woovi | 43.980 | 43.491 | 489 | 1,11% | 0 | 0 |
| Mercado Pago | 11.956 | 11.647 | 309 | 2,58% | 0 | 0 |
| Efibank | 6.419 | 6.272 | 147 | 2,29% | 0 | 0 |
| RisePay | 129 | 18 | 111 | 86,05% | 0 | 0 |
| **Total** | **62.484** | **61.428** | **1.056** | **1,69%** | **0** | **0** |

### Destaques

- A RisePay é a exceção: 86,05% das aprovações desse gateway foram confirmadas por polling.
- Na Woovi, Mercado Pago e Efibank, o polling ficou entre 1,11% e 2,58% das vendas aprovadas.

## Nota sobre a consistência do snapshot

O resumo inicial totaliza 62.410 confirmações, enquanto a consulta segmentada por gateway totaliza 62.484 — diferença de 74 vendas. Como as consultas foram executadas separadamente em uma base com novas confirmações em andamento, este relatório preserva os números de cada execução e não os trata como um único snapshot atômico. Para uma comparação fechada, todas as consultas devem usar a mesma janela de datas fixa e ser executadas na mesma extração.

## Consultas usadas

### Participação de webhook e polling

```sql
SELECT
  COUNT(*) AS vendas_confirmadas,
  SUM(confirmation_source = 'webhook') AS confirmadas_via_webhook,
  ROUND(100 * SUM(confirmation_source = 'webhook') / NULLIF(COUNT(*), 0), 2) AS percentual_webhook,
  SUM(confirmation_source = 'polling') AS confirmadas_via_polling,
  ROUND(100 * SUM(confirmation_source = 'polling') / NULLIF(COUNT(*), 0), 2) AS percentual_polling
FROM checkout_transparent_api.charges
WHERE status = 'paid'
  AND confirmed_at >= NOW() - INTERVAL 1 MONTH
  AND confirmation_source IN ('webhook', 'polling');
```

### Fonte de confirmação por gateway

```sql
SELECT
  ig.name AS gateway,
  COUNT(*) AS vendas_aprovadas,
  SUM(c.confirmation_source = 'webhook') AS via_webhook,
  SUM(c.confirmation_source = 'polling') AS via_polling,
  ROUND(100 * SUM(c.confirmation_source = 'polling') / NULLIF(COUNT(*), 0), 2) AS percentual_polling,
  SUM(c.confirmation_source = 'manual') AS via_manual,
  SUM(c.confirmation_source IS NULL) AS sem_origem
FROM checkout_transparent_api.charges c
JOIN checkout_transparent_api.integrations i ON i.id = c.integration_id
JOIN checkout_transparent_api.integration_gateways ig ON ig.id = i.integration_gateway_id
WHERE c.status = 'paid'
  AND c.confirmed_at >= NOW() - INTERVAL 1 MONTH
GROUP BY ig.id, ig.name
ORDER BY vendas_aprovadas DESC;
```
