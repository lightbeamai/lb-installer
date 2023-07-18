SELECT
    ic.table_schema,ic.table_name,
    count(distinct(concat_ws('.', ic.table_schema, ic.table_name, ic.column_name))) AS column_count
FROM
    information_schema.columns ic 
WHERE
    ic.table_schema NOT LIKE 'pg_%' -- Exclude system schemas
    AND  ic.table_schema != 'information_schema' -- Exclude information_schema schema
group by ic.table_schema, ic.table_name
