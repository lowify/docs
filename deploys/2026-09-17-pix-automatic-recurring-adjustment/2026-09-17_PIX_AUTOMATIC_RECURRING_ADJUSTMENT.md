# Ajuste de saldo — parcelas Pix Automático

Corrige parcelas recorrentes Pix Automático que tiveram a taxa do seller descontada uma segunda vez e credita no extrato a diferença já perdida.

## Escopo confirmado

- 1.230 parcelas afetadas;
- 56 sellers afetados;
- R$ 1.186,61 a creditar no total;
- 96 parcelas têm `gross_amount` válido: R$ 95,04;
- 1.134 parcelas não possuem `gross_amount`; para elas, o valor correto é o líquido da primeira venda da mesma assinatura;
- cada lançamento de compensação usa `extract.type_id = 0` e um crédito positivo;
- o trigger da tabela `extract` calcula a coluna `balance`. Nunca definir `balance` manualmente.

## 1. Correção das vendas pelo Commerce

O comando `subscriptions:repair-pix-automatic-recurring-sale-amounts` corrige somente parcelas pagas com Pix Automático, assinatura e `order_id` iniciado por `sub_`.

Para cada parcela, ele:

1. usa `gross_amount - order_bump_fee - taxa_seller`, quando o bruto existe;
2. sem bruto, usa como referência o líquido da primeira venda daquela assinatura;
3. atualiza somente quando o valor correto é maior que o `sale_amount` atual. Nunca reduz valores históricos.

Executar primeiro o dry-run. O resultado esperado é `eligible=1230` e `updated=0`.

```bash
cd /opt/lowify/services/service-commerce-v2

docker compose exec -T service-commerce-v2 \
  php bin/hyperf.php subscriptions:repair-pix-automatic-recurring-sale-amounts
```

Depois de confirmar o total, executar a atualização:

```bash
docker compose exec -T service-commerce-v2 \
  php bin/hyperf.php subscriptions:repair-pix-automatic-recurring-sale-amounts --execute
```

Resultado esperado: `eligible=1230 updated=1230`.

## 2. Crédito de ajuste no extrato

Executar no banco `lowify`, uma única vez. A referência `2026091701` identifica este lote e torna o script idempotente por seller.

```sql
START TRANSACTION;

SET @adjustment_reference_id = 2026091701;

INSERT INTO extract (id_usuario, type_id, reference_id, amount, created_at)
SELECT adjustment.user_id, 0, @adjustment_reference_id, adjustment.amount, NOW()
FROM (
    SELECT 1131 AS user_id, 233.64 AS amount UNION ALL
    SELECT 77, 229.68 UNION ALL
    SELECT 1176, 134.64 UNION ALL
    SELECT 55, 78.21 UNION ALL
    SELECT 848, 68.31 UNION ALL
    SELECT 1187, 64.35 UNION ALL
    SELECT 5230, 64.35 UNION ALL
    SELECT 586, 33.66 UNION ALL
    SELECT 54, 29.70 UNION ALL
    SELECT 1555, 27.29 UNION ALL
    SELECT 7827, 20.79 UNION ALL
    SELECT 19, 15.45 UNION ALL
    SELECT 5643, 14.85 UNION ALL
    SELECT 693, 13.86 UNION ALL
    SELECT 1454, 12.87 UNION ALL
    SELECT 697, 11.88 UNION ALL
    SELECT 10, 11.14 UNION ALL
    SELECT 4983, 10.89 UNION ALL
    SELECT 425, 9.90 UNION ALL
    SELECT 2714, 9.41 UNION ALL
    SELECT 273, 8.91 UNION ALL
    SELECT 3059, 8.91 UNION ALL
    SELECT 10442, 7.92 UNION ALL
    SELECT 814, 7.92 UNION ALL
    SELECT 1382, 5.94 UNION ALL
    SELECT 17, 5.60 UNION ALL
    SELECT 3435, 3.96 UNION ALL
    SELECT 9139, 3.96 UNION ALL
    SELECT 1827, 2.97 UNION ALL
    SELECT 5085, 2.97 UNION ALL
    SELECT 4473, 1.99 UNION ALL
    SELECT 1285, 1.98 UNION ALL
    SELECT 307, 1.98 UNION ALL
    SELECT 38, 1.98 UNION ALL
    SELECT 735, 1.98 UNION ALL
    SELECT 751, 1.98 UNION ALL
    SELECT 8414, 1.98 UNION ALL
    SELECT 10348, 0.99 UNION ALL
    SELECT 10986, 0.99 UNION ALL
    SELECT 11899, 0.99 UNION ALL
    SELECT 1968, 0.99 UNION ALL
    SELECT 2122, 0.99 UNION ALL
    SELECT 2556, 0.99 UNION ALL
    SELECT 2660, 0.99 UNION ALL
    SELECT 2823, 0.99 UNION ALL
    SELECT 2872, 0.99 UNION ALL
    SELECT 305, 0.99 UNION ALL
    SELECT 3285, 0.99 UNION ALL
    SELECT 4800, 0.99 UNION ALL
    SELECT 6630, 0.99 UNION ALL
    SELECT 7431, 0.99 UNION ALL
    SELECT 771, 0.99 UNION ALL
    SELECT 7968, 0.99 UNION ALL
    SELECT 849, 0.99 UNION ALL
    SELECT 926, 0.99 UNION ALL
    SELECT 99, 0.99
) adjustment
WHERE NOT EXISTS (
    SELECT 1
    FROM extract existing
    WHERE existing.id_usuario = adjustment.user_id
      AND existing.type_id = 0
      AND existing.reference_id = @adjustment_reference_id
);

COMMIT;
```

## 3. Validação

```sql
SELECT
    COUNT(*) AS adjustment_rows,
    ROUND(SUM(amount), 2) AS total_adjusted
FROM extract
WHERE type_id = 0
  AND reference_id = 2026091701;
```

Resultado esperado: `56` linhas e `1186.61` de total creditado.
