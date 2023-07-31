SELECT
    name AS database_name,
    size * 8 / 1024 AS database_size_mb
FROM
    sys.master_files
WHERE
    name not in ('master', 'model', 'msdb', 'tempdb', 'rdsadmin')
ORDER BY
    database_name;