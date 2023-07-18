select schemaname, sum(n_live_tup) from pg_stat_all_tables 
WHERE schemaname 
     NOT LIKE 'pg_%' -- Exclude system schemas
     AND schemaname != 'information_schema' -- Exclude information_schema schema
group by schemaname 

