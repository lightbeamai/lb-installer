SELECT
  c.table_schema AS schema_name,
c.table_name AS table_name, COALESCE(pgtd.description, '') AS table_description, c.column_name AS column_name,
c.data_type AS data_type, COALESCE(pgcd.description, '') AS column_description, ordinal_position AS column_id,
c.table_catalog AS DATABASE,
FALSE AS is_view,
COALESCE(table_stats.num_rows, 0) AS num_rows, CASE WHEN lower(c.is_nullable) = 'yes' THEN
TRUE
WHEN lower(c.is_nullable) = 'no' THEN
FALSE
END AS is_nullable,
cc.constraint_type, COALESCE(table_stats.table_size, 0) AS table_size
FROM ( SELECT
* FROM
INFORMATION_SCHEMA.COLUMNS WHERE
lower(table_schema)
NOT in ('pg_catalog','pg_temp_1','pg_toast_temp1','information_schema','pg_toast')) AS c
LEFT JOIN ( SELECT
* FROM
pg_catalog.pg_statio_all_tables WHERE
schemaname NOT in('pg_catalog','pg_temp_1','pg_toast_temp1','information_schema','pg_toast')) AS st
ON c.table_schema = st.schemaname
AND c.table_name = st.relname
LEFT JOIN pg_catalog.pg_description pgcd ON pgcd.objoid = st.relid

  AND pgcd.objsubid = c.ordinal_position
LEFT JOIN pg_catalog.pg_description pgtd ON pgtd.objoid = st.relid
AND pgtd.objsubid = 0 LEFT JOIN (
SELECT
pg_stat_all_tables.schemaname, relname AS table_name, n_live_tup AS num_rows,
pg_relation_size('"' || schemaname || '"."' || relname || '"') AS table_size FROM (
SELECT *
FROM pg_catalog.pg_stat_all_tables
WHERE schemaname NOT
in('pg_catalog','pg_temp_1','pg_toast_temp1','information_schema','pg_toast')) pg_stat_all_tables) table_stats
ON c.table_schema = table_stats.schemaname AND c.table_name = table_stats.table_name
LEFT JOIN ( SELECT DISTINCT
tc.table_schema AS SCHEMA_NAME, kcu.table_name,
kcu.column_name,
CASE WHEN count(tc.constraint_type) = 1 THEN
min(tc.constraint_type)
WHEN count(tc.constraint_type) = 2 THEN
'PRIMARY KEY' END constraint_type
FROM
information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage kcu ON tc.constraint_name =
kcu.constraint_name WHERE
tc.constraint_type in('PRIMARY KEY', 'FOREIGN KEY') GROUP BY tc.table_schema,
kcu.table_name,
kcu.column_name) AS cc ON c.column_name = cc.column_name AND c.table_schema = cc.schema_name

 AND c.table_name = cc.table_name ORDER BY c.table_schema, c.table_name
