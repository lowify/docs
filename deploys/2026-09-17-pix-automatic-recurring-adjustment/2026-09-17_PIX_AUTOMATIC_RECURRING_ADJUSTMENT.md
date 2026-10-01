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

Executar no banco `lowify`, uma única vez. As referências `26091701` até `26091756` identificam este lote e respeitam a unicidade de `(type_id, reference_id)`.

```sql
START TRANSACTION;

SET @adjustment_reference_start = 26091701;
SET @adjustment_reference_end = 26091756;

INSERT INTO extract (id_usuario, type_id, reference_id, amount, created_at) VALUES
    (1131, 0, 26091701, 233.64, NOW()),
    (77, 0, 26091702, 229.68, NOW()),
    (1176, 0, 26091703, 134.64, NOW()),
    (55, 0, 26091704, 78.21, NOW()),
    (848, 0, 26091705, 68.31, NOW()),
    (1187, 0, 26091706, 64.35, NOW()),
    (5230, 0, 26091707, 64.35, NOW()),
    (586, 0, 26091708, 33.66, NOW()),
    (54, 0, 26091709, 29.70, NOW()),
    (1555, 0, 26091710, 27.29, NOW()),
    (7827, 0, 26091711, 20.79, NOW()),
    (19, 0, 26091712, 15.45, NOW()),
    (5643, 0, 26091713, 14.85, NOW()),
    (693, 0, 26091714, 13.86, NOW()),
    (1454, 0, 26091715, 12.87, NOW()),
    (697, 0, 26091716, 11.88, NOW()),
    (10, 0, 26091717, 11.14, NOW()),
    (4983, 0, 26091718, 10.89, NOW()),
    (425, 0, 26091719, 9.90, NOW()),
    (2714, 0, 26091720, 9.41, NOW()),
    (273, 0, 26091721, 8.91, NOW()),
    (3059, 0, 26091722, 8.91, NOW()),
    (10442, 0, 26091723, 7.92, NOW()),
    (814, 0, 26091724, 7.92, NOW()),
    (1382, 0, 26091725, 5.94, NOW()),
    (17, 0, 26091726, 5.60, NOW()),
    (3435, 0, 26091727, 3.96, NOW()),
    (9139, 0, 26091728, 3.96, NOW()),
    (1827, 0, 26091729, 2.97, NOW()),
    (5085, 0, 26091730, 2.97, NOW()),
    (4473, 0, 26091731, 1.99, NOW()),
    (1285, 0, 26091732, 1.98, NOW()),
    (307, 0, 26091733, 1.98, NOW()),
    (38, 0, 26091734, 1.98, NOW()),
    (735, 0, 26091735, 1.98, NOW()),
    (751, 0, 26091736, 1.98, NOW()),
    (8414, 0, 26091737, 1.98, NOW()),
    (10348, 0, 26091738, 0.99, NOW()),
    (10986, 0, 26091739, 0.99, NOW()),
    (11899, 0, 26091740, 0.99, NOW()),
    (1968, 0, 26091741, 0.99, NOW()),
    (2122, 0, 26091742, 0.99, NOW()),
    (2556, 0, 26091743, 0.99, NOW()),
    (2660, 0, 26091744, 0.99, NOW()),
    (2823, 0, 26091745, 0.99, NOW()),
    (2872, 0, 26091746, 0.99, NOW()),
    (305, 0, 26091747, 0.99, NOW()),
    (3285, 0, 26091748, 0.99, NOW()),
    (4800, 0, 26091749, 0.99, NOW()),
    (6630, 0, 26091750, 0.99, NOW()),
    (7431, 0, 26091751, 0.99, NOW()),
    (771, 0, 26091752, 0.99, NOW()),
    (7968, 0, 26091753, 0.99, NOW()),
    (849, 0, 26091754, 0.99, NOW()),
    (926, 0, 26091755, 0.99, NOW()),
    (99, 0, 26091756, 0.99, NOW());

COMMIT;
```

## 3. Validação

```sql
SELECT
    COUNT(*) AS adjustment_rows,
    ROUND(SUM(amount), 2) AS total_adjusted
FROM extract
WHERE type_id = 0
  AND reference_id BETWEEN 26091701 AND 26091756;
```

Resultado esperado: `56` linhas e `1186.61` de total creditado.
