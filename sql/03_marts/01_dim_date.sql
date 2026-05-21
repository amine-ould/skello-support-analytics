-- =============================================================================
-- dim_date  (DuckDB)
-- Table calendrier sur 2021-2027.
-- =============================================================================

CREATE OR REPLACE TABLE marts.dim_date AS

WITH date_spine AS (
    SELECT DATE '2021-01-01' + INTERVAL (i) DAY AS date_day
    FROM range(0, 2557) t(i)             -- ~7 ans
)

SELECT
    date_day,
    EXTRACT(year   FROM date_day)                           AS year_num,
    EXTRACT(month  FROM date_day)                           AS month_num,
    EXTRACT(day    FROM date_day)                           AS day_of_month,
    EXTRACT(isodow FROM date_day)                           AS day_of_week_iso,    -- 1=lundi
    dayname(date_day)                                       AS day_name,
    EXTRACT(isoyear FROM date_day)                          AS year_iso,
    EXTRACT(week    FROM date_day)                          AS week_iso,
    date_trunc('week',  date_day)                           AS week_start_date,    -- lundi de la semaine
    date_trunc('month', date_day)                           AS month_start_date,
    (EXTRACT(isodow FROM date_day) IN (6, 7))               AS is_weekend
FROM date_spine
WHERE date_day <= DATE '2027-12-31';
