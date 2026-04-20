Please run each of the .sql files on that database with the account credentials that you need to connect to LightBeam.

Fetch Schema List:
Update the database name in schema_list.sql query and run:
```sql
mariadb -h <DATABASE_HOST_IP> --port=<port> -u <DATABASE_USER> -p < schema_list.sql > schema_list
```

Fetch All Relation List:
Update the database name in fetch_all_relations.sql query and run:
```sql
mariadb -h <DATABASE_HOST_IP> --port=<port> -u <DATABASE_USER> -p < fetch_all_relations.sql > all_relations
```

Fetch All Tables And Columns List:
Update the database name in all_tables_columns.sql query and run:
```sql
mariadb -h <DATABASE_HOST_IP> --port=<port> -u <DATABASE_USER> -p < all_tables_columns.sql > all_tables_columns
```

# MariaDB User Check

database_stats.sh script can be used to test connectivity with a MariaDB database as well as fetch some stats and metadata.
The script supports 2 modes which can be specified with -m flag while running the script. One mode is stats mode which
will just print info like list of databases with their size. Count of tables, rows, column, size per schema.
Distribution of data by data type. Stats mode is the default mode. Another mode is full_metadata which will print
complete information of all columns like their data type, constraints etc. MariaDB uses 3306 as default port.

### Pre-requisites

Install the [MariaDB client](https://mariadb.com/kb/en/mariadb-package-repository-setup-and-usage/) on the machine.
The script uses the `mariadb` command (available in MariaDB 10.4+). If only the `mysql` command is available on your
system it will be used automatically as a fallback.

From `sql_user_check_mariadb` directory, run these commands depending on mode of script. You will be prompted for password.

Stats mode:
```shell
./database_stats.sh -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -o <OUTPUT_FILE> -p <PORT_NUMBER>
```

Full metadata mode:
```shell
./database_stats.sh -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -m full_metadata -o <OUTPUT_FILE> -p <PORT_NUMBER>
```
