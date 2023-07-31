SELECT
	table_counts.TABLE_SCHEMA,
	COUNT(*) AS total_tables,
	SUM(TABLE_ROWS) AS total_rows,
	SUM(COLUMN_COUNT) AS total_columns
FROM (
	SELECT
		information_schema.tables.TABLE_SCHEMA,
		information_schema.tables.TABLE_NAME,
		IFNULL(TABLE_ROWS, 0) AS TABLE_ROWS,
		COUNT(*) AS COLUMN_COUNT
	FROM
		information_schema.tables
	LEFT JOIN information_schema.columns ON information_schema.tables.TABLE_NAME = information_schema.columns.TABLE_NAME
WHERE
	information_schema.tables.TABLE_SCHEMA NOT IN('information_schema', 'performance_schema', 'mysql', 'sys', 'innodb')
GROUP BY
	information_schema.tables.TABLE_SCHEMA,
	information_schema.tables.TABLE_NAME,
	TABLE_ROWS) AS table_counts;
