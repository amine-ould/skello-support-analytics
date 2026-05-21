-- =============================================================================
-- dashboard_queries.sql  (DuckDB)
-- Les 6 requêtes qui alimentent le dashboard de Lorette, exécutables sur le
-- mart. Toutes opèrent sur fct_conversations / int_admin_messages.
--
-- Note importante : le dataset s'arrête en janvier 2022. Pour montrer un
-- résultat parlant, on ne peut pas faire "semaine en cours vs S-1" relatif à
-- CURRENT_DATE — on utilise une semaine de référence sur les données réelles.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Q1. Bandeau KPI — semaine la plus récente vs précédente
-- -----------------------------------------------------------------------------
WITH ref_week AS (
    SELECT MAX(conversation_created_week) AS w
    FROM marts.fct_conversations
    WHERE is_handled_by_support
)
SELECT
    conversation_created_week,
    CASE WHEN conversation_created_week = (SELECT w FROM ref_week) THEN 'S-1' ELSE 'S-2' END AS label,
    COUNT(*)                                                                AS volume,
    ROUND(AVG(CASE WHEN is_replied_under_5min THEN 100.0 ELSE 0 END), 1)    AS pct_under_5min,
    ROUND(AVG(CASE WHEN is_csat_positive       THEN 100.0 ELSE 0 END), 1)   AS pct_csat_positive,
    ROUND(AVG(CASE WHEN has_csat               THEN 100.0 ELSE 0 END), 1)   AS pct_csat_response,
    ROUND(MEDIAN(resolution_minutes), 1)                                    AS median_resolution_min
FROM marts.fct_conversations
WHERE is_handled_by_support
  AND conversation_created_week IN (
      (SELECT w FROM ref_week),
      (SELECT w - INTERVAL 7 DAY FROM ref_week)
  )
GROUP BY conversation_created_week
ORDER BY conversation_created_week DESC;


-- -----------------------------------------------------------------------------
-- Q2. Performance individuelle (tableau par agent — sur tout le dataset)
-- -----------------------------------------------------------------------------
SELECT
    a.first_name                                                            AS agent,
    COUNT(DISTINCT CASE WHEN f.first_responder_admin_id = a.admin_id
                        THEN f.conversation_id END)                         AS nb_first_replied,
    ROUND(MEDIAN(CASE WHEN f.first_responder_admin_id = a.admin_id
                      THEN f.frt_minutes END), 1)                           AS median_frt_min,
    ROUND(AVG(CASE WHEN f.first_responder_admin_id = a.admin_id
                   THEN CASE WHEN f.is_replied_under_5min THEN 100.0 ELSE 0 END END), 1) AS pct_under_5min,
    COUNT(DISTINCT CASE WHEN f.csat_rated_teammate_id = a.admin_id
                        AND f.has_csat THEN f.conversation_id END)          AS nb_csat,
    ROUND(AVG(CASE WHEN f.csat_rated_teammate_id = a.admin_id
                   THEN f.csat_rating END), 2)                              AS avg_csat,
    ROUND(AVG(CASE WHEN f.csat_rated_teammate_id = a.admin_id
                   THEN CASE WHEN f.is_csat_positive THEN 100.0 ELSE 0 END END), 1) AS pct_csat_positive
FROM marts.dim_support_agents a
CROSS JOIN marts.fct_conversations f
GROUP BY a.first_name
ORDER BY pct_csat_positive DESC NULLS LAST;


-- -----------------------------------------------------------------------------
-- Q3. Heatmap activité : volume conv ouvertes par jour × heure (28 derniers jours)
-- -----------------------------------------------------------------------------
WITH max_date AS (
    SELECT MAX(conversation_created_at) AS d FROM marts.fct_conversations WHERE is_handled_by_support
)
SELECT
    EXTRACT(isodow FROM conversation_created_at)            AS day_iso,
    dayname(conversation_created_at)                        AS day_name,
    EXTRACT(hour   FROM conversation_created_at)            AS hour,
    COUNT(*)                                                AS nb_conversations
FROM marts.fct_conversations
WHERE is_handled_by_support
  AND conversation_created_at >= (SELECT d - INTERVAL 28 DAY FROM max_date)
GROUP BY 1, 2, 3
ORDER BY 1, 3;


-- -----------------------------------------------------------------------------
-- Q4. Évolution FRT et CSAT par semaine
-- -----------------------------------------------------------------------------
SELECT
    conversation_created_week,
    COUNT(*)                                                                AS volume,
    ROUND(AVG(CASE WHEN is_replied_under_5min THEN 100.0 ELSE 0 END), 1)    AS pct_under_5min,
    ROUND(AVG(CASE WHEN is_csat_positive AND has_csat THEN 100.0
                   WHEN has_csat                        THEN 0
                   ELSE NULL END), 1)                                        AS pct_csat_positive,
    ROUND(MEDIAN(frt_minutes), 1)                                           AS median_frt_min
FROM marts.fct_conversations
WHERE is_handled_by_support
GROUP BY conversation_created_week
ORDER BY conversation_created_week;


-- -----------------------------------------------------------------------------
-- Q5. Distribution du FRT par bucket (sur tout le scope Support)
-- -----------------------------------------------------------------------------
SELECT
    frt_bucket,
    COUNT(*)                                                AS nb_conversations,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)      AS pct
FROM marts.fct_conversations
WHERE is_handled_by_support
GROUP BY frt_bucket
ORDER BY CASE frt_bucket
    WHEN 'under_1_min'    THEN 1
    WHEN 'under_5_min'    THEN 2
    WHEN 'under_30_min'   THEN 3
    WHEN 'under_2_hours'  THEN 4
    WHEN 'under_1_day'    THEN 5
    WHEN 'over_1_day'     THEN 6
    ELSE 7
END;


-- -----------------------------------------------------------------------------
-- Q6. Top tags (sujets) sur les conv Support
-- -----------------------------------------------------------------------------
SELECT
    tag_name,
    COUNT(*) AS nb_conversations
FROM (
    SELECT UNNEST(tag_names) AS tag_name
    FROM marts.fct_conversations
    WHERE is_handled_by_support
      AND tag_names IS NOT NULL
) t
GROUP BY tag_name
ORDER BY nb_conversations DESC
LIMIT 15;
