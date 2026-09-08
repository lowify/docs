-- Comunicações de venda — complemento incremental de funding
--
-- Destino: banco `lowify` da homologação.
-- Pré-condição: executar as pré-checagens de 001_sale_notifications.sql.
-- Este patch destina-se a ambientes que já possuem as regras, créditos e
-- estruturas iniciais, mas ainda não receberam o fallback por saldo normal.
-- DDL MySQL possui commit implícito; executar em janela controlada.

CREATE TABLE `seller_balance_holds` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `owner_user_id` BIGINT UNSIGNED NOT NULL,
    `source_type` ENUM('sale_delivery', 'sale_recovery_dispatch') NOT NULL,
    `source_id` BIGINT UNSIGNED NOT NULL,
    `amount` DECIMAL(12,2) NOT NULL,
    `status` ENUM('held', 'consumed', 'released') NOT NULL DEFAULT 'held',
    `expires_at` DATETIME NULL DEFAULT NULL,
    `consumed_extract_id` BIGINT UNSIGNED NULL DEFAULT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_seller_balance_hold_source` (`source_type`, `source_id`),
    KEY `idx_seller_balance_hold_owner_status` (`owner_user_id`, `status`, `expires_at`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `sales_delivery`
    ADD COLUMN `funding_source` ENUM('communication_credit', 'seller_balance', 'none') NOT NULL DEFAULT 'none' AFTER `hold_timeout_at`,
    ADD COLUMN `funding_status` ENUM('not_required', 'held', 'consumed', 'released', 'insufficient') NOT NULL DEFAULT 'not_required' AFTER `funding_source`,
    ADD COLUMN `funding_reference_id` VARCHAR(100) NULL DEFAULT NULL AFTER `funding_status`,
    ADD COLUMN `unit_price` DECIMAL(12,2) NULL DEFAULT NULL AFTER `funding_reference_id`,
    ADD KEY `idx_sales_delivery_funding_status` (`funding_status`, `id`);

ALTER TABLE `sale_recovery_dispatches`
    ADD COLUMN `funding_source` ENUM('communication_credit', 'seller_balance', 'none') NOT NULL DEFAULT 'none' AFTER `skip_reason`,
    ADD COLUMN `funding_status` ENUM('not_required', 'held', 'consumed', 'released', 'insufficient') NOT NULL DEFAULT 'not_required' AFTER `funding_source`,
    ADD COLUMN `funding_reference_id` VARCHAR(100) NULL DEFAULT NULL AFTER `funding_status`,
    ADD COLUMN `unit_price` DECIMAL(12,2) NULL DEFAULT NULL AFTER `funding_reference_id`,
    ADD KEY `idx_sale_recovery_funding_status` (`funding_status`, `id`);

INSERT INTO `extract_types` (`id`, `description`)
VALUES (36, 'Comunicação de venda');
