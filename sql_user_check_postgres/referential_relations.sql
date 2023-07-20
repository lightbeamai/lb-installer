SELECT DISTINCT
	concat_ws('_', pk_constraint_name, fk_constraint_name) AS constraint_name,
	rc1.*,
	kcu1.table_schema AS r_schema_name,
	kcu1.table_name AS r_table_name,
	kcu1.column_name AS r_column_name
FROM
	information_schema.key_column_usage AS kcu1
	JOIN (
		SELECT
			table_schema AS l_schema_name,
			table_name AS l_table_name,
			column_name AS l_column_name,
			pk_constraint_name,
			fk_constraint_name
		FROM
			information_schema.key_column_usage AS kcu
			JOIN (
				SELECT
					constraint_name AS fk_constraint_name,
					unique_constraint_name AS pk_constraint_name
				FROM
					information_schema.referential_constraints) AS rc ON kcu.constraint_name = pk_constraint_name) AS rc1 ON kcu1.constraint_name = rc1.fk_constraint_name