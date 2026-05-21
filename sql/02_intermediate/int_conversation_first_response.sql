/* =============================================================================
   int_conversation_first_response  (DuckDB)
   -----------------------------------------------------------------------------
   Objet : calcule le First Response Time (FRT) — délai entre la création
           de la conversation et le premier message d'un admin HUMAIN
           (bots exclus).
   Granularité : 1 ligne = 1 conversation

   Cas particulier des conversations OUTBOUND :
     ~2% des conversations ont un premier message admin antérieur à la
     création de la conversation (FRT négatif). Il s'agit de conversations
     initiées par Skello (onboarding, relance, notification…), pas par le
     client. Pour ces conv, le KPI "1ʳᵉ réponse < 5 min" n'a pas de sens
     car le client n'a pas encore écrit. On les flag `is_outbound = TRUE`
     et on les exclut des KPI de FRT dans les marts.
   ============================================================================= */

CREATE OR REPLACE TABLE intermediate.int_conversation_first_response AS

WITH admin_messages AS (
    SELECT
        conversation_id,
        author_id,
        created_at
    FROM staging.stg_intercom__conversation_parts
    WHERE is_message = TRUE
      AND is_admin   = TRUE
      AND is_bot     = FALSE
),

first_admin_reply AS (
    SELECT
        conversation_id,
        MIN(created_at)                                   AS first_admin_reply_at,
        arg_min(author_id, created_at)                    AS first_responder_admin_id
    FROM admin_messages
    GROUP BY conversation_id
),

joined AS (
    SELECT
        c.conversation_id,
        c.created_at                                                              AS conversation_created_at,
        fr.first_admin_reply_at,
        fr.first_responder_admin_id,
        CAST(date_diff('second', c.created_at, fr.first_admin_reply_at) AS BIGINT) AS frt_seconds_raw,
        -- Conv où admin a parlé en premier (outbound) : FRT négatif
        COALESCE(fr.first_admin_reply_at < c.created_at, FALSE)                   AS is_outbound
    FROM staging.stg_intercom__conversations c
    LEFT JOIN first_admin_reply fr USING (conversation_id)
)

SELECT
    conversation_id,
    conversation_created_at,
    first_admin_reply_at,
    first_responder_admin_id,
    is_outbound,
    -- frt_seconds nullifié pour les outbound (KPI non pertinent)
    CASE WHEN is_outbound THEN NULL ELSE frt_seconds_raw END        AS frt_seconds,
    CASE WHEN is_outbound THEN NULL ELSE frt_seconds_raw / 60.0 END AS frt_minutes,
    CASE
        WHEN is_outbound                          THEN 'outbound'
        WHEN frt_seconds_raw IS NULL              THEN 'no_admin_reply'
        WHEN frt_seconds_raw <  60                THEN 'under_1_min'
        WHEN frt_seconds_raw <  5 * 60            THEN 'under_5_min'
        WHEN frt_seconds_raw < 30 * 60            THEN 'under_30_min'
        WHEN frt_seconds_raw <  2 * 60 * 60       THEN 'under_2_hours'
        WHEN frt_seconds_raw < 24 * 60 * 60       THEN 'under_1_day'
        ELSE 'over_1_day'
    END                                                             AS frt_bucket,
    -- Flag direct pour le KPI métier (les outbound sont exclus)
    CASE
        WHEN is_outbound             THEN FALSE
        WHEN frt_seconds_raw IS NULL THEN FALSE
        ELSE (frt_seconds_raw < 5 * 60)
    END                                                             AS is_replied_under_5min
FROM joined;
