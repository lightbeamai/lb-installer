SELECT
table_schema AS schema_name,
count(distinct(concat_ws('.', table_schema, table_name))) AS table_count, count(distinct(concat_ws('.', table_schema, table_name, column_name))) AS column_count
 FROM information_schema."columns"
WHERE
lower(table_schema)
NOT in('pg_catalog','pg_temp_1','pg_toast_temp1','information_schema','pg_toast')
GROUP BY table_schema
