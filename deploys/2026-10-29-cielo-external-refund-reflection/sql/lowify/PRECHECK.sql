SELECT banking_refund_id, COUNT(*) AS duplicates
FROM sales_refund
GROUP BY banking_refund_id
HAVING COUNT(*) > 1;

SELECT INDEX_NAME, NON_UNIQUE, COLUMN_NAME, SEQ_IN_INDEX
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = 'lowify'
  AND TABLE_NAME = 'sales_refund'
  AND INDEX_NAME = 'uq_sales_refund_banking_refund_id';
