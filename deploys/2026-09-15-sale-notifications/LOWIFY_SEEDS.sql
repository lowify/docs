-- Deploy: comunicações de venda
-- Banco: lowify
-- Execute após LOWIFY_DEPLOY.sql.

INSERT INTO system_vars (var_key, var_value)
VALUES
    ('sale_notifications_feature_enabled', '1'),
    ('sale_delivery_whatsapp_enabled', '1'),
    ('sale_delivery_whatsapp_unit_price', '0.35'),
    ('sale_recovery_unit_price', '0.35')
ON DUPLICATE KEY UPDATE var_value = VALUES(var_value);

-- A ausência de sale_notifications_allow_seller_balance em user_system_vars
-- significa permitido. Não criar overrides por usuário neste deploy.

INSERT INTO extract_types (id, description)
VALUES
    (35, 'Compra de créditos de comunicação'),
    (36, 'Comunicação de venda')
ON DUPLICATE KEY UPDATE description = VALUES(description);

INSERT INTO communication_credit_packages (name, amount, bonus, is_active, created_at, updated_at)
SELECT 'Créditos de comunicação — R$ 50,00', 50.00, 0.00, 1, NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM communication_credit_packages WHERE amount = 50.00 AND bonus = 0.00);
INSERT INTO communication_credit_packages (name, amount, bonus, is_active, created_at, updated_at)
SELECT 'Créditos de comunicação — R$ 100,00', 100.00, 0.00, 1, NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM communication_credit_packages WHERE amount = 100.00 AND bonus = 0.00);
INSERT INTO communication_credit_packages (name, amount, bonus, is_active, created_at, updated_at)
SELECT 'Créditos de comunicação — R$ 500,00', 500.00, 20.00, 1, NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM communication_credit_packages WHERE amount = 500.00 AND bonus = 20.00);
INSERT INTO communication_credit_packages (name, amount, bonus, is_active, created_at, updated_at)
SELECT 'Créditos de comunicação — R$ 1.000,00', 1000.00, 40.00, 1, NOW(), NOW()
WHERE NOT EXISTS (SELECT 1 FROM communication_credit_packages WHERE amount = 1000.00 AND bonus = 40.00);
