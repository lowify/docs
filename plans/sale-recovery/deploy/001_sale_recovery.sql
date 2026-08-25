-- Recuperação de vendas por canais oficiais
--
-- Execute cada bloco no banco do serviço identificado pelo título.
-- Não execute este arquivo inteiro em uma única conexão e não use este arquivo
-- para o Checkout Transparente API: naquele serviço a alteração é uma migration.
--
-- Pré-requisito: fazer backup e validar os nomes de índices no ambiente alvo.
-- DDL em MySQL possui commit implícito.

-- ============================================================================
-- services-commerce-v2
-- ============================================================================

CREATE TABLE `product_sale_recovery_rules` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `product_id` BIGINT UNSIGNED NOT NULL,
    `owner_user_id` BIGINT UNSIGNED NOT NULL,
    `owner_type` ENUM('producer', 'affiliate') NOT NULL,
    `affiliate_id` BIGINT UNSIGNED NULL DEFAULT NULL,
    `is_enabled` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_product_sale_recovery_rule_owner` (`product_id`, `owner_type`, `owner_user_id`, `affiliate_id`),
    KEY `idx_product_sale_recovery_rule_owner_product` (`owner_user_id`, `product_id`),
    KEY `idx_product_sale_recovery_rule_affiliate_product` (`affiliate_id`, `product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `product_sale_recovery_rule_steps` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `product_sale_recovery_rule_id` BIGINT UNSIGNED NOT NULL,
    `step` TINYINT UNSIGNED NOT NULL,
    `delay_minutes` SMALLINT UNSIGNED NOT NULL,
    `is_enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_product_sale_recovery_step` (`product_sale_recovery_rule_id`, `step`),
    CONSTRAINT `fk_product_sale_recovery_step_rule`
        FOREIGN KEY (`product_sale_recovery_rule_id`) REFERENCES `product_sale_recovery_rules` (`id`)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `product_sale_recovery_rule_step_channels` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `product_sale_recovery_rule_step_id` BIGINT UNSIGNED NOT NULL,
    `channel` ENUM('email', 'whatsapp') NOT NULL,
    `created_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_product_sale_recovery_step_channel` (`product_sale_recovery_rule_step_id`, `channel`),
    CONSTRAINT `fk_product_sale_recovery_channel_step`
        FOREIGN KEY (`product_sale_recovery_rule_step_id`) REFERENCES `product_sale_recovery_rule_steps` (`id`)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A coluna permanece NULL durante a descontinuação do legado. O novo código
-- deve sempre preenchê-la com email ou whatsapp; não criar novos dispatches
-- legados. Após arquivamento do legado, uma segunda janela pode torná-la NOT NULL.
ALTER TABLE `sale_recovery_dispatches`
    ADD COLUMN `product_id` BIGINT UNSIGNED NULL DEFAULT NULL AFTER `sale_id`,
    ADD COLUMN `product_sale_recovery_rule_id` BIGINT UNSIGNED NULL DEFAULT NULL AFTER `product_id`,
    ADD COLUMN `owner_user_id` BIGINT UNSIGNED NULL DEFAULT NULL AFTER `user_id`,
    ADD COLUMN `affiliate_id` BIGINT UNSIGNED NULL DEFAULT NULL AFTER `owner_user_id`,
    ADD COLUMN `channel` ENUM('email', 'whatsapp') NULL DEFAULT NULL AFTER `stage`,
    ADD COLUMN `skip_reason` VARCHAR(100) NULL DEFAULT NULL AFTER `status`;

UPDATE `sale_recovery_dispatches`
SET `owner_user_id` = `user_id`
WHERE `owner_user_id` IS NULL;

ALTER TABLE `sale_recovery_dispatches`
    MODIFY COLUMN `status` ENUM('scheduled', 'processing', 'queued', 'sent', 'sent_to_provider', 'confirmed', 'failed', 'skipped', 'canceled') NOT NULL DEFAULT 'scheduled',
    DROP INDEX `uk_sale_recovery_sale_stage`,
    ADD UNIQUE KEY `uk_sale_recovery_sale_stage_channel` (`sale_id`, `stage`, `channel`),
    ADD KEY `idx_sale_recovery_owner_status_schedule` (`owner_user_id`, `status`, `scheduled_for`, `id`),
    ADD KEY `idx_sale_recovery_product_id` (`product_id`),
    ADD KEY `idx_sale_recovery_affiliate_id` (`affiliate_id`);

CREATE TABLE `sale_recovery_dispatch_events` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `sale_recovery_dispatch_id` BIGINT UNSIGNED NOT NULL,
    `event_type` ENUM('scheduled', 'queued', 'sent_to_provider', 'confirmed', 'failed', 'skipped', 'canceled', 'read') NOT NULL,
    `occurred_at` DATETIME NOT NULL,
    `provider_reference_type` ENUM('email_single', 'whatsapp_meta') NULL DEFAULT NULL,
    `provider_reference_id` BIGINT UNSIGNED NULL DEFAULT NULL,
    `reason` VARCHAR(255) NULL DEFAULT NULL,
    `metadata` JSON NULL DEFAULT NULL,
    `created_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_sale_recovery_event_idempotency` (`sale_recovery_dispatch_id`, `event_type`, `provider_reference_type`, `provider_reference_id`),
    KEY `idx_sale_recovery_event_dispatch_date` (`sale_recovery_dispatch_id`, `occurred_at`, `id`),
    CONSTRAINT `fk_sale_recovery_event_dispatch`
        FOREIGN KEY (`sale_recovery_dispatch_id`) REFERENCES `sale_recovery_dispatches` (`id`)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- services-account
-- ============================================================================
-- `system_vars` e `user_system_vars` já existem. O preço inicial deve ser
-- definido antes da liberação. Substitua 0.00 pela taxa comercial aprovada.

INSERT INTO `system_vars` (`var_key`, `var_value`)
VALUES
    ('sale_recovery_feature_enabled', '0'),
    ('sale_recovery_unit_price', '0.00')
ON DUPLICATE KEY UPDATE `var_value` = `var_value`;

-- Não inserir override em user_system_vars neste deploy. Admins 1/2 criam ou
-- removem overrides por usuário pela tela administrativa.

-- ============================================================================
-- services-wallet
-- ============================================================================

CREATE TABLE `sale_recovery_balance_holds` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `user_id` BIGINT UNSIGNED NOT NULL,
    `sale_recovery_dispatch_id` BIGINT UNSIGNED NOT NULL,
    `amount` DECIMAL(12,2) NOT NULL,
    `status` ENUM('blocked', 'approved', 'refused') NOT NULL DEFAULT 'blocked',
    `blocked_at` DATETIME NOT NULL,
    `resolved_at` DATETIME NULL DEFAULT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_sale_recovery_hold_dispatch` (`sale_recovery_dispatch_id`),
    KEY `idx_sale_recovery_hold_user_status` (`user_id`, `status`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- O ID de extract_types deve seguir a numeração efetiva do banco Wallet.
-- Escolha o próximo ID livre antes de executar este insert.
-- INSERT INTO `extract_types` (`id`, `description`)
-- VALUES (<NEXT_ID>, 'Recuperação de venda')
-- ON DUPLICATE KEY UPDATE `description` = VALUES(`description`);
