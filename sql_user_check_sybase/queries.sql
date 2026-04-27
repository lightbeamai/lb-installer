-- Mirrors the production metadata extractor queries from
-- python-utils/structured_data/structured_data_utils/consts.py:
--   * SYBASE_METADATA_EXTRACTOR_SQL  -- user tables (type = 'U')
--   * SYBASE_VIEWS_EXTRACTOR_SQL     -- views (type = 'V'), excludes sysquerymetrics
--
-- Running these here verifies that the LightBeam scanner user has the same
-- read access the production extractor needs. Plus a foreign-key dump for
-- diagnostic purposes.

-- Tables: SYBASE_METADATA_EXTRACTOR_SQL
SELECT
    u.name AS schema_name,
    o.name AS table_name,
    '' AS table_description,
    c.name AS column_name,
    t.name AS data_type,
    '' AS column_description,
    DB_NAME() AS [database],
    'false' AS is_view,
    ISNULL(row_count(DB_ID(), o.id), -1) AS num_rows,
    CASE WHEN c.status & 8 = 8 THEN 'true' ELSE 'false' END AS is_nullable,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM sysindexes i
            WHERE i.id = o.id AND i.status & 2048 = 2048
            AND (
                c.name = INDEX_COL(o.name, i.indid, 1) OR
                c.name = INDEX_COL(o.name, i.indid, 2) OR
                c.name = INDEX_COL(o.name, i.indid, 3) OR
                c.name = INDEX_COL(o.name, i.indid, 4) OR
                c.name = INDEX_COL(o.name, i.indid, 5) OR
                c.name = INDEX_COL(o.name, i.indid, 6) OR
                c.name = INDEX_COL(o.name, i.indid, 7) OR
                c.name = INDEX_COL(o.name, i.indid, 8) OR
                c.name = INDEX_COL(o.name, i.indid, 9) OR
                c.name = INDEX_COL(o.name, i.indid, 10) OR
                c.name = INDEX_COL(o.name, i.indid, 11) OR
                c.name = INDEX_COL(o.name, i.indid, 12) OR
                c.name = INDEX_COL(o.name, i.indid, 13) OR
                c.name = INDEX_COL(o.name, i.indid, 14) OR
                c.name = INDEX_COL(o.name, i.indid, 15) OR
                c.name = INDEX_COL(o.name, i.indid, 16)
            )
        ) THEN 'PRIMARY KEY'
        ELSE NULL
    END AS constraint_type,
    (CONVERT(bigint, data_pages(DB_ID(), o.id, 0))
        + CONVERT(bigint, data_pages(DB_ID(), o.id, 1))) * CONVERT(bigint, @@maxpagesize) AS table_size
FROM dbo.sysobjects o
INNER JOIN dbo.syscolumns c ON o.id = c.id
INNER JOIN dbo.systypes t ON c.usertype = t.usertype
INNER JOIN dbo.sysusers u ON o.uid = u.uid
WHERE o.type = 'U'
ORDER BY u.name, o.name, c.colid
go

-- Views: SYBASE_VIEWS_EXTRACTOR_SQL
SELECT
    u.name AS schema_name,
    o.name AS table_name,
    '' AS table_description,
    c.name AS column_name,
    t.name AS data_type,
    '' AS column_description,
    DB_NAME() AS [database],
    'true' AS is_view,
    -1 AS num_rows,
    CASE WHEN c.status & 8 = 8 THEN 'true' ELSE 'false' END AS is_nullable,
    NULL AS constraint_type,
    0 AS table_size
FROM dbo.sysobjects o
INNER JOIN dbo.syscolumns c ON o.id = c.id
INNER JOIN dbo.systypes t ON c.usertype = t.usertype
INNER JOIN dbo.sysusers u ON o.uid = u.uid
WHERE o.type = 'V'
    AND o.name NOT IN ('sysquerymetrics')
ORDER BY u.name, o.name, c.colid
go

-- Foreign-key relationships (diagnostic; no production equivalent).
SELECT
    u_fk.name AS l_schema_name,
    o_fk.name AS l_table_name,
    c_fk.name AS l_column_name,
    u_pk.name AS r_schema_name,
    o_pk.name AS r_table_name,
    c_pk.name AS r_column_name,
    r.constrid AS constraint_id
FROM
    sysreferences r
    INNER JOIN sysobjects o_fk ON r.tableid = o_fk.id
    INNER JOIN sysusers u_fk ON o_fk.uid = u_fk.uid
    INNER JOIN sysobjects o_pk ON r.reftabid = o_pk.id
    INNER JOIN sysusers u_pk ON o_pk.uid = u_pk.uid
    INNER JOIN syscolumns c_fk ON r.tableid = c_fk.id AND c_fk.colid = r.fokey1
    INNER JOIN syscolumns c_pk ON r.reftabid = c_pk.id AND c_pk.colid = r.refkey1
ORDER BY
    l_schema_name,
    l_table_name,
    l_column_name
go
