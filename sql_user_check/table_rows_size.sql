
SELECT pg_stat_all_tables.schemaname, relname AS table_name, n_live_tup AS num_rows,
       pg_size_pretty(pg_relation_size('"' || schemaname || '"."' || relname || '"')) AS table_size
FROM pg_catalog.pg_stat_all_tables
WHERE schemaname
  NOT LIKE 'pg_%' -- Exclude system schemas
  AND schemaname != 'information_schema' -- Exclude information_schema schema
