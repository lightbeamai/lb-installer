Please run each of the .sql files on that database with the account credentials that you need to connect to LightBeam.

Fetch Schema List:
```sql
mysql -h <DATABASE_HOST_IP> --port=<port> -u <DATABASE_USER> -p < schema_list.sql > schema_list
```

Fetch All Relations List:
```sql
mysql -h <DATABASE_HOST_IP> --port=<port> -u <DATABASE_USER> -p < fetch_all_relations.sql > all_relations
```

Fetch all_tables_columns List:
```sql
mysql -h <DATABASE_HOST_IP> --port=<port> -u <DATABASE_USER> -p < all_tables_columns.sql > all_tables_columns
```
