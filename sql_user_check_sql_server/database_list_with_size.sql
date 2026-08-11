-- sys.master_files has one row per file, so the rows are grouped by database
-- to report a single size per database. DB_NAME() is used because
-- sys.master_files.name is the logical file name, not the database name.
SELECT
    DB_NAME(database_id) AS database_name,
    CAST(SUM(CAST(size AS BIGINT)) * 8 / 1024 AS BIGINT) as database_size_mb
FROM
    sys.master_files
WHERE
    DB_NAME(database_id) is not null
    and DB_NAME(database_id) not in ('master', 'model', 'msdb', 'tempdb', 'rdsadmin')
GROUP BY
    DB_NAME(database_id)
ORDER BY
    database_name;
