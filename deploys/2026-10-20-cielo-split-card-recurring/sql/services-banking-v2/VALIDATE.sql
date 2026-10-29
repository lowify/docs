-- Banco: services-banking-v2
-- Confirma as alterações manuais da recorrência Cielo Split.

SELECT table_name, column_name, column_type, is_nullable
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND (
      (table_name = 'subscriptions' AND column_name = 'metadata')
      OR (table_name = 'subscriptions_charge' AND column_name = 'cielo_split_state')
  )
ORDER BY table_name, column_name;
