SELECT
    tc.SCHEMA_NAME AS SCHEMA_NAME,
    FALSE AS is_view,
    tc.TABLE_NAME,
    tc.COLUMN_NAME,
    tc.DATA_TYPE_NAME AS DATA_TYPE,
    tc.IS_NULLABLE,
    cc.CONSTRAINT AS CONSTRAINT_TYPE,
    mt.RECORD_COUNT AS NUM_ROWS,
    mt.TABLE_SIZE,
    NULL AS TABLE_DESCRIPTION,
    tc.COMMENTS AS COLUMN_DESCRIPTION
FROM
    SYS.TABLE_COLUMNS tc
LEFT JOIN
    (SELECT
        ic.SCHEMA_NAME,
        ic.TABLE_NAME,
        ic.COLUMN_NAME,
        ic.CONSTRAINT
    FROM
        SYS.INDEX_COLUMNS ic
    WHERE
        ic.SCHEMA_NAME = 'DATABASE_NAME') as cc
    ON tc.TABLE_NAME = cc.TABLE_NAME
    AND tc.COLUMN_NAME = cc.COLUMN_NAME
    AND tc.SCHEMA_NAME = cc.SCHEMA_NAME
LEFT JOIN
    SYS.M_TABLES mt
    ON tc.TABLE_NAME = mt.TABLE_NAME
    AND tc.SCHEMA_NAME = mt.SCHEMA_NAME
WHERE
    tc.SCHEMA_NAME = 'DATABASE_NAME'
ORDER BY
    tc.TABLE_NAME,
    tc.COLUMN_NAME