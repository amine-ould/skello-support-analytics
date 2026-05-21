-- =============================================================================
-- fct_conversations  (DuckDB)
-- Table de faits PRINCIPALE : 1 ligne = 1 conversation, enrichie de toutes
-- les métriques nécessaires au reporting. C'est la table que la BI requête
-- en priorité (80% des questions de Lorette s'écrivent en SELECT ... GROUP BY).
-- =============================================================================

CREATE OR REPLACE TABLE marts.fct_conversations AS

WITH message_counts AS (
    SELECT
        conversation_id,
        SUM(CASE WHEN is_admin    AND NOT is_bot THEN 1 ELSE 0 END)   AS nb_admin_messages,
        SUM(CASE WHEN is_customer                THEN 1 ELSE 0 END)   AS nb_customer_messages,
        COUNT(*)                                                       AS nb_messages_total
    FROM staging.stg_intercom__conversation_parts
    WHERE is_message = TRUE
    GROUP BY conversation_id
),

close_event AS (
    SELECT
        conversation_id,
        MAX(created_at)                                                AS closed_at,
        arg_max(author_id, created_at)                                 AS closed_by_admin_id
    FROM staging.stg_intercom__conversation_parts
    WHERE is_close = TRUE
    GROUP BY conversation_id
)

SELECT
    c.conversation_id,

    -- Dimensions temporelles
    c.created_at                                                       AS conversation_created_at,
    CAST(c.created_at AS DATE)                                         AS conversation_created_date,
    date_trunc('week', c.created_at)                                   AS conversation_created_week,
    close_event.closed_at,
    date_diff('minute', c.created_at, close_event.closed_at)           AS resolution_minutes,

    -- État
    c.state,
    c.is_open,
    c.is_priority,

    -- Assignations
    c.final_assignee_id,
    c.final_assignee_type,
    asg.first_support_assignee_id,
    asg.last_support_assignee_id,
    COALESCE(asg.is_handled_by_support, FALSE)                         AS is_handled_by_support,
    COALESCE(asg.nb_assignments, 0)                                    AS nb_assignments,

    -- First Response Time
    frt.first_admin_reply_at,
    frt.first_responder_admin_id,
    frt.frt_seconds,
    frt.frt_minutes,
    frt.frt_bucket,
    COALESCE(frt.is_replied_under_5min, FALSE)                         AS is_replied_under_5min,
    COALESCE(frt.is_outbound, FALSE)                                   AS is_outbound,

    -- Volume de messages
    COALESCE(mc.nb_admin_messages,    0)                               AS nb_admin_messages,
    COALESCE(mc.nb_customer_messages, 0)                               AS nb_customer_messages,
    COALESCE(mc.nb_messages_total,    0)                               AS nb_messages_total,
    (COALESCE(mc.nb_admin_messages, 0) = 1)                            AS is_one_touch,

    -- CSAT
    c.csat_rating,
    c.csat_remark,
    c.csat_created_at,
    c.csat_rated_teammate_id,
    (c.csat_rating IS NOT NULL)                                        AS has_csat,
    (c.csat_rating >= 4)                                               AS is_csat_positive,
    (c.csat_rating <= 2)                                               AS is_csat_negative,

    -- Tags
    c.tag_names

FROM staging.stg_intercom__conversations               c
LEFT JOIN intermediate.int_conversation_first_response  frt USING (conversation_id)
LEFT JOIN intermediate.int_conversation_assignments     asg USING (conversation_id)
LEFT JOIN message_counts                                 mc USING (conversation_id)
LEFT JOIN close_event                                       USING (conversation_id);
