-- Pesquisa somente-leitura para planejar a migração de contas da fase 1.
-- Execute na base de produção (preferencialmente em uma réplica de leitura).
-- Não contém UPDATE, INSERT, DELETE, DDL ou execução de migração.
-- Os horários usam o fuso configurado no banco.

SET @as_of := NOW();
SET @d30 := DATE_SUB(@as_of, INTERVAL 30 DAY);
SET @d60 := DATE_SUB(@as_of, INTERVAL 60 DAY);
SET @d90 := DATE_SUB(@as_of, INTERVAL 90 DAY);

-- 1. Cobertura das fontes. Só use auth_sessions como métrica de 90 dias se
-- oldest_record for anterior a @d90.
SELECT
    'auth_sessions' AS source,
    MIN(created_at) AS oldest_record,
    MAX(created_at) AS newest_record,
    COUNT(*) AS records
FROM auth_sessions

UNION ALL

SELECT
    'user_activity_logs',
    MIN(created_at),
    MAX(created_at),
    COUNT(*)
FROM user_activity_logs

UNION ALL

SELECT
    'sales',
    MIN(sale_timestamp),
    MAX(sale_timestamp),
    COUNT(*)
FROM sales;

-- 2. Total da fase 1 e métricas cumulativas de atividade.
-- Venda paga e saldo são os sinais prioritários, pois a migração bloqueia
-- saque enquanto cadastro/revisão da fase 2 não estiverem aprovados.
SELECT
    COUNT(*) AS phase_1_total,
    COALESCE(SUM(login.last_login >= @d30), 0) AS login_30d,
    COALESCE(SUM(login.last_login >= @d60), 0) AS login_60d,
    COALESCE(SUM(login.last_login >= @d90), 0) AS login_90d,
    COALESCE(SUM(activity.last_activity >= @d30), 0) AS dashboard_30d,
    COALESCE(SUM(activity.last_activity >= @d60), 0) AS dashboard_60d,
    COALESCE(SUM(activity.last_activity >= @d90), 0) AS dashboard_90d,
    COALESCE(SUM(sale.last_paid_sale >= @d30), 0) AS sellers_paid_sale_30d,
    COALESCE(SUM(sale.last_paid_sale >= @d60), 0) AS sellers_paid_sale_60d,
    COALESCE(SUM(sale.last_paid_sale >= @d90), 0) AS sellers_paid_sale_90d
FROM tbl_usuarios u
LEFT JOIN (
    SELECT user_id, MAX(created_at) AS last_login
    FROM auth_sessions
    WHERE created_at >= @d90
    GROUP BY user_id
) login ON login.user_id = u.id_user
LEFT JOIN (
    SELECT user_id, MAX(created_at) AS last_activity
    FROM user_activity_logs
    WHERE created_at >= @d90
    GROUP BY user_id
) activity ON activity.user_id = u.id_user
LEFT JOIN (
    SELECT id_usuario, MAX(sale_timestamp) AS last_paid_sale
    FROM sales
    WHERE status = 'paid'
      AND sale_timestamp >= @d90
    GROUP BY id_usuario
) sale ON sale.id_usuario = u.id_user
WHERE u.account_phase = 1;

-- 3. Elegibilidade operacional e divisão PF/PJ.
-- PJ-CPF cria sócio na migração; PJ-CNPJ preserva o fluxo PJ.
SELECT
    CASE
        WHEN LOWER(COALESCE(u.tipo_conta, '')) <> 'pj' THEN 'pf'
        WHEN CHAR_LENGTH(REGEXP_REPLACE(COALESCE(u.cpf, ''), '[^0-9]', '')) = 14 THEN 'pj_cnpj'
        ELSE 'pj_cpf'
    END AS migration_mode,
    COUNT(*) AS total,
    SUM(u.account_review_status IS NULL) AS eligible_now,
    SUM(u.account_review_status IS NOT NULL) AS review_state_conflict
FROM tbl_usuarios u
WHERE u.account_phase = 1
GROUP BY migration_mode
ORDER BY migration_mode;

-- 4. Prontidão documental, usando a mesma regra do migrador:
-- selfie + CNH única, ou selfie + frente/verso de CNH, ou selfie + RG frente/verso.
SELECT
    tipo_conta,
    COUNT(*) AS total,
    SUM(personal_documents_complete) AS documents_complete,
    SUM(NOT personal_documents_complete) AS documents_incomplete
