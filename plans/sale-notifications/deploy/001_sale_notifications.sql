-- Plano: comunicações de venda
-- Execute cada bloco no banco do serviço indicado. Não execute o arquivo inteiro
-- em uma única conexão. Validar backup, nomes de índices e estado do schema antes
-- do deploy; DDL MySQL possui commit implícito.

-- ============================================================================
-- services-commerce-v2
-- ============================================================================

CREATE TABLE `product_sale_delivery_rules` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `product_id` BIGINT UNSIGNED NOT NULL,
    `owner_user_id` BIGINT UNSIGNED NOT NULL,
    `owner_type` ENUM('producer', 'affiliate') NOT NULL,
    `affiliate_id` BIGINT UNSIGNED NULL DEFAULT NULL,
    `affiliate_scope_id` BIGINT UNSIGNED AS (COALESCE(`affiliate_id`, 0)) STORED,
    `whatsapp_enabled` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_product_sale_delivery_rule_owner`
        (`product_id`, `owner_type`, `owner_user_id`, `affiliate_scope_id`),
    KEY `idx_product_sale_delivery_rule_owner_product` (`owner_user_id`, `product_id`),
    KEY `idx_product_sale_delivery_rule_affiliate_product` (`affiliate_id`, `product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `product_sale_recovery_rules` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `product_id` BIGINT UNSIGNED NOT NULL,
    `owner_user_id` BIGINT UNSIGNED NOT NULL,
    `owner_type` ENUM('producer', 'affiliate') NOT NULL,
    `affiliate_id` BIGINT UNSIGNED NULL DEFAULT NULL,
    `affiliate_scope_id` BIGINT UNSIGNED AS (COALESCE(`affiliate_id`, 0)) STORED,
    `is_enabled` TINYINT(1) NOT NULL DEFAULT 0,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_product_sale_recovery_rule_owner`
        (`product_id`, `owner_type`, `owner_user_id`, `affiliate_scope_id`),
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

CREATE TABLE `sale_delivery_attempts` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `sale_id` BIGINT UNSIGNED NOT NULL,
    `owner_user_id` BIGINT UNSIGNED NOT NULL,
    `is_resend` TINYINT(1) NOT NULL DEFAULT 0,
    `author_type` ENUM('system', 'seller', 'collaborator', 'admin') NOT NULL,
    `author_user_id` BIGINT UNSIGNED NULL DEFAULT NULL,
    `chargeable` TINYINT(1) NOT NULL DEFAULT 1,
    `idempotency_key` VARCHAR(100) NOT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_sale_delivery_attempt_idempotency` (`idempotency_key`),
    KEY `idx_sale_delivery_attempt_sale` (`sale_id`, `id`),
    KEY `idx_sale_delivery_attempt_owner` (`owner_user_id`, `created_at`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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

-- O índice legado é uk_sale_recovery_sale_stage. Validar o nome no ambiente
-- antes de executar; registros legados permanecem com channel NULL.
ALTER TABLE `sale_recovery_dispatches`
    MODIFY COLUMN `status`
        ENUM('scheduled', 'processing', 'sent', 'queued', 'sent_to_provider', 'confirmed', 'failed', 'skipped', 'canceled')
        NOT NULL DEFAULT 'scheduled',
    DROP INDEX `uk_sale_recovery_sale_stage`,
    ADD UNIQUE KEY `uk_sale_recovery_sale_stage_channel` (`sale_id`, `stage`, `channel`),
    ADD KEY `idx_sale_recovery_owner_status_schedule` (`owner_user_id`, `status`, `scheduled_for`, `id`);

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
    UNIQUE KEY `uk_sale_recovery_event_idempotency`
        (`sale_recovery_dispatch_id`, `event_type`, `provider_reference_type`, `provider_reference_id`),
    KEY `idx_sale_recovery_event_dispatch_date` (`sale_recovery_dispatch_id`, `occurred_at`, `id`),
    CONSTRAINT `fk_sale_recovery_event_dispatch`
        FOREIGN KEY (`sale_recovery_dispatch_id`) REFERENCES `sale_recovery_dispatches` (`id`)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A referência do provider ainda não existe na criação da tentativa.
ALTER TABLE `sales_delivery`
    ADD COLUMN `sale_delivery_attempt_id` BIGINT UNSIGNED NULL DEFAULT NULL AFTER `sale_id`,
    ADD COLUMN `owner_user_id` BIGINT UNSIGNED NULL DEFAULT NULL AFTER `sale_delivery_attempt_id`,
    ADD COLUMN `is_late_delivery` TINYINT(1) NOT NULL DEFAULT 0 AFTER `error`,
    ADD COLUMN `status_timeout_at` DATETIME NULL DEFAULT NULL AFTER `is_late_delivery`,
    ADD COLUMN `hold_timeout_at` DATETIME NULL DEFAULT NULL AFTER `status_timeout_at`,
    MODIFY COLUMN `reference_id` INT UNSIGNED NULL DEFAULT NULL,
    MODIFY COLUMN `status`
        ENUM('pending', 'sent_to_provider', 'sent_pending', 'timed_out', 'fail', 'success', 'read', 'delivered', 'skipped', 'canceled')
        NULL DEFAULT NULL,
    ADD KEY `idx_sales_delivery_attempt` (`sale_delivery_attempt_id`),
    ADD KEY `idx_sales_delivery_owner_status` (`owner_user_id`, `status`, `id`),
    ADD KEY `idx_sales_delivery_status_timeout` (`status`, `status_timeout_at`, `id`),
    ADD KEY `idx_sales_delivery_hold_timeout` (`status`, `hold_timeout_at`, `id`);

-- Os fluxos novos usam sale_delivery_attempt_id + type como identidade. Antes
-- de adicionar a unicidade, migrar/arquivar reenvios históricos que conflitem.
-- ALTER TABLE `sales_delivery`
--     ADD UNIQUE KEY `uk_sales_delivery_attempt_type` (`sale_delivery_attempt_id`, `type`);

-- ============================================================================
-- services-account
-- ============================================================================

-- `system_vars` já existe no banco legado. `user_system_vars` pode não existir
-- em instalações antigas; este DDL também documenta o contrato utilizado pelo
-- Account para overrides por usuário.
CREATE TABLE IF NOT EXISTS `user_system_vars` (
    `user_id` BIGINT UNSIGNED NOT NULL,
    `var_key` VARCHAR(100) NOT NULL,
    `var_value` VARCHAR(255) NULL DEFAULT NULL,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`user_id`, `var_key`),
    KEY `idx_user_system_vars_key` (`var_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Pré-checagem: esta consulta deve retornar zero linhas. Caso contrário, tratar
-- as duplicidades antes de criar a unicidade usada pelo upsert do Account.
SELECT `user_id`, `var_key`, COUNT(*) AS `duplicate_count`
FROM `user_system_vars`
GROUP BY `user_id`, `var_key`
HAVING COUNT(*) > 1;

-- Para uma tabela já existente, garantir a coluna de auditoria e a unicidade
-- de forma idempotente. Executar somente após a pré-checagem de duplicidades.
SET @account_schema := DATABASE();
SET @add_user_system_vars_updated_at := (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE `user_system_vars` ADD COLUMN `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP',
        'SELECT 1'
    )
    FROM information_schema.columns
    WHERE table_schema = @account_schema
      AND table_name = 'user_system_vars'
      AND column_name = 'updated_at'
);
PREPARE account_statement FROM @add_user_system_vars_updated_at;
EXECUTE account_statement;
DEALLOCATE PREPARE account_statement;

