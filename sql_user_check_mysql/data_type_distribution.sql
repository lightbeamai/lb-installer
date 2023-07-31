SELECT
	column_type AS data_type,
	COUNT(*) AS count
FROM
	information_schema.columns
WHERE
	table_schema NOT IN('information_schema', 'performance_schema', 'mysql', 'sys', 'innodb')
GROUP BY
	column_type
ORDER BY
	count DESC;