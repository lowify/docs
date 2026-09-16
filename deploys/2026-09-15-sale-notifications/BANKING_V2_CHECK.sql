-- Deploy: comunicações de venda
-- Banco do Banking V2
-- Execute após BANKING_V2_DEPLOY.sql.

SELECT column_name, column_type, is_nullable
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'pix_charges'
  AND column_name IN ('purpose','communication_credit_purchase_uuid','communication_credit_payment_data')
ORDER BY ordinal_position;

SELECT index_name, non_unique, GROUP_CONCAT(column_name ORDER BY seq_in_index) AS columns_in_index
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name = 'pix_charges'
  AND index_name = 'uk_pix_charges_communication_credit_purchase_uuid'
GROUP BY index_name, non_unique;
