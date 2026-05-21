# Skello — Support Analytics

> **Case study Data Analyst Stagiaire**
> Modèle de données et reporting hebdomadaire pour l'équipe Support de Skello, à partir des données Intercom (`CONVERSATIONS`, `CONVERSATION_PARTS`).

---

## TL;DR

| | |
|---|---|
| **Objectif business** | Donner à Lorette (Lead Support) la visibilité dont elle a besoin pour son rituel hebdomadaire du lundi : CSAT, FRT, charge horaire, performance par agent. |
| **Approche** | Modèle en couches (`raw` → `staging` → `intermediate` → `marts`), inspiré dbt, exécuté sur DuckDB en local pour reproductibilité totale. |
| **Livrable principal** | 9 modèles SQL + 1 table de faits pivot (`fct_conversations`) + un notebook Jupyter qui rejoue toute la chaîne et génère le dashboard. |
| **Reproductibilité** | `python scripts/run_pipeline.py` ou ouvrir `notebooks/skello_pipeline.ipynb`. ~3 secondes de bout en bout. |

---

## Démarche

### 1. Exploration des données (pas que la doc)

Avant de modéliser, j'ai chargé les CSV pour confronter la documentation à la réalité. **3 anomalies majeures découvertes** qui ont changé l'approche :

| Constat | Conséquence |
|---|---|
| `CONVERSATIONS.ASSIGNEE` ne contient que l'assignee **final** | Pour avoir le détail "par personne" demandé par Lorette, il faut reconstruire l'historique via `CONVERSATION_PARTS.PART_GROUP = 'Assignment'`. |
| `ASSIGNED_TO` est sérialisé en **Python-dict** (apostrophes simples, `None` au lieu de `null`), pas en JSON | `json_extract` plante dessus → extraction par regex. |
| **Justine** (ID 5391224) n'apparaît **jamais** dans les données (ni assignation, ni message), **Patrick** une fois | À remonter à Lorette en priorité — sans clarification, 2/4 de l'équipe sont invisibles dans le dashboard. |

### 2. Architecture en couches (medallion / dbt-style)

```
                  CONVERSATIONS.csv    CONVERSATION_PARTS.csv
                          │                     │
                          ▼                     ▼
              ┌──────────────────────────────────────────┐
              │  raw            (chargement brut CSV)     │
              ├──────────────────────────────────────────┤
              │  staging        (parsing JSON, typage,    │
              │                  dédoublonnage)           │
              ├──────────────────────────────────────────┤
              │  intermediate   (logique métier :         │
              │                  FRT, assignations,       │
              │                  messages admin)          │
              ├──────────────────────────────────────────┤
              │  marts          (consommé par la BI :     │
              │                  dim_*, fct_*)            │
              └──────────────────────────────────────────┘
```