FROM (
    SELECT
        u.id_user,
        CASE WHEN LOWER(COALESCE(u.tipo_conta, '')) = 'pj' THEN 'pj' ELSE 'pf' END AS tipo_conta,
        (
            MAX(CASE WHEN d.type = 'selfie' AND d.status IN ('pending', 'approved') THEN 1 ELSE 0 END) = 1
            AND (
                MAX(CASE WHEN d.type = 'driver_license' AND d.status IN ('pending', 'approved') THEN 1 ELSE 0 END) = 1
                OR (
                    MAX(CASE WHEN d.type = 'driver_license_front' AND d.status IN ('pending', 'approved') THEN 1 ELSE 0 END) = 1
                    AND MAX(CASE WHEN d.type = 'driver_license_back' AND d.status IN ('pending', 'approved') THEN 1 ELSE 0 END) = 1
                )
                OR (
                    MAX(CASE WHEN d.type = 'identity_card_front' AND d.status IN ('pending', 'approved') THEN 1 ELSE 0 END) = 1
                    AND MAX(CASE WHEN d.type = 'identity_card_back' AND d.status IN ('pending', 'approved') THEN 1 ELSE 0 END) = 1
                )
            )
        ) AS personal_documents_complete
    FROM tbl_usuarios u
    LEFT JOIN documents d
        ON d.owner_type = 'user'
       AND d.owner_id = u.id_user
    WHERE u.account_phase = 1
    GROUP BY u.id_user, u.tipo_conta
) readiness
GROUP BY tipo_conta
ORDER BY tipo_conta;

-- 5. Exposição financeira atual da fase 1. A lógica de saldo é a mesma usada
-- na listagem administrativa: último registro de extract por seller.
SELECT
    COUNT(*) AS phase_1_total,
    SUM(COALESCE(balance.balance, 0) > 0) AS sellers_with_positive_balance,
    SUM(COALESCE(balance.balance, 0) <= 0) AS sellers_without_positive_balance,
    COALESCE(SUM(GREATEST(COALESCE(balance.balance, 0), 0)), 0) AS total_positive_balance
FROM tbl_usuarios u
LEFT JOIN (
    SELECT e.id_usuario, e.balance
    FROM extract e
    INNER JOIN (
        SELECT id_usuario, MAX(id) AS last_id
        FROM extract
        GROUP BY id_usuario
    ) last_extract
        ON last_extract.id_usuario = e.id_usuario
       AND last_extract.last_id = e.id
) balance ON balance.id_usuario = u.id_user
WHERE u.account_phase = 1;

-- 6. Prévia do lote inicial de menor risco. Retorna somente IDs e atributos
-- operacionais: fase 1, sem saldo positivo, sem venda paga, login ou atividade
-- nos últimos 90 dias e sem conflito de revisão. Não migra nenhuma conta.
SELECT
    u.id_user,
    CASE
        WHEN LOWER(COALESCE(u.tipo_conta, '')) <> 'pj' THEN 'pf'
        WHEN CHAR_LENGTH(REGEXP_REPLACE(COALESCE(u.cpf, ''), '[^0-9]', '')) = 14 THEN 'pj_cnpj'
        ELSE 'pj_cpf'
    END AS migration_mode,
    COALESCE(balance.balance, 0) AS current_balance
FROM tbl_usuarios u
LEFT JOIN (
    SELECT user_id, MAX(created_at) AS last_login
    FROM auth_sessions
    WHERE created_at >= @d90
    GROUP BY user_id
) login ON login.user_id = u.id_user
LEFT JOIN (
    SELECT user_id, MAX(created_at) AS last_activity
    FROM user_activity_logs
    WHERE created_at >= @d90
    GROUP BY user_id
) activity ON activity.user_id = u.id_user
LEFT JOIN (
    SELECT id_usuario, MAX(sale_timestamp) AS last_paid_sale
    FROM sales
    WHERE status = 'paid'
      AND sale_timestamp >= @d90
    GROUP BY id_usuario
) sale ON sale.id_usuario = u.id_user
LEFT JOIN (
    SELECT e.id_usuario, e.balance
    FROM extract e
    INNER JOIN (
        SELECT id_usuario, MAX(id) AS last_id
        FROM extract
        GROUP BY id_usuario
    ) last_extract
        ON last_extract.id_usuario = e.id_usuario
       AND last_extract.last_id = e.id
) balance ON balance.id_usuario = u.id_user
WHERE u.account_phase = 1
  AND u.account_review_status IS NULL
  AND COALESCE(balance.balance, 0) <= 0
  AND login.last_login IS NULL
  AND activity.last_activity IS NULL
  AND sale.last_paid_sale IS NULL
ORDER BY u.id_user
LIMIT 100;
