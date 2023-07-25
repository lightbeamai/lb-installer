SELECT
    c.table_schema AS schema_name,
	c.table_name AS table_name,
	COALESCE(pgtd.description, '') AS table_description,
	c.column_name AS column_name,
	c.data_type AS data_type,
	COALESCE(pgcd.description, '') AS column_description,
	c.ordinal_position AS column_id,
	c.table_catalog AS DATABASE,
	FALSE AS is_view,
	CASE WHEN lower(c.is_nullable) = 'yes' THEN
		TRUE
	WHEN lower(c.is_nullable) = 'no' THEN
		FALSE
	END AS is_nullable,
	cc.constraint_type,
	0 AS num_rows,
	0 AS table_size
FROM (
	SELECT
		ic.*
	FROM
		INFORMATION_SCHEMA.COLUMNS ic
	LEFT JOIN INFORMATION_SCHEMA.VIEWS iv ON ic.table_schema = iv.table_schema
		AND ic.table_name = iv.table_name
WHERE
	lower(ic.table_schema) NOT in ('information_schema', 'pg_catalog', 'pg_internal') AND iv.table_schema IS NULL) AS c
	LEFT JOIN (
		SELECT
			*
		FROM
			pg_catalog.pg_statio_all_tables
		WHERE
			schemaname NOT in ('information_schema', 'pg_catalog', 'pg_internal')) AS st ON c.table_schema = st.schemaname
	AND c.table_name = st.relname
	LEFT JOIN pg_catalog.pg_description pgcd ON pgcd.objoid = st.relid
		AND pgcd.objsubid = c.ordinal_position
	LEFT JOIN pg_catalog.pg_description pgtd ON pgtd.objoid = st.relid
		AND pgtd.objsubid = 0
	LEFT JOIN (
		SELECT
			pgn.nspname AS schema_name, c.relname AS table_name, a.attname AS column_name,
			CASE WHEN co.contype = 'p' THEN
				'PRIMARY KEY'
			WHEN co.contype = 'f' THEN
				'FOREIGN KEY'
			END constraint_type
		FROM
			pg_class c
			JOIN pg_attribute a ON c.oid = a.attrelid
			LEFT JOIN pg_constraint co ON a.attnum = ANY (co.conkey)
				AND c.oid = co.conrelid
		LEFT JOIN pg_namespace pgn ON pgn.oid = c.relnamespace) AS cc ON c.column_name = cc.column_name
		AND c.table_schema = cc.schema_name
		AND c.table_name = cc.table_name
	ORDER BY
		c.table_schema,
		c.table_name