**Pourquoi ce découpage ?**
- **Staging** isole le nettoyage : si demain l'ETL change le format JSON, on ne corrige qu'à un seul endroit.
- **Intermediate** porte la logique métier **réutilisable** (1 définition du FRT, 1 définition d'une conv "Support"). Pas de divergence possible entre dashboards.
- **Marts** aplatis et dénormalisés : les outils de viz requêtent en `SELECT ... GROUP BY` sans jointure.

### 3. Choix techniques

| Choix | Pourquoi |
|---|---|
| **DuckDB** plutôt que SQLite ou Postgres local | Mêmes patterns SQL que Snowflake (CTE, fonctions JSON, `MEDIAN`, `arg_min`, `bool_or`, intervalles ISO), zéro install serveur, lit nativement les CSV, vectorisé. Le portage en Snowflake (`json_extract` → `PARSE_JSON`, `arg_min` → `MIN_BY`, etc.) est mécanique. |
| **SQL en fichiers** plutôt qu'inline en Python | Audit / relecture / versioning évident, chaque fichier exécutable seul. |
| **Préfixe numérique** sur les fichiers marts | L'ordre d'exécution est déterministe (`fct_conversations` avant `fct_agent_daily_activity` qui en dépend). |
| **Notebook Jupyter** comme livrable de présentation | Permet à Lorette / une équipe data de rejouer la démo et de voir les graphiques inline. |

---

## Installation

### Pré-requis

- Python 3.9+
- 2 CSV fournis (à placer dans `data/raw/`)

### Mise en route

```bash
# 1. Se placer dans le dossier
cd skello-support-analytics

# 2. Installer les dépendances
pip install -r requirements.txt

# 3. Placer les CSV
#    data/raw/CONVERSATIONS.csv
#    data/raw/CONVERSATION_PARTS.csv

# 4a. Lancer le pipeline en ligne de commande
python scripts/run_pipeline.py

# 4b. OU ouvrir le notebook (graphiques pré-rendus, exécution optionnelle)
jupyter lab notebooks/skello_pipeline.ipynb

# 4c. OU lancer le dashboard interactif (filtres semaine/agent)
streamlit run dashboard.py
```

Le pipeline complet tourne en **~3 secondes** sur les 252 k lignes du dataset.

---

## Structure du repo

```
skello-support-analytics/
│
├── README.md                                ← vous êtes ici
├── requirements.txt
├── dashboard.py                             ← dashboard Streamlit interactif
│
├── data/
│   ├── raw/                                 ← CSV à placer ici
│   └── README.md
│
├── notebooks/
│   └── skello_pipeline.ipynb                ← démo complète + dashboard + insights
│
├── sql/
│   ├── 01_staging/
│   │   ├── stg_intercom__conversations.sql
│   │   └── stg_intercom__conversation_parts.sql
│   ├── 02_intermediate/
│   │   ├── int_conversation_first_response.sql
│   │   ├── int_conversation_assignments.sql
│   │   └── int_admin_messages.sql
│   ├── 03_marts/
│   │   ├── 01_dim_date.sql
│   │   ├── 02_dim_support_agents.sql
│   │   ├── 03_fct_conversations.sql          ← table de faits pivot
│   │   └── 04_fct_agent_daily_activity.sql
│   ├── 04_dashboard/
│   │   └── dashboard_queries.sql             ← 6 requêtes du dashboard
│   └── 05_tests/
│       └── tests.sql                         ← 11 tests automatisés (style dbt)
│
├── scripts/
│   └── run_pipeline.py                       ← orchestrateur CLI (avec tests intégrés)
│
└── docs/
    ├── data_model.md                         ← schéma + diagramme du modèle
    ├── dashboard_template.md                 ← template du reporting hebdo
    └── questions_lorette.md                  ← questions ouvertes au métier
```

---

## Résultats principaux

Après exécution du pipeline sur le dataset (Oct 2021 → Jan 2022) :

| KPI | Valeur | Commentaire |
|---|---|---|
| Conversations | **11 786** | dont 3 358 (28 %) avec CSAT renseignée |
| FRT médian | **7,9 min** | scope Support |
| **% conv. répondues en <5 min** | **31,3 %** | KPI prioritaire — loin de la cible standard (70 %+) |
| Tag #1 | **Badgeuse** (470 conv) | suivi de Équipes, Permissions, Contrats |
| Pic de charge | **lundi matin** | 323 conv ouvertes entre 6h-12h |
| Justine / Patrick | **0 trace** dans les données | ⚠️ Anomalie à clarifier avec Lorette |

Voir `notebooks/skello_pipeline.ipynb` pour les graphiques détaillés (heatmap, distribution FRT, évolution hebdo, top tags).

---

## Plan d'action 30 / 60 / 90 jours

Si j'étais stagiaire chez Skello, voici la roadmap que je proposerais à Lorette dès la 1ʳᵉ semaine :

### 🗓 Mois 1 — Industrialiser & fiabiliser

- Migrer le pipeline DuckDB local vers **dbt + Snowflake** : `models/` au lieu de `sql/`, `ref()` pour les dépendances, `schema.yml` avec les tests (`unique`, `not_null`, `relationships`, `accepted_values`).
- Brancher le dashboard sur l'outil de BI maison (Metabase / Tableau / Looker) pour que Lorette puisse y accéder sans relancer le pipeline.
- Résoudre les questions ouvertes en `docs/questions_lorette.md` (notamment Justine/Patrick et l'assignee 663326).
- Mettre en place une **CI** : `dbt build` à chaque PR sur le repo data, échec si les tests ne passent pas.

### 🗓 Mois 2 — Enrichir la valeur

- Croiser les conv Intercom avec d'autres sources :
  - **Salesforce / HubSpot** : segment client (SMB / mid-market / enterprise), MRR, ancienneté → la CSAT varie-t-elle selon le segment ?
  - **Mixpanel / Amplitude** : la conv arrive-t-elle après un parcours produit cassé ? Le client utilisait quelle fonctionnalité avant ?
- Ajouter un **dashboard "Voice of Customer"** : extraction des verbatims `csat_remark`, classification automatique des thèmes (Bug / Question UX / Demande feature) via OpenAI / Mistral.
- **Alerting Slack** : webhook qui notifie Lorette en cours de semaine si % FRT <5min descend sous le seuil.

### 🗓 Mois 3 — Anticiper plutôt que constater

- **Modèle prédictif** : *probabilité qu'une conversation reçoive une CSAT négative*, calculé en temps réel pendant la conv en fonction du FRT, du tag, du segment client. Alerte l'agent senior pour qu'il intervienne avant la fin.
- **Forecasting du volume Support** : modèle ARIMA ou Prophet sur le volume hebdomadaire → utile pour dimensionner les recrutements à 3 mois.
- Pousser le **scope dbt sémantique** : exposer les KPI Support comme métriques officielles consommables par d'autres équipes (Sales, Customer Success) via dbt Semantic Layer ou Cube.dev.

---

## Ce qui est validé techniquement

| Test | Statut |
|---|---|
| `python scripts/run_pipeline.py` | ✅ Pipeline complet ~3 sec, 11 tests SQL à 0 failure, KPI imprimés |
| Notebook exécuté end-to-end | ✅ 19/19 cellules code, graphiques pré-rendus |
| `streamlit run dashboard.py` | ✅ Dashboard interactif (filtres semaine/agent) |
| 9 modèles SQL construits | ✅ staging (2), intermediate (3), marts (4) |
| Tests SQL automatisés | ✅ 11 tests intégrés au pipeline (`sql/05_tests/tests.sql`) |
| Anomalies détectées & corrigées | ✅ 1 NULL ID dans la source, 229 conv outbound (flag `is_outbound`) |

---

## Annexes

- 📄 [`docs/data_model.md`](docs/data_model.md) — modèle détaillé table par table
- 📊 [`docs/dashboard_template.md`](docs/dashboard_template.md) — template du dashboard hebdomadaire, section par section avec justifications
- ❓ [`docs/questions_lorette.md`](docs/questions_lorette.md) — questions ouvertes au métier
