-- Executar no banco usado por services-commerce-v2.
-- Se qualquer consulta retornar estado parcial ou diferente do esperado, parar.

SELECT column_name, column_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name = 'tbl_produtos'
  AND column_name IN ('apple_pay_enabled', 'google_pay_enabled')
ORDER BY FIELD(column_name, 'apple_pay_enabled', 'google_pay_enabled');

SELECT var_key, var_value
FROM system_vars
WHERE var_key IN ('checkout_apple_pay_enabled', 'checkout_google_pay_enabled')
ORDER BY FIELD(var_key, 'checkout_apple_pay_enabled', 'checkout_google_pay_enabled');
