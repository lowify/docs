-- Executar no banco usado por services-banking-v2 após DEPLOY.sql.

SELECT column_name, column_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'charges_card'
  AND column_name = 'wallet_card_id';

SELECT index_name, column_name, seq_in_index
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name = 'charges_card'
  AND index_name = 'idx_charges_card_wallet_id'
ORDER BY seq_in_index;