SET @add_user_system_vars_unique := (
    SELECT IF(
        EXISTS (
            SELECT 1
            FROM (
                SELECT `index_name`, GROUP_CONCAT(`column_name` ORDER BY `seq_in_index`) AS `columns`
                FROM information_schema.statistics
                WHERE table_schema = @account_schema
                  AND table_name = 'user_system_vars'
                  AND non_unique = 0
                GROUP BY `index_name`
                HAVING `columns` = 'user_id,var_key'
            ) AS `unique_indexes`
        ),
        'SELECT 1',
        'ALTER TABLE `user_system_vars` ADD UNIQUE KEY `uk_user_system_vars_user_key` (`user_id`, `var_key`)'
    )
);
PREPARE account_statement FROM @add_user_system_vars_unique;
EXECUTE account_statement;
DEALLOCATE PREPARE account_statement;

INSERT INTO `system_vars` (`var_key`, `var_value`)
VALUES
    ('sale_notifications_feature_enabled', '0'),
    ('sale_delivery_whatsapp_enabled', '0'),
    ('sale_delivery_whatsapp_unit_price', '0.00'),
    ('sale_recovery_unit_price', '0.00')
ON DUPLICATE KEY UPDATE `var_value` = `var_value`;

-- Overrides por usuário ficam em user_system_vars e são administrados via Account.

-- ============================================================================
-- services-wallet
-- ============================================================================

-- Pré-validação obrigatória: o tipo 35 foi reservado para esta feature.
-- Não prossiga se o ID 35 já tiver outra descrição.
SELECT `id`, `description`
FROM `extract_types`
WHERE `id` = 35
ORDER BY `id`;

-- O tipo é usado pelo débito do saldo normal na compra de pacote de créditos.
-- O INSERT deve falhar, em vez de sobrescrever, se houver conflito de ID.
INSERT INTO `extract_types` (`id`, `description`)
VALUES (35, 'Compra de créditos de comunicação');

