-- Banco: lowify
-- Fase 01: preparação do ambiente.
-- Escopo: services-account e services-commerce-v2
-- Objetivo: alterações manuais necessárias à integração Cielo.
-- Execução: manual, após revisão do schema do ambiente-alvo.

-- services-account: suporte ao onboarding e comprovante bancário.
ALTER TABLE user_events
    ADD COLUMN IF NOT EXISTS payload JSON NULL AFTER event;

ALTER TABLE user_verification_sessions
    MODIFY COLUMN type ENUM('full','document','selfie','personal_full','personal_document','personal_selfie','business_contract_social','business_proof_of_registration','proof_of_bank_domicile') NULL AFTER status;

ALTER TABLE documents
    MODIFY COLUMN type ENUM('selfie','driver_license','ata','social_contract','bylaws','driver_license_front','driver_license_back','identity_card_front','identity_card_back','proof_of_registration','proof_of_bank_domicile') NOT NULL,
    MODIFY COLUMN owner_type ENUM('user','partner','account_bank') NOT NULL;

CREATE TABLE IF NOT EXISTS user_account_bank (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NOT NULL,
    uuid CHAR(36) NOT NULL,
    bank VARCHAR(3) NOT NULL,
    bank_account_type ENUM('checking','savings','salary') NOT NULL,
    number VARCHAR(30) NOT NULL,
    operation VARCHAR(10) NULL,
    verifier_digit VARCHAR(5) NOT NULL,
    agency_number VARCHAR(20) NOT NULL,
    agency_digit VARCHAR(5) NOT NULL,
    validation_status ENUM('pending','awaiting_analysis','document_rejected','approved','removed') NOT NULL DEFAULT 'pending',
    created_at DATETIME NOT NULL,
    updated_at DATETIME NULL,
    removed_at DATETIME NULL,
    PRIMARY KEY (id),
    UNIQUE KEY user_account_bank_uuid_unique (uuid),
    KEY user_account_bank_user_id_index (user_id),
    KEY user_account_bank_removed_at_index (removed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS user_account_bank_addicional (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_account_bank_id BIGINT UNSIGNED NOT NULL,
    attribute_key VARCHAR(100) NOT NULL,
    value TEXT NULL,
    updated_at DATETIME NULL,
    PRIMARY KEY (id),
    UNIQUE KEY user_account_bank_addicional_unique_key (user_account_bank_id, attribute_key),
    KEY user_account_bank_addicional_user_account_bank_id_index (user_account_bank_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- As cinco colunas abaixo pertenciam a uma versão intermediária e foram
-- removidas pela migration posterior. O estado final usa a tabela adicional.
ALTER TABLE user_account_bank
    DROP COLUMN IF EXISTS cielo_seller_merchant_id,
    DROP COLUMN IF EXISTS cielo_split_status,
    DROP COLUMN IF EXISTS cielo_split_reason_code,
    DROP COLUMN IF EXISTS cielo_split_rejection_message,
    DROP COLUMN IF EXISTS cielo_split_status_updated_at;

CREATE TABLE IF NOT EXISTS review_cases (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    subject_type VARCHAR(80) NOT NULL,
    subject_id BIGINT UNSIGNED NOT NULL,
    owner_user_id BIGINT UNSIGNED NOT NULL,
    status ENUM('pending','in_review','approved','resubmission_requested','rejected') NOT NULL,
    reviewed_by BIGINT UNSIGNED NULL,
    final_observation TEXT NULL,
    metadata JSON NULL,
    created_at DATETIME NOT NULL,
    started_at DATETIME NULL,
    completed_at DATETIME NULL,
    PRIMARY KEY (id),
    KEY review_cases_owner_user_id_index (owner_user_id),
    KEY review_cases_subject_status (subject_type, subject_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS review_case_events (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    review_case_id BIGINT UNSIGNED NOT NULL,
    event_type VARCHAR(80) NOT NULL,
    actor_user_id BIGINT UNSIGNED NULL,
    from_status VARCHAR(40) NULL,
    to_status VARCHAR(40) NULL,
    observation TEXT NULL,
    metadata JSON NULL,
    created_at DATETIME NOT NULL,
    PRIMARY KEY (id),
    KEY review_case_events_review_case_id_index (review_case_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- A coluna é compartilhada por Account e Commerce; aplicar uma única vez.
ALTER TABLE tbl_usuarios
    ADD COLUMN IF NOT EXISTS card_integration_enabled TINYINT(1) NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_tbl_usuarios_card_integration_enabled
    ON tbl_usuarios (card_integration_enabled);

-- services-commerce-v2: gateways, regras de liquidação e meios de pagamento.
INSERT INTO tbl_gateways (nome, identificador, status, cash_in, cash_out)
VALUES ('Cielo E-commerce', 'cielo_ecommerce', 'active', 1, NULL)
ON DUPLICATE KEY UPDATE nome = VALUES(nome), status = VALUES(status), cash_in = VALUES(cash_in);

INSERT INTO tbl_gateways (nome, identificador, status, cash_in, cash_out)
VALUES ('Pagar.me PSP', 'pagarme_psp', 'active', 1, NULL)
ON DUPLICATE KEY UPDATE nome = VALUES(nome), status = VALUES(status), cash_in = VALUES(cash_in);

ALTER TABLE sales_affiliates
    ADD COLUMN IF NOT EXISTS settlement_method ENUM('wallet','gateway_split') NOT NULL DEFAULT 'wallet' AFTER status,
    ADD INDEX IF NOT EXISTS idx_sales_affiliates_settlement_method (settlement_method);

ALTER TABLE disputes
    ADD COLUMN IF NOT EXISTS should_block_balance TINYINT(1) NOT NULL DEFAULT 1 AFTER amount_affiliate_blocked,
    ADD INDEX IF NOT EXISTS idx_disputes_should_block_status_seller (should_block_balance, status, seller_id),
    ADD INDEX IF NOT EXISTS idx_disputes_should_block_status_affiliate (should_block_balance, status, user_affiliate_id);

ALTER TABLE tbl_produtos
    ADD COLUMN IF NOT EXISTS pix_enabled TINYINT UNSIGNED NOT NULL DEFAULT 1 AFTER preco,
    ADD COLUMN IF NOT EXISTS credit_card_enabled TINYINT UNSIGNED NOT NULL DEFAULT 0 AFTER pix_enabled,
    ADD COLUMN IF NOT EXISTS credit_card_installments TINYINT UNSIGNED NOT NULL DEFAULT 1 AFTER credit_card_enabled;

ALTER TABLE tbl_usuarios
    ADD COLUMN IF NOT EXISTS gateway_prioritario_checkout_card VARCHAR(255) NULL AFTER gateway_prioritario;

INSERT INTO system_vars (var_key, var_value)
VALUES ('gateway_default_checkout_card', 'cielo_ecommerce')
ON DUPLICATE KEY UPDATE var_value = var_value;
