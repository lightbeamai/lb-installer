Please run each of the .sql files on that database with the account credentials that you need to connect to LightBeam.

Fetch Schema List:
```sql
psql -h <DATABASE_HOST_IP> -U <DATABASE_USER> -f schema_list.sql -p <PORT> -d <DATABASE_NAME> > schema_list
```

Fetch All Relations List:
```sql
psql -h <DATABASE_HOST_IP> -U <DATABASE_USER> -f fetch_all_relations.sql  -p <PORT> -d <DATABASE_NAME> > all_relations
```

Fetch all_tables_columns List:
```sql
psql -h <DATABASE_HOST_IP> -U <DATABASE_USER> -f all_tables_columns.sql -p <PORT> -d <DATABASE_NAME> > all_tables_columns
```





