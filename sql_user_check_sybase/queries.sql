-- Fetch database dictionary
SELECT
    db_name() AS [database],
    u.name AS schema_name,
    o.name AS table_name,
    c.name AS column_name,
    t.name AS data_type,
    c.colid AS column_id,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM sysindexes i
            WHERE i.id = o.id
              AND i.status & 2048 = 2048
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
    'false' AS is_view,
    CASE WHEN c.status & 8 = 8 THEN 'true' ELSE 'false' END AS is_nullable,
    ISNULL(row_count(db_id(), o.id), 0) AS num_rows
FROM
    dbo.sysobjects o
    INNER JOIN dbo.sysusers u ON o.uid = u.uid
    INNER JOIN dbo.syscolumns c ON o.id = c.id
    INNER JOIN dbo.systypes t ON c.usertype = t.usertype
WHERE
    o.type = 'U'
ORDER BY
    schema_name,
    table_name,
    column_id
go

-- Fetch relationships (foreign keys)
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
