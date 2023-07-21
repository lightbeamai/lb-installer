SELECT
	t1.schema_name,
	t1.table_count,
	t1.column_count,
	t2.row_count
FROM (
	SELECT
		c.TABLE_SCHEMA AS schema_name,
		COUNT(DISTINCT c.TABLE_NAME) AS table_count,
		COUNT(COLUMN_NAME) AS column_count
	FROM
		INFORMATION_SCHEMA.TABLES t
	LEFT JOIN INFORMATION_SCHEMA.COLUMNS c ON t.TABLE_NAME = c.TABLE_NAME
		AND t.TABLE_SCHEMA = c.TABLE_SCHEMA
WHERE
	TABLE_TYPE = 'BASE TABLE' -- Filters only for base tables (not views)
GROUP BY
	c.TABLE_SCHEMA) AS t1
	LEFT JOIN (
		SELECT
			SCHEMA_NAME (A.schema_id) AS schema_name,
			SUM(B.rows) AS row_count
		FROM
			sys.objects A
			INNER JOIN sys.partitions B ON A.object_id = B.object_id
		WHERE
			A.type = 'U'
		GROUP BY
			A.schema_id) AS t2 ON t1.schema_name = t2.schema_name