-- =============================================================================
-- stg_intercom__conversations  (DuckDB)
-- 1 ligne = 1 conversation, JSON parsé, timestamps typés, dédoublonné.
-- =============================================================================

CREATE OR REPLACE TABLE staging.stg_intercom__conversations AS

WITH deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY ID
            ORDER BY UPDATED_AT DESC, _SDC_SEQUENCE DESC
        ) AS rn
    FROM raw.conversations
)

SELECT
    ID                                                              AS conversation_id,

    -- Timestamps : on enlève le " Z" final puis on parse avec millisecondes
    strptime(REPLACE(CREATED_AT,    ' Z', ''), '%Y-%m-%d %H:%M:%S.%g')   AS created_at,
    strptime(REPLACE(UPDATED_AT,    ' Z', ''), '%Y-%m-%d %H:%M:%S.%g')   AS updated_at,
    try_strptime(REPLACE(CAST(WAITING_SINCE AS VARCHAR),  ' Z', ''), '%Y-%m-%d %H:%M:%S.%g') AS waiting_since,
    try_strptime(REPLACE(CAST(SNOOZED_UNTIL AS VARCHAR),  ' Z', ''), '%Y-%m-%d %H:%M:%S.%g') AS snoozed_until,

    STATE                                                           AS state,
    OPEN                                                            AS is_open,
    READ                                                            AS is_read,
    (PRIORITY = 'priority')                                         AS is_priority,

    -- Assignee final (peut différer des assignations intermédiaires, cf. int_conversation_assignments)
    json_extract_string(ASSIGNEE, '$.id')                           AS final_assignee_id,
    json_extract_string(ASSIGNEE, '$.type')                         AS final_assignee_type,

    -- CSAT rating
    TRY_CAST(json_extract_string(CONVERSATION_RATING, '$.rating') AS INTEGER) AS csat_rating,
    json_extract_string(CONVERSATION_RATING, '$.remark')            AS csat_remark,
    try_strptime(
        json_extract_string(CONVERSATION_RATING, '$.created_at'),
        '%Y-%m-%dT%H:%M:%S%z'
    )                                                               AS csat_created_at,
    json_extract_string(CONVERSATION_RATING, '$.teammate.id')       AS csat_rated_teammate_id,

    -- Tags : liste de noms (LIST<VARCHAR>) prête à UNNEST
    CASE
        WHEN TAGS IS NULL THEN NULL
        ELSE list_transform(
                CAST(TAGS AS JSON)::JSON[],
                x -> json_extract_string(x, '$.name')
             )
    END                                                             AS tag_names

FROM deduplicated
WHERE rn = 1
  AND ID IS NOT NULL;  -- 1 ligne avec ID NULL dans la source, exclue
