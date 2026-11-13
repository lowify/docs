ALTER TABLE tbl_usuarios
    ADD COLUMN checkout_review_approved_override TINYINT(1) NOT NULL DEFAULT 0
    AFTER account_review_status;
