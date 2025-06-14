USE DATABASE LB_DATABASE_NAME;
SELECT
    table_schema AS schema_name,
    count(TABLE_NAME) AS table_count
FROM
    LB_DATABASE_NAME.INFORMATION_SCHEMA."TABLES"
WHERE
    table_schema not in ('INFORMATION_SCHEMA')
GROUP BY
    table_schema;
SHOW PRIMARY KEYS in DATABASE LB_DATABASE_NAME;
SELECT
        replace(c.column_name, '/', '_') AS column_name,
        coalesce(c.comment, ' ') AS column_description,
        c.data_type AS data_type,
        c.ordinal_position AS column_id,
        c.table_catalog AS database,
        c.table_schema AS schema_name,
        replace(c.table_name, '/', '_') AS table_name,
        coalesce(t.comment, ' ') AS table_description,
        decode(lower(t.table_type), 'view', 'true', 'false') AS is_view,
        c.constraint_type,
        decode(lower(c.is_nullable), 'yes', 'true', 'false') AS is_nullable,
        t.row_count AS num_rows,
        t.bytes AS table_size
    FROM (
        SELECT
            cols.*,
            constraints.constraint_type
        FROM
            LB_DATABASE_NAME.INFORMATION_SCHEMA.COLUMNS cols
        LEFT JOIN (
            SELECT DISTINCT
                "database_name" AS database_name,
                "schema_name" AS schema_name,
                "table_name" AS table_name,
                "column_name" AS column_name,
                'primary_key' AS constraint_type
            FROM
                table(result_scan(last_query_id()))
        ) constraints ON cols.table_catalog = constraints.database_name
        AND cols.table_schema = constraints.schema_name
        AND cols.table_name = constraints.table_name
        AND cols.column_name = constraints.column_name
    WHERE
        cols.table_schema NOT in('INFORMATION_SCHEMA') AND t.TABLE_TYPE = 'BASE TABLE' ) AS c
        LEFT JOIN LB_DATABASE_NAME.INFORMATION_SCHEMA.TABLES t ON c.TABLE_NAME = t.TABLE_NAME
            AND c.TABLE_SCHEMA = t.TABLE_SCHEMA
        ORDER BY
            c.TABLE_NAME, c.TABLE_SCHEMA;
SHOW IMPORTED KEYS in DATABASE LB_DATABASE_NAME;
SELECT
    "pk_schema_name" AS l_schema_name,
    replace("pk_table_name", '/', '_') AS l_table_name,
    replace("pk_column_name", '/', '_') AS l_column_name,
    "fk_schema_name" AS r_schema_name,
    replace("fk_table_name", '/', '_') AS r_table_name,
    replace("fk_column_name", '/', '_') AS r_column_name,
    "fk_name" AS constraint_name
FROM
    TABLE (result_scan (last_query_id ()));