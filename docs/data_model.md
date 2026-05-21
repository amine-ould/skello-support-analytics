# Modèle de données

## Vue d'ensemble

```
                      ┌─────────────────────────────────┐
                      │ RAW (source ETL → DWH)          │
                      │                                  │
                      │  raw.conversations               │
                      │  raw.conversation_parts          │
                      └────────────────┬─────────────────┘
                                       │
                                       ▼
                      ┌─────────────────────────────────┐
                      │ STAGING (nettoyage)              │
                      │                                  │
                      │  stg_intercom__conversations     │ 1 conv = 1 ligne, JSON parsé
                      │  stg_intercom__conversation_parts│ 1 event = 1 ligne, JSON parsé
                      └────────────────┬─────────────────┘
                                       │
                                       ▼
                      ┌─────────────────────────────────┐
                      │ INTERMEDIATE (logique métier)    │
                      │                                  │
                      │  int_conversation_first_response │ 1 conv = 1 ligne, FRT calculé
                      │  int_conversation_assignments    │ 1 conv = 1 ligne, hist. d'assignation
                      │  int_admin_messages              │ 1 msg admin = 1 ligne
                      └────────────────┬─────────────────┘
                                       │
                                       ▼
                      ┌─────────────────────────────────┐
                      │ MARTS (BI / dashboards)          │
                      │                                  │
                      │  dim_support_agents     ─┐       │
                      │  dim_date               ─┤       │
                      │                          ├─ joins par les outils de viz
                      │  fct_conversations      ─┤       │  (table pivot, 80% des KPI)
                      │  fct_agent_daily_activity─┘       │
                      └─────────────────────────────────┘
```

---

## Détail des tables

### `staging.stg_intercom__conversations`
Granularité : **1 ligne = 1 conversation** (PK : `conversation_id`).

| Colonne | Type | Source / logique |
|---|---|---|
| `conversation_id` | VARCHAR | `raw.conversations.ID`, dédupliqué |
| `created_at`, `updated_at` | TIMESTAMP | `strptime(REPLACE(..., ' Z', ''), '%Y-%m-%d %H:%M:%S.%g')` |
| `waiting_since`, `snoozed_until` | TIMESTAMP | idem (try_strptime car nullable) |
| `state`, `is_open`, `is_read`, `is_priority` | VARCHAR/BOOL | colonnes directes |
| `final_assignee_id`, `final_assignee_type` | VARCHAR | `json_extract_string(ASSIGNEE, '$.id')` |
| `csat_rating` | INTEGER | `json_extract_string(CONVERSATION_RATING, '$.rating')` |
| `csat_remark`, `csat_created_at`, `csat_rated_teammate_id` | divers | sous-champs de `CONVERSATION_RATING` |
| `tag_names` | LIST(VARCHAR) | `list_transform(CAST(TAGS AS JSON)::JSON[], x -> json_extract_string(x, '$.name'))` |

**Dédoublonnage** : `ROW_NUMBER() OVER (PARTITION BY ID ORDER BY UPDATED_AT DESC)` — Stitch peut envoyer plusieurs versions d'une même conv.

---

### `staging.stg_intercom__conversation_parts`
Granularité : **1 ligne = 1 event** (PK : `part_id`).

| Colonne | Type | Source / logique |
|---|---|---|
| `part_id`, `conversation_id` | VARCHAR | direct |
| `created_at`, `updated_at`, `conversation_created_at` | TIMESTAMP | parsing identique au staging conv |
| `part_group` | VARCHAR | `Message` / `Assignment` / `Close` / `Snooze` / `Quick Reply` |
| `author_id`, `author_type` | VARCHAR | `json_extract_string(AUTHOR, '$.id')` |
| `is_bot`, `is_admin`, `is_customer` | BOOL | sur `author_type` |
| `assigned_to_id`, `assigned_to_type` | VARCHAR | **regex** (pas JSON, voir note ↓) |
| `is_message`, `is_assignment`, `is_close`, `is_snooze` | BOOL | flags sur `part_group` |

> ⚠️ **Note importante** : `ASSIGNED_TO` est sérialisé au format **Python dict** (apostrophes simples, `None` au lieu de `null`), pas en JSON valide. `json_extract_string` plante dessus. On utilise `regexp_extract(ASSIGNED_TO, '''id'':\s*''([^'']+)''', 1)`.

---

### `intermediate.int_conversation_first_response`
Granularité : **1 ligne = 1 conversation**.
Calcule le **First Response Time (FRT)** : délai entre `conversation.created_at` et le 1ᵉʳ message d'un admin **humain** (bots exclus).

