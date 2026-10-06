CREATE TABLE affiliate_bans (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    product_id INT UNSIGNED NOT NULL,
    owner_user_id INT UNSIGNED NOT NULL,
    affiliated_user_id INT UNSIGNED NOT NULL,
    reason TEXT NOT NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    banned_by_user_id INT UNSIGNED NOT NULL,
    banned_at DATETIME NOT NULL,
    revoked_by_user_id INT UNSIGNED NULL,
    revoked_at DATETIME NULL,
    UNIQUE KEY affiliate_bans_scope_unique (product_id, owner_user_id, affiliated_user_id),
    KEY affiliate_bans_active_scope_idx (product_id, owner_user_id, affiliated_user_id, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE affiliate_ban_events (
    id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    affiliate_ban_id INT UNSIGNED NOT NULL,
    event_type ENUM('banned', 'revoked') NOT NULL,
    actor_user_id INT UNSIGNED NOT NULL,
    reason TEXT NULL,
    created_at DATETIME NOT NULL,
    KEY affiliate_ban_events_ban_created_idx (affiliate_ban_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
