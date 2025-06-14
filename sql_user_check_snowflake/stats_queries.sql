USE DATABASE LB_DATABASE_NAME;

SELECT
  table_schema AS schema,
  SUM(bytes) AS bytes
FROM information_schema.tables
where schema not in ('INFORMATION_SCHEMA') AND t.TABLE_TYPE = 'BASE TABLE'
GROUP BY schema;

SELECT
  TABLE_SCHEMA AS schema_name,
  DATA_TYPE,
  COUNT(*) AS column_count
FROM
  INFORMATION_SCHEMA.COLUMNS
WHERE
  TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA') AND t.TABLE_TYPE = 'BASE TABLE'
GROUP BY
  TABLE_SCHEMA, DATA_TYPE;

SELECT
  t.TABLE_CATALOG AS database_name,
  t.TABLE_SCHEMA AS schema_name,
  COUNT(DISTINCT t.TABLE_NAME) AS table_count,
  SUM(COLUMN_COUNT) AS column_count,
  SUM(ROW_COUNT) AS row_count
FROM
  INFORMATION_SCHEMA.TABLES t
LEFT JOIN
  (SELECT
    TABLE_CATALOG,
    TABLE_SCHEMA,
    TABLE_NAME,
    COUNT(*) AS COLUMN_COUNT
   FROM
     INFORMATION_SCHEMA.COLUMNS
   GROUP BY
     TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME
   ) c ON t.TABLE_CATALOG = c.TABLE_CATALOG AND t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME
WHERE
  t.TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA')
  AND t.TABLE_TYPE = 'BASE TABLE'
GROUP BY
  t.TABLE_CATALOG, t.TABLE_SCHEMA
ORDER BY
  database_name, schema_name;