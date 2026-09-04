-- Banco: services-banking
-- Fase 01: preparação do ambiente.
-- Escopo: services-banking-v2
-- Objetivo: validar as alterações aplicadas por DEPLOY.sql.
-- Execução: somente leitura.

SELECT table_name
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN (
    'providers', 'baas_accounts', 'baas_account_events', 'baas_account_event_attempts',
    'charges_card', 'charge_card_events', 'charge_card_installments',
    'charge_card_installment_allocations', 'refund_charge_card_installment_allocations',
    'dispute_evidence_events', 'dispute_evidence_event_attempts'
  );

-- Inventário completo: usar para comparar as tabelas existentes com DEPLOY.sql.
SELECT table_name, ordinal_position, column_name, column_type, is_nullable, column_default, extra
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name IN (
    'providers', 'baas_accounts', 'baas_account_events', 'baas_account_event_attempts',
    'charges_card', 'charge_card_events', 'charge_card_installments',
    'charge_card_installment_allocations', 'refund_charge_card_installment_allocations',
    'dispute_evidence_events', 'dispute_evidence_event_attempts'
  )
ORDER BY table_name, ordinal_position;

SELECT table_name, column_name, column_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND (
    (table_name = 'baas_accounts' AND column_name IN (
        'provider_correlation_id', 'user_document', 'user_id', 'metadata', 'internal_reference'
    ))
    OR (table_name = 'charges_card' AND column_name IN ('account_id', 'purpose', 'order_id', 'is_disputed'))
    OR (table_name = 'charge_card_installment_allocations' AND column_name IN (
        'provider_merchant_id', 'refunded_amount', 'expected_settlement_at',
        'liquidated_at', 'status', 'provider_schedule_id', 'provider_receivable_id'
    ))
  )
ORDER BY table_name, ordinal_position;

SELECT table_name, index_name, column_name, seq_in_index
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND index_name IN (
    'idx_charges_card_provider_transaction_id', 'idx_charges_card_account_id',
    'idx_charges_card_purpose', 'idx_charges_card_order_id', 'idx_charges_card_disputed_id',
    'uq_baas_accounts_internal_reference',
    'uq_charge_card_installments_charge_number', 'idx_charge_card_installments_status_expected_at',
    'idx_refund_card_allocations_refund_charge_id',
    'idx_baas_account_events_event_id', 'dispute_evidence_events_event_id_unique'
  )
ORDER BY table_name, index_name, seq_in_index;

SELECT table_name, constraint_name, referenced_table_name
FROM information_schema.key_column_usage
WHERE table_schema = DATABASE()
  AND referenced_table_name IS NOT NULL
  AND table_name IN ('baas_accounts', 'baas_account_events', 'baas_account_event_attempts', 'charges_card', 'charge_card_events', 'dispute_evidence_event_attempts');

SELECT id, code, name, active
FROM providers
WHERE code IN ('cielo_ecommerce', 'pagarme_psp') OR id = 4;

-- Executar individualmente quando suportado pelo cliente SQL para obter o DDL exato:
-- SHOW CREATE TABLE providers;
-- SHOW CREATE TABLE baas_accounts;
-- SHOW CREATE TABLE baas_account_events;
-- SHOW CREATE TABLE baas_account_event_attempts;
-- SHOW CREATE TABLE charges_card;
-- SHOW CREATE TABLE charge_card_events;
