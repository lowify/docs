-- Deploy: comunicações de venda
-- Banco do Banking V2
-- Execute manualmente antes de subir services-banking-v2.

ALTER TABLE pix_charges
  MODIFY purpose ENUM('checkout', 'billing', 'communication_credit_topup') NOT NULL DEFAULT 'checkout';

ALTER TABLE pix_charges
  ADD COLUMN communication_credit_purchase_uuid VARCHAR(36) NULL AFTER purpose,
  ADD COLUMN communication_credit_payment_data JSON NULL AFTER communication_credit_purchase_uuid,
  ADD UNIQUE KEY uk_pix_charges_communication_credit_purchase_uuid (communication_credit_purchase_uuid);
