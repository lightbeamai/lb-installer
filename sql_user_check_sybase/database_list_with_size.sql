-- Lists user databases on the Sybase ASE server with their sizes.
-- Mirrors SYBASE_DATABASE_LIST_SQL in
-- python-utils/structured_data/structured_data_utils/sybase/consts.py
-- (system database exclusion list: master, tempdb, model, sybsystemprocs,
-- sybsecurity, sybsystemdb, sybpcidb, dbccdb, sybmgmtdb, sybdiag).
--
-- The minimal-permissions onboarding user can read master..sysdatabases /
-- sysusages via the default `guest` user in master, which is how the
-- production scanner discovers databases.
SELECT
    d.name AS database_name,
    (SUM(u.size) * (@@maxpagesize / 1024)) / 1024 AS database_size_mb
FROM
    master..sysusages u
    JOIN master..sysdatabases d ON u.dbid = d.dbid
WHERE
    d.name NOT IN ('master', 'tempdb', 'model', 'sybsystemprocs',
                   'sybsecurity', 'sybsystemdb', 'sybpcidb', 'dbccdb',
                   'sybmgmtdb', 'sybdiag')
GROUP BY
    d.name
ORDER BY
    database_name
go
