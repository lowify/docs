-- Banco: services-banking
-- Fase 01: preparação do ambiente.
-- Escopo: services-banking-v2
-- Objetivo: alterações manuais necessárias à integração Cielo.
-- Execução: manual, após revisão do schema do ambiente-alvo.

CREATE TABLE IF NOT EXISTS providers (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    code VARCHAR(45) NOT NULL,
    name VARCHAR(45) NOT NULL,
    active TINYINT UNSIGNED NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Não sobrescreve um provider que eventualmente já ocupe o id 4.
INSERT INTO providers (id, code, name, active, created_at)
SELECT 4, 'cielo_ecommerce', 'Cielo E-commerce', 1, CURRENT_TIMESTAMP
WHERE NOT EXISTS (SELECT 1 FROM providers WHERE id = 4 OR code = 'cielo_ecommerce');

CREATE TABLE IF NOT EXISTS baas_accounts (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    provider_id INT UNSIGNED NOT NULL,
    provider_account_id VARCHAR(255) NULL,
    provider_correlation_id VARCHAR(64) NULL,
    user_document VARCHAR(20) NULL,
    user_id INT NULL,
    status ENUM('created','pending','active','canceled') NOT NULL DEFAULT 'created',
    key_secret TEXT NULL,
    pix_key TEXT NULL,
    pix_type ENUM('evp') NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY baas_accounts_provider_id_index (provider_id),
    CONSTRAINT fk_bass_accounts_provider_id FOREIGN KEY (provider_id)
        REFERENCES providers (id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE baas_accounts
    ADD COLUMN IF NOT EXISTS provider_correlation_id VARCHAR(64) NULL AFTER provider_account_id,
    ADD COLUMN IF NOT EXISTS user_document VARCHAR(20) NULL AFTER provider_correlation_id;

CREATE TABLE IF NOT EXISTS baas_account_events (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    event_id VARCHAR(36) NOT NULL,
    baas_account_id INT UNSIGNED NOT NULL,
    status VARCHAR(20) NOT NULL,
    event VARCHAR(100) NOT NULL,
    date_created DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY idx_baas_account_events_event_id (event_id),
    KEY idx_baas_account_events_account_id (baas_account_id),
    KEY idx_baas_account_events_status (status),
    CONSTRAINT fk_baas_account_events_baas_account_id FOREIGN KEY (baas_account_id)
        REFERENCES baas_accounts (id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS baas_account_event_attempts (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    baas_account_event_id BIGINT UNSIGNED NOT NULL,
    error TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_baas_account_event_attempts_event_id (baas_account_event_id),
    CONSTRAINT fk_baas_account_event_attempts_event_id FOREIGN KEY (baas_account_event_id)
        REFERENCES baas_account_events (id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS charges_card (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    provider_transaction_id VARCHAR(100) NULL,
    provider_identifier VARCHAR(100) NOT NULL,
    account_id INT UNSIGNED NULL,
    status ENUM('created','pending','paid','requires_action','refused','refunded','failed','expired') NOT NULL DEFAULT 'created',
    total DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    installments INT NOT NULL DEFAULT 1,
    error_retry TINYINT UNSIGNED NOT NULL DEFAULT 0,
    token_charge VARCHAR(255) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY idx_charges_card_provider_transaction_id (provider_transaction_id),
    KEY idx_charges_card_account_id (account_id),
    CONSTRAINT fk_charges_card_account_id_baas_accounts_id FOREIGN KEY (account_id)
        REFERENCES baas_accounts (id) ON DELETE SET NULL ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE charges_card
    ADD COLUMN IF NOT EXISTS account_id INT UNSIGNED NULL AFTER provider_identifier,
    ADD INDEX IF NOT EXISTS idx_charges_card_account_id (account_id);

CREATE TABLE IF NOT EXISTS charge_card_events (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    charges_card_id INT UNSIGNED NOT NULL,
    source ENUM('api_create','api_retry','webhook') NOT NULL DEFAULT 'api_create',
    provider_status VARCHAR(100) NOT NULL,
    new_status VARCHAR(100) NOT NULL,
    error_code INT UNSIGNED NULL,
    error_message VARCHAR(255) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    CONSTRAINT charge_card_events_charges_card_id_foreign FOREIGN KEY (charges_card_id)
        REFERENCES charges_card (id) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS dispute_evidence_events (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    event_id VARCHAR(36) NOT NULL,
    sale_id INT UNSIGNED NOT NULL,
    event VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL,
    payload JSON NOT NULL,
    error TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY dispute_evidence_events_event_id_unique (event_id),
    KEY dispute_evidence_events_sale_id_index (sale_id),
    KEY dispute_evidence_events_status_index (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS dispute_evidence_event_attempts (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    dispute_evidence_event_id BIGINT UNSIGNED NOT NULL,
    error TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY dispute_evidence_event_attempts_dispute_evidence_event_id_index (dispute_evidence_event_id),
    CONSTRAINT fk_dispute_evidence_attempt_event FOREIGN KEY (dispute_evidence_event_id)
        REFERENCES dispute_evidence_events (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE charges_card
    ADD COLUMN IF NOT EXISTS purpose ENUM('checkout', 'billing') NOT NULL DEFAULT 'checkout' AFTER account_id,
    ADD INDEX IF NOT EXISTS idx_charges_card_purpose (purpose),
    ADD COLUMN IF NOT EXISTS order_id VARCHAR(32) NULL AFTER purpose,
    ADD INDEX IF NOT EXISTS idx_charges_card_order_id (order_id),
    ADD COLUMN IF NOT EXISTS is_disputed TINYINT(1) NOT NULL DEFAULT 0 AFTER status,
    ADD INDEX IF NOT EXISTS idx_charges_card_disputed_id (is_disputed, id);

ALTER TABLE baas_accounts
    ADD COLUMN IF NOT EXISTS metadata JSON NULL AFTER pix_type,
    ADD COLUMN IF NOT EXISTS internal_reference VARCHAR(36) NULL AFTER provider_correlation_id,
    ADD UNIQUE INDEX IF NOT EXISTS uq_baas_accounts_internal_reference (internal_reference);

CREATE TABLE IF NOT EXISTS charge_card_installments (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    charges_card_id INT UNSIGNED NOT NULL,
    installment_number TINYINT UNSIGNED NOT NULL,
    gross_amount DECIMAL(12,2) NOT NULL,
    expected_settlement_at DATETIME NOT NULL,
    liquidated_at DATETIME NULL,
    status ENUM('pending','paid','liquidated','refunded','cancelled') NOT NULL DEFAULT 'pending',
    provider_receivable_id VARCHAR(100) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_charge_card_installments_charge_number (charges_card_id, installment_number),
    KEY idx_charge_card_installments_status_expected_at (status, expected_settlement_at),
    KEY idx_charge_card_installments_provider_receivable_id (provider_receivable_id),
    CONSTRAINT fk_charge_card_installments_charge_card_id FOREIGN KEY (charges_card_id)
        REFERENCES charges_card (id) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS charge_card_installment_allocations (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    charge_card_installment_id INT UNSIGNED NOT NULL,
    recipient_type ENUM('producer','affiliate','platform') NOT NULL,
    seller_id INT UNSIGNED NULL,
    provider_merchant_id VARCHAR(100) NULL,
    gross_amount DECIMAL(12,2) NOT NULL,
    fee_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    net_amount DECIMAL(12,2) NOT NULL,
    refunded_amount DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    expected_settlement_at DATETIME NULL,
    liquidated_at DATETIME NULL,
    status ENUM('pending','paid','liquidated','refunded','cancelled') NOT NULL DEFAULT 'pending',
    provider_schedule_id VARCHAR(100) NULL,
    provider_receivable_id VARCHAR(100) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_charge_card_installment_allocations_installment_id (charge_card_installment_id),
    KEY idx_charge_card_installment_allocations_seller_id (seller_id),
    KEY idx_charge_card_installment_allocations_seller_type (seller_id, recipient_type),
    KEY idx_charge_card_installment_allocations_provider_merchant (provider_merchant_id),
    KEY idx_charge_card_installment_allocations_status_expected (status, expected_settlement_at),
    KEY idx_charge_card_installment_allocations_provider_schedule (provider_schedule_id),
    KEY idx_charge_card_installment_allocations_provider_receivable (provider_receivable_id),
    CONSTRAINT fk_charge_card_installment_allocations_installment_id FOREIGN KEY (charge_card_installment_id)
        REFERENCES charge_card_installments (id) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS refund_charge_card_installment_allocations (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    refund_charge_id INT UNSIGNED NOT NULL,
    charge_card_id INT UNSIGNED NOT NULL,
    charge_card_installment_id INT UNSIGNED NOT NULL,
    charge_card_installment_allocation_id INT UNSIGNED NOT NULL,
    installment_number TINYINT UNSIGNED NOT NULL,
    recipient_type VARCHAR(30) NOT NULL,
    seller_id INT UNSIGNED NULL,
    provider_merchant_id VARCHAR(100) NULL,
    amount DECIMAL(12,2) NOT NULL,
    status ENUM('pending','approved','failed') NOT NULL DEFAULT 'pending',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_refund_card_allocations_refund_charge_id (refund_charge_id),
    KEY idx_refund_card_allocations_charge_card_id (charge_card_id),
    KEY idx_refund_card_allocations_allocation_id (charge_card_installment_allocation_id),
    KEY idx_refund_card_allocations_status (status),
    CONSTRAINT fk_refund_card_allocations_refund_charge_id FOREIGN KEY (refund_charge_id)
        REFERENCES refunds_charge (id) ON DELETE CASCADE ON UPDATE NO ACTION,
    CONSTRAINT fk_refund_card_allocations_charge_card_id FOREIGN KEY (charge_card_id)
        REFERENCES charges_card (id) ON DELETE CASCADE ON UPDATE NO ACTION,
    CONSTRAINT fk_refund_card_allocations_installment_id FOREIGN KEY (charge_card_installment_id)
        REFERENCES charge_card_installments (id) ON DELETE CASCADE ON UPDATE NO ACTION,
    CONSTRAINT fk_refund_card_allocations_allocation_id FOREIGN KEY (charge_card_installment_allocation_id)
        REFERENCES charge_card_installment_allocations (id) ON DELETE CASCADE ON UPDATE NO ACTION
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO providers (code, name, active, created_at)
SELECT 'pagarme_psp', 'Pagar.me PSP', 1, CURRENT_TIMESTAMP
WHERE NOT EXISTS (SELECT 1 FROM providers WHERE code = 'pagarme_psp');
