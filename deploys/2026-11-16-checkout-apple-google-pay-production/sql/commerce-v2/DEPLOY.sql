-- Executar uma única vez, somente se PRECHECK.sql retornar zero linhas
-- para as duas consultas. Executar no banco usado por services-commerce-v2.

ALTER TABLE tbl_produtos
    ADD COLUMN apple_pay_enabled TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER credit_card_enabled,
    ADD COLUMN google_pay_enabled TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER apple_pay_enabled;

INSERT INTO system_vars (var_key, var_value, updated_at)
VALUES
    ('checkout_apple_pay_enabled', '0', NOW()),
    ('checkout_google_pay_enabled', '0', NOW());
