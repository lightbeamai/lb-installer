SELECT DISTINCT 'default'                       AS schema_name,
                c.table_name                    AS table_name,
                COALESCE(tt.TABLE_COMMENT, '')  AS table_description,
                c.column_name                   AS column_name,
                c.data_type                     AS data_type,
                COALESCE(c.column_comment, ' ') AS column_description,
                ordinal_position                AS column_id,
                c.table_schema                  AS "database",
                FALSE                           AS is_view,
                COALESCE(tt.table_rows, 0)      AS num_rows,
                CASE
                    WHEN lower(c.is_nullable) = 'yes' THEN
                        TRUE
                    WHEN lower(c.is_nullable) = 'no' THEN
                        FALSE
                    END                         AS is_nullable,
                cc.constraint_type,
                COALESCE(tt.data_length, 0)     AS table_size
FROM (SELECT *
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE table_schema = '__db_name__') AS c # <--- Update here
         LEFT JOIN INFORMATION_SCHEMA.tables AS tt ON c.table_schema = tt.table_schema
    AND c.table_name = tt.table_name
         LEFT JOIN (SELECT DISTINCT tc.table_schema         AS SCHEMA_NAME,
                                    kcu.table_name,
                                    kcu.column_name,
                                    max(tc.constraint_type) AS constraint_type
                    FROM information_schema.table_constraints AS tc
                             JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
                    WHERE tc.constraint_type in ('PRIMARY KEY', 'FOREIGN KEY')
                    GROUP BY tc.table_schema,
                             kcu.table_name,
                             kcu.column_name) AS cc ON c.column_name = cc.column_name
    AND c.table_schema = cc.schema_name
    AND c.table_name = cc.table_name
ORDER BY c.table_schema,
         c.table_name;
