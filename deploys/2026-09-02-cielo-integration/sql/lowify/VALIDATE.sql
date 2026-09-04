-- Banco: lowify
-- Fase 01: preparação do ambiente.
-- Escopo: services-account e services-commerce-v2
-- Objetivo: validar as alterações aplicadas por DEPLOY.sql.
-- Execução: somente leitura.

-- Estruturas criadas/evoluídas pelo Account.
SELECT table_name
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN ('user_account_bank', 'user_account_bank_addicional', 'review_cases', 'review_case_events');

SELECT table_name, column_name, column_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND (
    (table_name = 'tbl_usuarios' AND column_name = 'card_integration_enabled')
    OR (table_name = 'user_events' AND column_name = 'payload')
    OR (table_name = 'tbl_produtos' AND column_name IN ('pix_enabled', 'credit_card_enabled', 'credit_card_installments'))
    OR (table_name = 'sales_affiliates' AND column_name = 'settlement_method')
    OR (table_name = 'disputes' AND column_name = 'should_block_balance')
    OR (table_name = 'tbl_usuarios' AND column_name = 'gateway_prioritario_checkout_card')
  )
ORDER BY table_name, ordinal_position;

SELECT column_name
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'user_account_bank'
  AND column_name LIKE 'cielo_%';
-- Resultado esperado: nenhuma linha.

SELECT table_name, index_name, column_name, seq_in_index
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND index_name IN (
    'idx_tbl_usuarios_card_integration_enabled',
    'idx_sales_affiliates_settlement_method',
    'idx_disputes_should_block_status_seller',
    'idx_disputes_should_block_status_affiliate'
  )
ORDER BY table_name, index_name, seq_in_index;

SELECT id_gateway, nome, identificador, status, cash_in, cash_out
FROM tbl_gateways
WHERE identificador IN ('cielo_ecommerce', 'pagarme_psp');

SELECT var_key, var_value
FROM system_vars
WHERE var_key = 'gateway_default_checkout_card';
