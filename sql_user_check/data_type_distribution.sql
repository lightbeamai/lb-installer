SELECT
    column_type,
    COUNT(*) AS type_count,
    ROUND((COUNT(*)::NUMERIC / total_count) * 100, 2) AS type_percentage
FROM
    (
        SELECT
            column_name,
            data_type || COALESCE('(' || character_maximum_length::VARCHAR || ')', '') AS column_type
        FROM
            information_schema.columns
        WHERE
            table_schema NOT LIKE 'pg_%' -- Exclude system schemas
            AND table_schema != 'information_schema' -- Exclude information_schema schema
    ) AS columns
CROSS JOIN
    (
        SELECT
            COUNT(*) AS total_count
        FROM
            information_schema.columns
        WHERE
            table_schema NOT LIKE 'pg_%' -- Exclude system schemas
            AND table_schema != 'information_schema' -- Exclude information_schema schema
    ) AS totals
GROUP BY
    column_type,
    total_count
ORDER BY
    type_count DESC;

