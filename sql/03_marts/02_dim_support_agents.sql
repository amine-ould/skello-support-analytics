-- =============================================================================
-- dim_support_agents  (DuckDB)
-- Référentiel statique des 4 membres de la team Support.
-- =============================================================================

CREATE OR REPLACE TABLE marts.dim_support_agents AS
SELECT * FROM (
    VALUES
        ('5217337', 'Héloïse', 'Support', TRUE),
        ('5391224', 'Justine', 'Support', TRUE),
        ('5440474', 'Patrick', 'Support', TRUE),
        ('5300290', 'Raphaël', 'Support', TRUE)
) AS t(admin_id, first_name, team, is_active);
