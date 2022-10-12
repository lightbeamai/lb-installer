Please run each of the .sql files on the User and Database that you need to connect to LightBeam.
Refer the examples below.

Fetch Schema List:
psql -h <DATABASE_HOST_IP> -U <DATABASE_USER> -f schema_list.sql -p <PORT> -d <DATABASE_NAME> > schema_list


Fetch All Relations List:
psql -h <DATABASE_HOST_IP> -U <DATABASE_USER> -f fetch_all_relations.sql  -p <PORT> -d <DATABASE_NAME> > all_relations


Fetch all_tables_columns List:
psql -h <DATABASE_HOST_IP> -U <DATABASE_USER> -f all_tables_columns.sql -p <PORT> -d <DATABASE_NAME> > all_tables_columns




