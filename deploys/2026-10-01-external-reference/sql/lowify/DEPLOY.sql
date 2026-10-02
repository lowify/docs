ALTER TABLE `sales`
    ADD COLUMN `external_reference` VARCHAR(100) NULL AFTER `transaction_id`;
