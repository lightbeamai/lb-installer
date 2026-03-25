SELECT
    u.name AS schema_name,
    t.name AS data_type,
    COUNT(*) AS column_count
FROM
    dbo.sysobjects o
    INNER JOIN dbo.sysusers u ON o.uid = u.uid
    INNER JOIN dbo.syscolumns c ON o.id = c.id
    INNER JOIN dbo.systypes t ON c.usertype = t.usertype
WHERE
    o.type = 'U'
GROUP BY
    u.name,
    t.name
ORDER BY
    schema_name,
    data_type
go
