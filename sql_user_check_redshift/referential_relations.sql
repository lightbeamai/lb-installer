SELECT
	'LB_DATABASE_NAME' || '_' || ns_ref.nspname || '_' || cl.relname || '_' || a.attname || '_' ||
	ns_ref_rel.nspname || '_' || cl_ref.relname || '_' || b.attname AS constraint_name,
	ns_ref.nspname AS l_schema_name,
	cl.relname AS l_table_name,
	a.attname AS l_column_name,
	ns_ref_rel.nspname AS r_schema_name,
	cl_ref.relname AS r_table_name,
	b.attname AS r_column_name
FROM
	pg_constraint c
	LEFT JOIN pg_class cl ON c.conrelid = cl.oid
	LEFT JOIN pg_namespace ns ON cl.relnamespace = ns.oid
	LEFT JOIN pg_attribute a ON a.attnum = ANY (c.conkey) AND a.attrelid = cl.oid
	LEFT JOIN pg_class cl_ref ON c.confrelid = cl_ref.oid
	LEFT JOIN pg_namespace ns_ref ON cl_ref.relnamespace = ns_ref.oid
	LEFT JOIN pg_attribute b ON b.attnum = ANY (c.confkey) AND b.attrelid = cl_ref.oid
	LEFT JOIN pg_namespace ns_ref_rel ON cl_ref.relnamespace = ns_ref_rel.oid
WHERE
	contype = 'f'