SELECT
    table_schema,
    COUNT(DISTINCT table_name) AS table_count,
    COUNT(DISTINCT column_name) AS column_count
  FROM
    `db_name.INFORMATION_SCHEMA.COLUMNS`
  GROUP BY
    table_schema