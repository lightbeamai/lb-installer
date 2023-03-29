-- Fetch database dictionary
SELECT DISTINCT
            TBL.table_catalog AS [database],
            TBL.TABLE_SCHEMA AS [schema_name],
            TBL.TABLE_NAME AS [table_name],
            CAST(PROP.VALUE AS NVARCHAR (MAX)) AS [table_description],
            COL.COLUMN_NAME AS [column_name],
            COL.DATA_TYPE AS [data_type],
            ' ' AS [column_description],
            COL.ORDINAL_POSITION AS [column_id],
            cc.constraint_type,
            CAST(0 AS BIT) AS is_view,
            CASE WHEN lower(COL.is_nullable) = 'yes' THEN
                CAST(1 AS BIT)
            WHEN lower(COL.is_nullable) = 'no' THEN
                CAST(0 AS BIT)
            END AS is_nullable,
            isnull(stat.num_rows, 0) as num_rows,
            isnull(stat.table_size, 0) as table_size
        FROM
            (SELECT * FROM INFORMATION_SCHEMA.TABLES) TBL
            INNER JOIN INFORMATION_SCHEMA.COLUMNS COL ON (COL.TABLE_NAME = TBL.TABLE_NAME
                    AND COL.TABLE_SCHEMA = TBL.TABLE_SCHEMA)
            LEFT JOIN SYS.EXTENDED_PROPERTIES PROP
            ON (PROP.MAJOR_ID = OBJECT_ID (TBL.TABLE_SCHEMA + '.' + TBL.TABLE_NAME)
                    AND PROP.MINOR_ID = 0
                    AND PROP.NAME = 'MS_Description')
            LEFT JOIN (SELECT
                        tc.table_schema AS SCHEMA_NAME,
                        kcu.table_name,
                        kcu.column_name,
                        CASE WHEN count(tc.constraint_type) = 1 THEN
                            min(tc.constraint_type)
                        WHEN count(tc.constraint_type) = 2 THEN
                            'PRIMARY KEY'
                        END constraint_type
                    FROM
                        information_schema.table_constraints AS tc
                        JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
                    WHERE
                        tc.constraint_type in('PRIMARY KEY', 'FOREIGN KEY')
                    GROUP BY
                        tc.table_schema,
                        kcu.table_name,
                        kcu.column_name) AS cc ON COL.COLUMN_NAME = cc.column_name
            AND TBL.TABLE_SCHEMA = cc.schema_name
            AND TBL.TABLE_NAME = cc.table_name
            LEFT JOIN (
                SELECT
                    SCHEMA_NAME (sOBJ.schema_id) AS [schema_name],
                    sOBJ.name AS [table_name],
                    MAX(sPTN.Rows) AS [num_rows],
                    MAX(a.used_pages) * 8 * 1024 AS [table_size]
                FROM
                    sys.objects AS sOBJ
                    INNER JOIN sys.partitions AS sPTN ON sOBJ.object_id = sPTN.object_id
                    INNER JOIN sys.allocation_units as a ON sPTN.partition_id = a.container_id
                GROUP BY
                    sOBJ.schema_id,
                    sOBJ.name) AS stat ON TBL.TABLE_SCHEMA = stat.schema_name
            AND TBL.TABLE_NAME = stat.table_name
        WHERE TBL.table_schema NOT IN ('information_schema', 'sys')
        ORDER BY
            SCHEMA_NAME,
            table_name,
            column_id
        FOR JSON PATH;
-- Fetch relationships
SELECT DISTINCT
        rc1.*,
        kcu1.table_schema AS r_schema_name,
        kcu1.table_name AS r_table_name,
        kcu1.column_name AS r_column_name,
        rc1.fk_constraint_name AS constraint_name
    FROM (
        SELECT
            *
        FROM
            information_schema.key_column_usage
        WHERE
            table_schema NOT IN ('information_schema', 'sys')) kcu1
        JOIN (
            SELECT
                table_schema AS l_schema_name, table_name AS l_table_name, column_name AS l_column_name,
                pk_constraint_name, fk_constraint_name
            FROM
                information_schema.key_column_usage kcu
                JOIN (
                    SELECT
                        constraint_name AS fk_constraint_name,
                        unique_constraint_name AS pk_constraint_name
                    FROM
                        information_schema.referential_constraints) rc
                        ON kcu.constraint_name = pk_constraint_name) AS rc1
                        ON kcu1.constraint_name = rc1.fk_constraint_name
            FOR JSON PATH;