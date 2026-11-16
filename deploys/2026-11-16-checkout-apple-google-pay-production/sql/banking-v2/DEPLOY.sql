-- Executar uma única vez, somente se PRECHECK.sql retornar coluna e índice ausentes.
-- Executar no banco usado por services-banking-v2.

ALTER TABLE charges_card
    ADD COLUMN wallet_card_id INT UNSIGNED NULL DEFAULT NULL AFTER installments,
    ADD INDEX idx_charges_card_wallet_id (wallet_card_id, id);
