-- Deploy: acesso web por link e Área de Membros
-- Banco: lowify
-- Execução manual, uma única vez, pelo operador.
-- DDL MySQL possui commit implícito. Antes de executar, rode VALIDATE.sql.

ALTER TABLE `sales_access_sessions`
    ADD COLUMN `session_token_hash` BINARY(32) NULL AFTER `ip`,
    ADD COLUMN `expires_at` DATETIME NULL AFTER `accessed_at`,
    ADD COLUMN `email_verified` TINYINT(1) UNSIGNED NOT NULL DEFAULT 0 AFTER `public_mode`,
    ADD KEY `idx_sales_access_sessions_link_ip` (`sales_access_link_id`, `ip`),
    ADD KEY `idx_sales_access_sessions_token_expiry` (`session_token_hash`, `expires_at`);

ALTER TABLE `sales_delivery`
    MODIFY COLUMN `type` ENUM('whatsapp', 'email', 'evolution', 'access_link') NOT NULL,
    MODIFY COLUMN `status` ENUM('pending', 'sent_to_provider', 'sent_pending', 'timed_out', 'fail', 'success', 'delivered', 'read', 'skipped', 'canceled', 'opened', 'hidden') NULL DEFAULT NULL;

ALTER TABLE `sales_delivery`
    MODIFY COLUMN `type` ENUM('whatsapp', 'email', 'evolution', 'access_link', 'content_access') NOT NULL,
    ADD COLUMN `product_id` BIGINT UNSIGNED NULL AFTER `sale_id`,
    ADD COLUMN `access_source` ENUM('link_access', 'members_area') NULL AFTER `type`,
    ADD COLUMN `access_session_hash` BINARY(32) NULL AFTER `access_source`,
    ADD COLUMN `accessed_at` DATETIME NULL AFTER `updated_at`,
    ADD KEY `idx_sales_delivery_content_access_sale` (`sale_id`, `type`, `accessed_at`),
    ADD UNIQUE KEY `uk_sales_delivery_content_access_session` (`sale_id`, `type`, `product_id`, `access_source`, `access_session_hash`);
