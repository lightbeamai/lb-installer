SELECT
    pg_size_pretty(pg_database_size(datname)) AS database_size,
    datname AS database_name
FROM
    pg_database
ORDER BY
    database_size DESC;
