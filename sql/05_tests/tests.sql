-- =============================================================================
-- tests.sql  (DuckDB)
-- Suite de tests sur le modèle. Chaque test renvoie le nombre de lignes en
-- défaut : doit être 0 pour passer. Pattern inspiré de dbt.
--
-- Exécution :
--   - Soit chaque CTE séparément en interactif
--   - Soit via scripts/run_pipeline.py qui exécute l'agrégat final
-- =============================================================================

WITH
-- ─── Tests d'intégrité (PK, FK) ───────────────────────────────────────────
t_conv_pk_unique AS (
    SELECT 'fct_conversations.conversation_id is unique' AS test_name,
           COUNT(*) - COUNT(DISTINCT conversation_id)    AS failures
    FROM marts.fct_conversations
),
t_stg_conv_pk_unique AS (
    SELECT 'stg_intercom__conversations.conversation_id is unique' AS test_name,
           COUNT(*) - COUNT(DISTINCT conversation_id)              AS failures
    FROM staging.stg_intercom__conversations
),
t_stg_parts_pk_unique AS (
    SELECT 'stg_intercom__conversation_parts.part_id is unique' AS test_name,
           COUNT(*) - COUNT(DISTINCT part_id)                    AS failures
    FROM staging.stg_intercom__conversation_parts
),

-- ─── Tests métier ─────────────────────────────────────────────────────────
t_csat_in_range AS (
    SELECT 'csat_rating in [1, 5]'                                              AS test_name,
           COUNT(*) FILTER (WHERE csat_rating IS NOT NULL
                                 AND csat_rating NOT BETWEEN 1 AND 5)           AS failures
    FROM marts.fct_conversations
),
t_frt_non_negatif AS (
    SELECT 'frt_seconds >= 0 (admin ne répond pas avant création conv)'         AS test_name,
           COUNT(*) FILTER (WHERE frt_seconds < 0)                              AS failures
    FROM marts.fct_conversations
),
t_resolution_non_negative AS (
    SELECT 'resolution_minutes >= 0'                                            AS test_name,
           COUNT(*) FILTER (WHERE resolution_minutes < 0)                       AS failures
    FROM marts.fct_conversations
),
t_close_apres_creation AS (
    SELECT 'closed_at >= conversation_created_at quand renseigné'               AS test_name,
           COUNT(*) FILTER (WHERE closed_at IS NOT NULL
                                 AND closed_at < conversation_created_at)       AS failures
    FROM marts.fct_conversations
),

-- ─── Tests de cohérence des jointures ─────────────────────────────────────
t_pas_de_doublons_frt AS (
    SELECT 'int_conversation_first_response.conversation_id is unique'          AS test_name,
           COUNT(*) - COUNT(DISTINCT conversation_id)                           AS failures
    FROM intermediate.int_conversation_first_response
),
t_handled_support_a_un_assignee AS (
    SELECT 'is_handled_by_support => first_support_assignee_id renseigné'      AS test_name,
           COUNT(*) FILTER (WHERE is_handled_by_support
                                 AND first_support_assignee_id IS NULL)         AS failures
    FROM marts.fct_conversations
),

-- ─── Tests de complétude ──────────────────────────────────────────────────
t_volume_minimum AS (
    SELECT 'fct_conversations contient au moins 1 000 lignes'                   AS test_name,
           CASE WHEN COUNT(*) < 1000 THEN 1 ELSE 0 END                          AS failures
    FROM marts.fct_conversations
),
t_dim_agents_complete AS (
    SELECT 'dim_support_agents contient les 4 membres attendus'                 AS test_name,
           4 - COUNT(*)                                                          AS failures
    FROM marts.dim_support_agents
    WHERE admin_id IN ('5217337', '5391224', '5440474', '5300290')
)

-- ─── Agrégation finale ────────────────────────────────────────────────────
SELECT * FROM t_conv_pk_unique             UNION ALL
SELECT * FROM t_stg_conv_pk_unique         UNION ALL
SELECT * FROM t_stg_parts_pk_unique        UNION ALL
SELECT * FROM t_csat_in_range              UNION ALL
SELECT * FROM t_frt_non_negatif            UNION ALL
SELECT * FROM t_resolution_non_negative    UNION ALL
SELECT * FROM t_close_apres_creation       UNION ALL
SELECT * FROM t_pas_de_doublons_frt        UNION ALL
SELECT * FROM t_handled_support_a_un_assignee UNION ALL
SELECT * FROM t_volume_minimum             UNION ALL
SELECT * FROM t_dim_agents_complete
ORDER BY failures DESC, test_name;
