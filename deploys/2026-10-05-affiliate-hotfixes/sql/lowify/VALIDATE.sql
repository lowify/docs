SELECT
    table_name,
    table_type
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN ('affiliate_bans', 'affiliate_ban_events')
ORDER BY table_name;

SELECT
    table_name,
    column_name,
    column_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name IN ('affiliate_bans', 'affiliate_ban_events')
ORDER BY table_name, ordinal_position;
