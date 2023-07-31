SELECT
	TABLE_SCHEMA AS schema_name,
	DATA_TYPE AS data_type,
	COUNT(*) AS column_count
FROM
	INFORMATION_SCHEMA.COLUMNS
WHERE
	table_schema NOT in('information_schema', 'sys')
GROUP BY
	TABLE_SCHEMA,
	DATA_TYPE
ORDER BY
	schema_name,
	data_type;
