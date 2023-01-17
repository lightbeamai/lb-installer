SELECT views.TABLE_NAME   AS `source_table_name`,
       tab.TABLE_NAME     AS `destination_table_name`,
       views.TABLE_SCHEMA AS `source_schema_name`,
       tab.TABLE_SCHEMA   AS `destination_schema_name`
FROM information_schema.`TABLES` AS tab
         INNER JOIN information_schema.VIEWS AS views ON views.VIEW_DEFINITION LIKE CONCAT('%`', tab.TABLE_NAME, '`%');
