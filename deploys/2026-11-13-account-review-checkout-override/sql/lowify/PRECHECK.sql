SELECT
    column_name,
    column_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'lowify'
  AND table_name = 'tbl_usuarios'
  AND column_name = 'checkout_review_approved_override';
