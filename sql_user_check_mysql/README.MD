Please run each of the .sql files on that database with the account credentials that you need to connect to LightBeam.

Fetch Schema List:
Update the database name in schema_list.sql query and run:
```sql
mysql -h <DATABASE_HOST_IP> --port=<port> -u <DATABASE_USER> -p < schema_list.sql > schema_list
```

Fetch All Relation List:
Update the database name in fetch_all_relations.sql query and run:
```sql
mysql -h <DATABASE_HOST_IP> --port=<port> -u <DATABASE_USER> -p < fetch_all_relations.sql > all_relations
```

Fetch All Tables And Columns List:
Update the database name in all_tables_columns.sql query and run:
```sql
mysql -h <DATABASE_HOST_IP> --port=<port> -u <DATABASE_USER> -p < all_tables_columns.sql > all_tables_columns
```
