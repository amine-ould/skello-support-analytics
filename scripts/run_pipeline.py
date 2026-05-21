"""
run_pipeline.py — Pipeline complet Skello / Intercom sur DuckDB.

Exécution :
    python scripts/run_pipeline.py
ou avec chemins explicites :
    python scripts/run_pipeline.py --conversations path/to/CONV.csv --parts path/to/PARTS.csv

Le pipeline :
  1. charge les 2 CSV dans le schéma `raw`
  2. exécute en ordre tous les .sql des couches staging → intermediate → marts
  3. lance les requêtes du dashboard et affiche les KPI
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
SQL_DIR = ROOT / "sql"
DEFAULT_DB = ROOT / "outputs" / "skello.duckdb"
LAYER_ORDER = ["01_staging", "02_intermediate", "03_marts"]


def banner(text: str) -> None:
    bar = "═" * 78
    print(f"\n{bar}\n  {text}\n{bar}")


def run_sql_file(con: duckdb.DuckDBPyConnection, path: Path) -> None:
    print(f"  ▸ {path.relative_to(ROOT)}")
    con.execute(path.read_text(encoding="utf-8"))


def show_query(con: duckdb.DuckDBPyConnection, title: str, sql: str) -> None:
    print(f"\n── {title}")
    df = con.execute(sql).fetchdf()
    print(df.to_string(index=False, na_rep="—", max_colwidth=24))


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--conversations", default=str(ROOT / "data" / "raw" / "CONVERSATIONS.csv"))
    p.add_argument("--parts",         default=str(ROOT / "data" / "raw" / "CONVERSATION_PARTS.csv"))
    p.add_argument("--db",            default=str(DEFAULT_DB))
    args = p.parse_args()

    conv_csv  = Path(args.conversations).resolve()
    parts_csv = Path(args.parts).resolve()
    for f in (conv_csv, parts_csv):
        if not f.exists():
            sys.exit(f"❌ Fichier introuvable : {f}\n"
                     f"   Placez les CSV dans data/raw/ ou utilisez --conversations / --parts.")

    db_path = Path(args.db).resolve()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()

    con = duckdb.connect(str(db_path))
    print(f"DuckDB {duckdb.__version__} — DB : {db_path}")

    # --- 1. RAW ---
    banner("1. Chargement RAW")
    con.execute("CREATE SCHEMA IF NOT EXISTS raw")
    con.execute(
        f"CREATE OR REPLACE TABLE raw.conversations AS "
        f"SELECT * FROM read_csv_auto('{conv_csv.as_posix()}', sample_size=50000)"
    )
    con.execute(
        f"CREATE OR REPLACE TABLE raw.conversation_parts AS "
        f"SELECT * FROM read_csv_auto('{parts_csv.as_posix()}', sample_size=50000)"
    )
    print(f"  raw.conversations         : {con.execute('SELECT COUNT(*) FROM raw.conversations').fetchone()[0]:>10,} lignes")
    print(f"  raw.conversation_parts    : {con.execute('SELECT COUNT(*) FROM raw.conversation_parts').fetchone()[0]:>10,} lignes")

    # --- 2. Modèles ---
    for s in ("staging", "intermediate", "marts"):
        con.execute(f"CREATE SCHEMA IF NOT EXISTS {s}")

    for layer in LAYER_ORDER:
        banner(f"2. Construction couche {layer.split('_', 1)[1].upper()}")
        for sql_path in sorted((SQL_DIR / layer).glob("*.sql")):
            run_sql_file(con, sql_path)

    # --- 3. Tests automatisés ---
    banner("3. Tests automatisés")
    tests_sql = (SQL_DIR / "05_tests" / "tests.sql").read_text(encoding="utf-8")
    df_tests = con.execute(tests_sql).fetchdf()
    print(df_tests.to_string(index=False))
    total_failures = int(df_tests["failures"].sum())
    if total_failures == 0:
        print(f"\n✅ Tous les tests passent ({len(df_tests)} tests, 0 failures)")
    else:
        print(f"\n❌ {total_failures} failures détectées sur {len(df_tests)} tests")
        sys.exit(1)

    # --- 4. KPI dashboard ---
    banner("4. KPI du dashboard")
    show_query(
        con, "Performance par agent",
        """
        SELECT
            a.first_name AS agent,
            COUNT(DISTINCT CASE WHEN f.first_responder_admin_id = a.admin_id THEN f.conversation_id END) AS nb_first_replied,
            ROUND(MEDIAN(CASE WHEN f.first_responder_admin_id = a.admin_id THEN f.frt_minutes END), 1)   AS median_frt_min,
            ROUND(AVG(CASE WHEN f.first_responder_admin_id = a.admin_id
                           THEN CASE WHEN f.is_replied_under_5min THEN 100.0 ELSE 0 END END), 1)         AS pct_under_5min,
            COUNT(DISTINCT CASE WHEN f.csat_rated_teammate_id = a.admin_id AND f.has_csat THEN f.conversation_id END) AS nb_csat,
            ROUND(AVG(CASE WHEN f.csat_rated_teammate_id = a.admin_id THEN f.csat_rating END), 2)        AS avg_csat,
            ROUND(AVG(CASE WHEN f.csat_rated_teammate_id = a.admin_id
                           THEN CASE WHEN f.is_csat_positive THEN 100.0 ELSE 0 END END), 1)              AS pct_csat_positive
        FROM marts.dim_support_agents a
        CROSS JOIN marts.fct_conversations f
        GROUP BY a.first_name
        ORDER BY pct_csat_positive DESC NULLS LAST
        """,
    )
    show_query(
        con, "Distribution du FRT (scope Support)",
        """
        SELECT frt_bucket,
               COUNT(*) AS nb_conversations,
               ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
        FROM marts.fct_conversations
        WHERE is_handled_by_support
        GROUP BY frt_bucket
        ORDER BY CASE frt_bucket
            WHEN 'under_1_min'    THEN 1 WHEN 'under_5_min'   THEN 2
            WHEN 'under_30_min'   THEN 3 WHEN 'under_2_hours' THEN 4
            WHEN 'under_1_day'    THEN 5 WHEN 'over_1_day'    THEN 6
            ELSE 7 END
        """,
    )
    show_query(
        con, "Top 10 tags",
        """
        SELECT tag_name, COUNT(*) AS n
        FROM (SELECT UNNEST(tag_names) AS tag_name
              FROM marts.fct_conversations
              WHERE is_handled_by_support AND tag_names IS NOT NULL) t
        GROUP BY tag_name ORDER BY n DESC LIMIT 10
        """,
    )

    banner(f"✅ Pipeline terminé — {db_path}")
    print("Pour explorer interactivement : duckdb", db_path)


if __name__ == "__main__":
    main()
