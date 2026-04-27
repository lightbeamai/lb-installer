-- Schema-level counts. Mirrors DEFAULT_SYBASE_SCHEMA_LIST in
-- python-utils/structured_data/structured_data_utils/sybase/consts.py
-- (user tables only, type = 'U'), with row_count added for convenience.
SELECT
    u.name AS schema_name,
    COUNT(DISTINCT o.name) AS table_count,
    COUNT(c.name) AS column_count,
    ISNULL(SUM(row_count(db_id(), o.id)), 0) AS row_count
FROM
    dbo.sysobjects o
    INNER JOIN dbo.sysusers u ON o.uid = u.uid
    INNER JOIN dbo.syscolumns c ON o.id = c.id
WHERE
    o.type = 'U'
GROUP BY
    u.name
ORDER BY
    schema_name
go
