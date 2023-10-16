SELECT
	svt.schema,
	count(svt.table),
	sum(size) AS tbl_size_in_mb,
	sum(tbl_rows)
FROM
	svv_table_info AS svt
GROUP BY
	svt.schema
