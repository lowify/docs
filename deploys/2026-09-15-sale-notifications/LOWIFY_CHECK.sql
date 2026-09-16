-- Deploy: comunicações de venda
-- Banco: lowify
-- Execute após DEPLOY e SEEDS. Todos os objetos esperados devem aparecer.

SELECT table_name
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN (
    'product_sale_delivery_rules', 'product_sale_recovery_rules',
    'product_sale_recovery_rule_steps', 'product_sale_recovery_rule_step_channels',
    'sale_delivery_attempts', 'sale_recovery_dispatch_events', 'seller_balance_holds',
    'communication_credit_packages', 'communication_credit_balances',
    'communication_credit_purchases', 'communication_credit_entries',
    'communication_credit_alerts', 'communication_credit_outbox'
  )
ORDER BY table_name;

SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND (
    (table_name = 'sales_delivery' AND column_name IN ('sale_delivery_attempt_id','owner_user_id','is_late_delivery','status_timeout_at','hold_timeout_at','funding_source','funding_status','funding_reference_id','unit_price'))
    OR (table_name = 'sale_recovery_dispatches' AND column_name IN ('product_id','product_sale_recovery_rule_id','owner_user_id','affiliate_id','channel','skip_reason','funding_source','funding_status','funding_reference_id','unit_price'))
  )
ORDER BY table_name, ordinal_position;

SELECT var_key, var_value
FROM system_vars
WHERE var_key IN ('sale_notifications_feature_enabled','sale_delivery_whatsapp_enabled','sale_delivery_whatsapp_unit_price','sale_recovery_unit_price')
ORDER BY var_key;

SELECT id, description FROM extract_types WHERE id IN (35,36) ORDER BY id;
SELECT name, amount, bonus, is_active FROM communication_credit_packages ORDER BY amount, bonus;