| Colonne | Logique |
|---|---|
| `first_admin_reply_at` | `MIN(created_at)` sur les messages `is_admin AND NOT is_bot` |
| `first_responder_admin_id` | `arg_min(author_id, created_at)` |
| `frt_seconds`, `frt_minutes` | `date_diff('second', ...)` |
| `frt_bucket` | catégorisation : `<1min` / `<5min` / `<30min` / `<2h` / `<24h` / `>24h` / `no_admin_reply` |
| `is_replied_under_5min` | flag direct pour le KPI métier |

---

### `intermediate.int_conversation_assignments`
Granularité : **1 ligne = 1 conversation**.
Reconstitue l'historique des (ré)assignations.

| Colonne | Logique |
|---|---|
| `is_handled_by_support` | `TRUE` si la conv a été assignée à un des 4 IDs Support à un moment |
| `first_support_assignee_id`, `last_support_assignee_id` | `arg_min` / `arg_max` parmi les assignations Support |
| `nb_assignments`, `nb_support_assignments` | compteurs |

> Pourquoi cette table ? Le champ `ASSIGNEE` de `CONVERSATIONS` ne contient que l'assignation **finale** — sans cette intermédiaire, on raterait toutes les conv Support ré-orientées en fin de parcours.

---

### `intermediate.int_admin_messages`
Granularité : **1 ligne = 1 message admin humain** (bots exclus).
Sert aux analyses fines : heatmap volume×heure×jour, charge de travail individuelle.

---

### `marts.dim_support_agents`
Référentiel statique des 4 membres Support. En prod réel, à alimenter depuis l'outil RH (BambooHR, Personio…).

| admin_id | first_name | team |
|---|---|---|
| 5217337 | Héloïse | Support |
| 5391224 | Justine | Support |
| 5440474 | Patrick | Support |
| 5300290 | Raphaël | Support |

---

### `marts.dim_date`
Table calendrier (`2021-01-01` → `2027-12-31`). Permet de joindre sur toutes les dates, **y compris celles à 0 conversation** (qui disparaîtraient sinon en `GROUP BY`).

---

### `marts.fct_conversations` (TABLE PIVOT)
Granularité : **1 ligne = 1 conversation, enrichie de tous les KPI**.
C'est la table que les outils de viz requêtent en priorité : **80 % des questions de Lorette s'y résolvent en un `SELECT ... GROUP BY` sans jointure**.

Colonnes notables : `conversation_id`, `conversation_created_at`, `conversation_created_week`, `closed_at`, `resolution_minutes`, `first_responder_admin_id`, `frt_minutes`, `is_replied_under_5min`, `nb_admin_messages`, `is_one_touch`, `csat_rating`, `is_csat_positive`, `is_handled_by_support`, `tag_names`.

---

### `marts.fct_agent_daily_activity`
Granularité : **1 ligne = 1 agent × 1 jour**. Sert au tableau hebdomadaire de performance par agent et à la heatmap d'activité.

Inclut une `spine` (CROSS JOIN agents × dates) pour garantir qu'un jour à 0 activité d'un agent apparaisse quand même (pas de trou dans le dashboard).

---

## Hypothèses & arbitrages (à valider avec Lorette)

| # | Hypothèse | Détail |
|---|---|---|
| 1 | Conversation "Support" = passée par Support à au moins un moment | Via l'historique d'assignation, pas l'assignee final |
| 2 | FRT = délai jusqu'au 1ᵉʳ admin **humain** (bots exclus) | Cohérent avec consigne |
| 3 | Performance par agent = mesurée sur `first_responder_admin_id` (pas `assignee`) | Reflète qui a *vraiment* travaillé |
| 4 | CSAT positive = note ≥ 4 / 5 | Convention standard support |
| 5 | Conv "résolue" = passage en `STATE='closed'` (dernier `Close`) | 100 % du dataset est `closed` |
| 6 | Semaine ISO lundi → dimanche | Cohérent avec rituel lundi |
| 7 | `Quick Reply` = exclu de l'analyse | 100 % émis par bots |

---

## Migration Snowflake (production)

Mapping mécanique des fonctions :

| DuckDB (local) | Snowflake (prod) |
|---|---|
| `json_extract_string(x, '$.id')` | `PARSE_JSON(x):"id"::STRING` |
| `strptime(REPLACE(..., ' Z', ''), '%Y-%m-%d %H:%M:%S.%g')` | `TO_TIMESTAMP_NTZ(...)` |
| `arg_min`, `arg_max` | `MIN_BY`, `MAX_BY` |
| `bool_or` | `BOOLOR_AGG` |
| `EXTRACT(isodow FROM x)` | `DAYOFWEEKISO(x)` |
| `range(N) t(i)` | `TABLE(GENERATOR(ROWCOUNT => N))` + `SEQ4()` |
| `UNNEST(list_col)` | `LATERAL FLATTEN(input => array_col)` |

Le reste (CTE, jointures, `MEDIAN`, fenêtres, `ORDER BY`) est identique.
