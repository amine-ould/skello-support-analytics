-- =============================================================================
-- fct_agent_daily_activity  (DuckDB)
-- 1 ligne = 1 agent × 1 jour. Sert au tableau de comparaison hebdo par agent
-- et à la heatmap d'activité.
-- =============================================================================

CREATE OR REPLACE TABLE marts.fct_agent_daily_activity AS

WITH spine AS (
    SELECT
        a.admin_id,
        a.first_name,
        d.date_day,
        d.week_start_date,
        d.day_of_week_iso,
        d.day_name
    FROM marts.dim_support_agents a
    CROSS JOIN marts.dim_date d
    WHERE d.date_day BETWEEN DATE '2021-10-01' AND CURRENT_DATE
      AND a.is_active = TRUE
),

daily_messages AS (
    SELECT
        admin_id,
        sent_date,
        COUNT(*)                                AS nb_messages_sent,
        COUNT(DISTINCT conversation_id)         AS nb_conversations_touched
    FROM intermediate.int_admin_messages
    GROUP BY admin_id, sent_date
),

daily_first_response AS (
    SELECT
        f.first_responder_admin_id              AS admin_id,
        CAST(f.first_admin_reply_at AS DATE)    AS response_date,
        COUNT(*)                                AS nb_conversations_first_replied,
        AVG(f.frt_minutes)                      AS avg_frt_minutes,
        MEDIAN(f.frt_minutes)                   AS median_frt_minutes,
        AVG(CASE WHEN f.is_replied_under_5min THEN 1.0 ELSE 0.0 END) * 100 AS pct_under_5min
    FROM intermediate.int_conversation_first_response f
    WHERE f.first_responder_admin_id IS NOT NULL
    GROUP BY 1, 2
),

daily_csat AS (
    SELECT
        csat_rated_teammate_id                  AS admin_id,
        CAST(csat_created_at AS DATE)           AS csat_date,
        COUNT(*)                                AS nb_csat_received,
        AVG(csat_rating)                        AS avg_csat,
        AVG(CASE WHEN is_csat_positive THEN 1.0 ELSE 0.0 END) * 100 AS pct_csat_positive
    FROM marts.fct_conversations
    WHERE has_csat = TRUE
      AND csat_rated_teammate_id IS NOT NULL
    GROUP BY 1, 2
)

SELECT
    s.admin_id,
    s.first_name,
    s.date_day,
    s.week_start_date,
    s.day_of_week_iso,
    s.day_name,

    COALESCE(dm.nb_messages_sent,                0)      AS nb_messages_sent,
    COALESCE(dm.nb_conversations_touched,        0)      AS nb_conversations_touched,

    COALESCE(dfr.nb_conversations_first_replied, 0)      AS nb_conversations_first_replied,
    dfr.avg_frt_minutes,
    dfr.median_frt_minutes,
    dfr.pct_under_5min,

    COALESCE(dc.nb_csat_received,                0)      AS nb_csat_received,
    dc.avg_csat,
    dc.pct_csat_positive

FROM spine s
LEFT JOIN daily_messages       dm  ON dm.admin_id  = s.admin_id AND dm.sent_date      = s.date_day
LEFT JOIN daily_first_response dfr ON dfr.admin_id = s.admin_id AND dfr.response_date = s.date_day
LEFT JOIN daily_csat           dc  ON dc.admin_id  = s.admin_id AND dc.csat_date      = s.date_day;
