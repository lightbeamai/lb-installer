SELECT
        'default' AS schema_name,
        c.table_name,
        '' AS table_description,
        c.column_name AS column_name,
        c.data_type AS data_type,
        '' AS column_description,
        c.ORDINAL_POSITION AS column_id,
        'db_name' AS DATABASE,
        FALSE AS is_view,
        0 AS num_rows,
        CASE WHEN lower(c.is_nullable) = 'yes' THEN
            TRUE
        WHEN lower(c.is_nullable) = 'no' THEN
            FALSE
        END AS is_nullable,
        NULL AS constraint_type,
        0 AS table_size
    FROM
        `db_name.INFORMATION_SCHEMA.COLUMNS` AS c
        JOIN (
            SELECT
                *
            FROM
                `db_name.INFORMATION_SCHEMA.TABLES`
            WHERE
                table_type in('BASE TABLE', 'EXTERNAL')) AS t ON c.table_catalog = t.table_catalog
        AND c.table_schema = t.table_schema
        AND c.table_name = t.table_name
    ORDER BY
        table_name