CREATE TABLE `communication_credit_packages` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `amount` DECIMAL(12,2) NOT NULL,
    `bonus` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    `is_active` TINYINT(1) NOT NULL DEFAULT 1,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    CONSTRAINT `chk_communication_credit_package_amount` CHECK (`amount` > 0),
    CONSTRAINT `chk_communication_credit_package_bonus` CHECK (`bonus` >= 0),
    KEY `idx_communication_credit_package_active` (`is_active`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `communication_credit_balances` (
    `owner_user_id` BIGINT UNSIGNED NOT NULL,
    `balance` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    `blocked_amount` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`owner_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `communication_credit_purchases` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `uuid` CHAR(36) NOT NULL,
    `owner_user_id` BIGINT UNSIGNED NOT NULL,
    `communication_credit_package_id` BIGINT UNSIGNED NOT NULL,
    `amount_snapshot` DECIMAL(12,2) NOT NULL,
    `bonus_snapshot` DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    `payment_method` ENUM('pix', 'wallet_balance') NOT NULL,
    `payment_reference_id` BIGINT UNSIGNED NULL DEFAULT NULL,
    `status` ENUM('creating', 'pending', 'paid', 'failed', 'expired', 'canceled') NOT NULL DEFAULT 'creating',
    `idempotency_key` VARCHAR(100) NOT NULL,
    `payment_data` JSON NULL DEFAULT NULL,
    `error_code` VARCHAR(100) NULL DEFAULT NULL,
    `expires_at` DATETIME NOT NULL,
    `pending_package_id` BIGINT UNSIGNED
        AS (CASE WHEN `status` IN ('creating', 'pending') THEN `communication_credit_package_id` ELSE NULL END) STORED,
    `created_at` DATETIME NOT NULL,
    `paid_at` DATETIME NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_communication_credit_purchase_uuid` (`uuid`),
    UNIQUE KEY `uk_communication_credit_purchase_idempotency` (`idempotency_key`),
    UNIQUE KEY `uk_communication_credit_purchase_open_package` (`owner_user_id`, `pending_package_id`),
    KEY `idx_communication_credit_purchase_owner_status` (`owner_user_id`, `status`, `created_at`, `id`),
    KEY `idx_communication_credit_purchase_expiration` (`status`, `expires_at`, `id`),
    KEY `idx_communication_credit_purchase_payment_reference` (`payment_method`, `payment_reference_id`),
    CONSTRAINT `fk_communication_credit_purchase_package`
        FOREIGN KEY (`communication_credit_package_id`) REFERENCES `communication_credit_packages` (`id`)
        ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `communication_credit_entries` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `owner_user_id` BIGINT UNSIGNED NOT NULL,
    `operation` ENUM('topup', 'hold', 'release', 'consume') NOT NULL,
    `amount` DECIMAL(12,2) NOT NULL,
    `source_type` VARCHAR(80) NOT NULL,
    `source_id` BIGINT UNSIGNED NOT NULL,
    `expires_at` DATETIME NULL DEFAULT NULL,
    `created_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_communication_credit_entry_source_operation`
        (`source_type`, `source_id`, `operation`),
    KEY `idx_communication_credit_entry_owner` (`owner_user_id`, `created_at`, `id`),
    KEY `idx_communication_credit_entry_expiry` (`operation`, `expires_at`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `communication_credit_alerts` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `owner_user_id` BIGINT UNSIGNED NOT NULL,
    `alert_type` ENUM('insufficient_credits') NOT NULL,
    `cooldown_until` DATETIME NOT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_communication_credit_alert_owner_type` (`owner_user_id`, `alert_type`),
    KEY `idx_communication_credit_alert_cooldown` (`cooldown_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `communication_credit_outbox` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `event_uuid` CHAR(36) NOT NULL,
    `event_type` VARCHAR(100) NOT NULL,
    `payload` JSON NOT NULL,
    `status` ENUM('pending', 'processing', 'published') NOT NULL DEFAULT 'pending',
    `attempts` INT UNSIGNED NOT NULL DEFAULT 0,
    `available_at` DATETIME NOT NULL,
    `published_at` DATETIME NULL DEFAULT NULL,
    `last_error` VARCHAR(255) NULL DEFAULT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_communication_credit_outbox_event_uuid` (`event_uuid`),
    KEY `idx_communication_credit_outbox_pending` (`status`, `available_at`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
-- services-banking-v2
-- ============================================================================
-- Não há DDL manual confirmado. Implementar o purpose
-- communication_credit_topup no fluxo de cobrança PIX existente e chamar a
-- Wallet com package_id + idempotency key após confirmação do pagamento.
