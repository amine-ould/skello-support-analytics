-- =============================================================================
-- stg_intercom__conversation_parts  (DuckDB)
-- 1 ligne = 1 event sur une conversation.
-- Important : ASSIGNED_TO est en réalité un objet JSON {id, type}, pas un id brut.
-- =============================================================================

CREATE OR REPLACE TABLE staging.stg_intercom__conversation_parts AS

WITH deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY ID
            ORDER BY UPDATED_AT DESC, _SDC_SEQUENCE DESC
        ) AS rn
    FROM raw.conversation_parts
)

SELECT
    ID                                                                AS part_id,
    CONVERSATION_ID                                                   AS conversation_id,

    strptime(REPLACE(CREATED_AT,                 ' Z', ''), '%Y-%m-%d %H:%M:%S.%g') AS created_at,
    strptime(REPLACE(UPDATED_AT,                 ' Z', ''), '%Y-%m-%d %H:%M:%S.%g') AS updated_at,
    try_strptime(REPLACE(NOTIFIED_AT,            ' Z', ''), '%Y-%m-%d %H:%M:%S.%g') AS notified_at,
    strptime(REPLACE(CONVERSATION_CREATED_AT,    ' Z', ''), '%Y-%m-%d %H:%M:%S.%g') AS conversation_created_at,

    PART_GROUP                                                        AS part_group,

    -- Auteur : id + type
    json_extract_string(AUTHOR, '$.id')                               AS author_id,
    json_extract_string(AUTHOR, '$.type')                             AS author_type,
    (json_extract_string(AUTHOR, '$.type') = 'bot')                   AS is_bot,
    (json_extract_string(AUTHOR, '$.type') = 'admin')                 AS is_admin,
    (json_extract_string(AUTHOR, '$.type') = 'user')                  AS is_customer,

    -- Cible d'assignation : attention, ce champ est sérialisé au format
    -- Python dict (apostrophes simples, None au lieu de null), pas en JSON.
    -- On extrait par regex. Ex : "{'type': 'admin', 'id': '5217337'}"
    NULLIF(regexp_extract(ASSIGNED_TO, '''id'':\s*''([^'']+)''',   1), '') AS assigned_to_id,
    NULLIF(regexp_extract(ASSIGNED_TO, '''type'':\s*''([^'']+)''', 1), '') AS assigned_to_type,

    (PART_GROUP = 'Message')                                          AS is_message,
    (PART_GROUP = 'Assignment')                                       AS is_assignment,
    (PART_GROUP = 'Close')                                            AS is_close,
    (PART_GROUP = 'Snooze')                                           AS is_snooze

FROM deduplicated
WHERE rn = 1;
