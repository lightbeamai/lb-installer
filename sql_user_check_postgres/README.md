# Postgres User Check

database_stats.sh script can be used to test connectivity with Postgres database as well as fetch some stats and metadata. 
The script supports 2 modes which can be specified with -m flag while running the script. One mode is stats mode which 
will just print info like list of databases with their size. Count of tables, rows, column, size per schema. 
Distribution of data by data type. Stats mode is the default mode. Another mode is full_metadata which will print 
complete information of all columns like their data type, constraints etc.

From `sql_user_check_postgres` directory, run these commands depending on mode of script. This will ask
for database password.

stats Mode:
```shell
./database_stats.sh -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -d <DATABASE_NAME> -o <OUTPUT_FILE> -p <PORT_NUMBER>
```

full_metadata Mode:
```shell
./database_stats.sh -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -d <DATABASE_NAME> -m full_metadata -o <OUTPUT_FILE> -p <PORT_NUMBER>
```
