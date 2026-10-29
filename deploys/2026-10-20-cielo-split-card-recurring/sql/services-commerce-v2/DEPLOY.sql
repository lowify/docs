-- Banco: services-commerce-v2
-- Escopo: eventos e etapas idempotentes de cobrança recorrente Cielo.
-- Execução: manual, antes de habilitar processo ou seller piloto.
-- Seguro para reaplicação: cria somente estruturas ausentes.

CREATE TABLE IF NOT EXISTS `cielo_recurring_sale_events` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `sale_id` BIGINT UNSIGNED NOT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
    `triggered_at` DATETIME NOT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    `last_error` VARCHAR(255) NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `cielo_recurring_sale_events_sale_id_unique` (`sale_id`),
    KEY `idx_cielo_recurring_sale_events_pending` (`status`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `cielo_recurring_sale_events`
    ADD COLUMN IF NOT EXISTS `claim_token` VARCHAR(32) NULL,
    ADD COLUMN IF NOT EXISTS `attempts` INT UNSIGNED NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS `available_at` DATETIME NULL;

CREATE TABLE IF NOT EXISTS `cielo_recurring_sale_event_steps` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `event_id` BIGINT UNSIGNED NOT NULL,
    `step` VARCHAR(40) NOT NULL,
    `status` VARCHAR(20) NOT NULL,
    `created_at` DATETIME NOT NULL,
    `updated_at` DATETIME NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_cielo_recurring_sale_event_step` (`event_id`, `step`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
