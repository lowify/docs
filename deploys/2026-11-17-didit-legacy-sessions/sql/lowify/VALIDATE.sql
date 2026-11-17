SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    COLUMN_NAME,
    COLUMN_TYPE,
    IS_NULLABLE,
    COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'lowify'
  AND TABLE_NAME = 'user_verification_sessions'
  AND COLUMN_NAME = 'provider';

-- Resultado esperado:
-- enum('didit','didit_legacy','local') | YES | NULL
