SELECT
    name AS database_name,
    (sum(size) * (@@maxpagesize / 1024)) / 1024 AS database_size_mb
FROM
    master.dbo.sysusages u
    JOIN master.dbo.sysdatabases d ON u.dbid = d.dbid
WHERE
    d.name NOT IN ('master', 'tempdb', 'model', 'sybsystemprocs', 'sybsecurity', 'sybsystemdb', 'dbccdb')
GROUP BY
    d.name
ORDER BY
    database_name
go
