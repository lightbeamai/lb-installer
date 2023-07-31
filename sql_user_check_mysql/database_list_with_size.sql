SELECT
	table_schema AS Database_Name,
	ROUND((data_length) / (1024 * 1024), 2) AS Database_Size_MB
FROM
	information_schema.tables
GROUP BY
	table_schema;