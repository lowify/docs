-- Banco: services-commerce-v2
-- Confirma as estruturas manuais da recorrência Cielo.

SELECT table_name, column_name, column_type, is_nullable
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND (
      (table_name = 'cielo_recurring_sale_events' AND column_name IN ('id', 'sale_id', 'status', 'claim_token', 'attempts', 'available_at'))
      OR (table_name = 'cielo_recurring_sale_event_steps' AND column_name IN ('id', 'event_id', 'step', 'status'))
  )
ORDER BY table_name, ordinal_position;

SELECT table_name, index_name, non_unique, column_name, seq_in_index
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name IN ('cielo_recurring_sale_events', 'cielo_recurring_sale_event_steps')
  AND index_name IN ('PRIMARY', 'cielo_recurring_sale_events_sale_id_unique', 'idx_cielo_recurring_sale_events_pending', 'uk_cielo_recurring_sale_event_step')
ORDER BY table_name, index_name, seq_in_index;
