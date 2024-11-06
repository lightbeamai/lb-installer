SELECT
	DATA_TYPE_NAME AS data_type,
	COUNT(*) AS count
FROM
	SYS.TABLE_COLUMNS
WHERE
	SCHEMA_NAME NOT LIKE 'SYS%' AND SCHEMA_NAME NOT LIKE '_SYS%'
GROUP BY
	DATA_TYPE_NAME
ORDER BY
	count DESC;