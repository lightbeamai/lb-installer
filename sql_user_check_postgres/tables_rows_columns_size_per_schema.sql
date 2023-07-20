SELECT
	cc.table_schema,
	cc.column_count,
	rc.row_count,
	tc.table_count,
	ss.schema_size
FROM (
	SELECT
		table_schema,
		COUNT(column_name) AS column_count
	FROM
		information_schema.columns
	WHERE
		table_schema NOT IN('information_schema', 'pg_catalog', 'pg_toast', 'pg_temp_1', 'pg_toast_temp1')
	GROUP BY
		table_schema) AS cc
	LEFT JOIN (
		SELECT
			sum(n_live_tup) AS row_count,
			schemaname
		FROM
			pg_stat_all_tables
		WHERE
			schemaname NOT IN('information_schema', 'pg_catalog', 'pg_toast', 'pg_temp_1', 'pg_toast_temp1')
		GROUP BY
			schemaname) AS rc ON rc.schemaname = cc.table_schema
	LEFT JOIN (
		SELECT
			table_schema,
			COUNT(table_name) AS table_count
		FROM
			information_schema.tables
		WHERE
			table_type = 'BASE TABLE'
			AND table_schema NOT IN('information_schema', 'pg_catalog', 'pg_toast', 'pg_temp_1', 'pg_toast_temp1')
		GROUP BY
			table_schema) AS tc ON rc.schemaname = tc.table_schema
	LEFT JOIN (
		SELECT
			nspname AS schema_name,
			pg_size_pretty(sum(pg_total_relation_size(quote_ident(schemaname) || '.' || quote_ident(tablename)))) AS schema_size
		FROM
			pg_tables
			JOIN pg_namespace ON pg_tables.schemaname = pg_namespace.nspname
		GROUP BY
			nspname) AS ss ON ss.schema_name = tc.table_schema