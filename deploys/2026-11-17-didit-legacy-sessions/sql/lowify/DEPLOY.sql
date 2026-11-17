ALTER TABLE lowify.user_verification_sessions
    MODIFY COLUMN provider ENUM('didit', 'didit_legacy', 'local') NULL DEFAULT NULL;
