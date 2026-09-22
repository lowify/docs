-- Validação: acesso web por link e Área de Membros
-- Banco: lowify

SELECT table_name, column_name, column_type
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND (
    (table_name = 'sales_access_sessions' AND column_name IN ('session_token_hash', 'expires_at', 'email_verified'))
    OR (table_name = 'sales_delivery' AND column_name IN ('product_id', 'access_source', 'access_session_hash', 'accessed_at'))
  )
ORDER BY table_name, ordinal_position;

SELECT table_name, index_name, non_unique, column_name, seq_in_index
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND (
    (table_name = 'sales_access_sessions' AND index_name IN ('idx_sales_access_sessions_link_ip', 'idx_sales_access_sessions_token_expiry'))
    OR (table_name = 'sales_delivery' AND index_name IN ('idx_sales_delivery_content_access_sale', 'uk_sales_delivery_content_access_session'))
  )
ORDER BY table_name, index_name, seq_in_index;
