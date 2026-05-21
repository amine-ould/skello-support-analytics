-- =============================================================================
-- int_conversation_assignments  (DuckDB)
-- Historique des (ré)assignations d'une conv. Permet d'identifier les conv
-- ayant été traitées par la team Support, même si l'assignee final est ailleurs.
-- =============================================================================

CREATE OR REPLACE TABLE intermediate.int_conversation_assignments AS

WITH assignment_events AS (
    SELECT
        conversation_id,
        part_id,
        created_at                                AS assigned_at,
        assigned_to_id,
        assigned_to_type,
        -- Les 4 IDs de la team Support (hard-codés ici par souci de lisibilité.
        -- En prod : JOIN dim_support_agents.)
        (assigned_to_id IN ('5217337', '5391224', '5440474', '5300290')) AS is_support_assignment
    FROM staging.stg_intercom__conversation_parts
    WHERE is_assignment = TRUE
      AND assigned_to_id IS NOT NULL
),

support_assignments AS (
    SELECT * FROM assignment_events WHERE is_support_assignment
),

aggregated AS (
    SELECT
        conversation_id,
        COUNT(DISTINCT part_id)                                       AS nb_assignments,
        COUNT(DISTINCT assigned_to_id)                                AS nb_distinct_assignees,
        SUM(CASE WHEN is_support_assignment THEN 1 ELSE 0 END)        AS nb_support_assignments,
        bool_or(is_support_assignment)                                AS is_handled_by_support
    FROM assignment_events
    GROUP BY conversation_id
),

first_last_support AS (
    SELECT
        conversation_id,
        arg_min(assigned_to_id, assigned_at)                          AS first_support_assignee_id,
        MIN(assigned_at)                                              AS first_support_assigned_at,
        arg_max(assigned_to_id, assigned_at)                          AS last_support_assignee_id,
        MAX(assigned_at)                                              AS last_support_assigned_at
    FROM support_assignments
    GROUP BY conversation_id
)

SELECT
    a.conversation_id,
    a.nb_assignments,
    a.nb_distinct_assignees,
    a.nb_support_assignments,
    a.is_handled_by_support,
    f.first_support_assignee_id,
    f.first_support_assigned_at,
    f.last_support_assignee_id,
    f.last_support_assigned_at
FROM aggregated a
LEFT JOIN first_last_support f USING (conversation_id);
