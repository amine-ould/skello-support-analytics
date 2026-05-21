-- =============================================================================
-- int_admin_messages  (DuckDB)
-- 1 ligne = 1 message d'admin humain. Sert aux analyses de charge horaire,
-- heatmap d'activité, et performance individuelle.
-- =============================================================================

CREATE OR REPLACE TABLE intermediate.int_admin_messages AS

SELECT
    part_id,
    conversation_id,
    author_id                                       AS admin_id,
    created_at                                      AS sent_at,
    CAST(created_at AS DATE)                        AS sent_date,
    EXTRACT(HOUR    FROM created_at)                AS sent_hour,
    -- isodow : 1=lundi ... 7=dimanche (norme ISO 8601)
    EXTRACT(isodow  FROM created_at)                AS sent_day_of_week_iso,
    dayname(created_at)                             AS sent_day_name,
    EXTRACT(isoyear FROM created_at)                AS sent_year_iso,
    EXTRACT(week    FROM created_at)                AS sent_week_iso,
    -- Date du lundi de la semaine (pour groupages hebdo)
    date_trunc('week', created_at)                  AS sent_week_start
FROM staging.stg_intercom__conversation_parts
WHERE is_message = TRUE
  AND is_admin   = TRUE
  AND is_bot     = FALSE;
