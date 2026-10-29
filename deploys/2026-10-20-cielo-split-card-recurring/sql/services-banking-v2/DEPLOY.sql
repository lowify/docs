-- Banco: services-banking-v2
-- Escopo: recorrência programada Cielo Split.
-- Execução: manual, antes de habilitar processo ou seller piloto.
-- Seguro para reaplicação: somente adiciona colunas ausentes.

ALTER TABLE `subscriptions`
    ADD COLUMN IF NOT EXISTS `metadata` TEXT NULL;

ALTER TABLE `subscriptions_charge`
    ADD COLUMN IF NOT EXISTS `cielo_split_state` VARCHAR(20) NULL;
