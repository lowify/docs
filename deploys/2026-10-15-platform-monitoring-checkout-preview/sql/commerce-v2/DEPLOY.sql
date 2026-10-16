ALTER TABLE `sales_delivery`
    ADD KEY `idx_sales_delivery_owner_created` (`owner_user_id`, `created_at`, `id`);

ALTER TABLE `sale_recovery_dispatches`
    ADD KEY `idx_sale_recovery_owner_created` (`owner_user_id`, `created_at`, `id`);
