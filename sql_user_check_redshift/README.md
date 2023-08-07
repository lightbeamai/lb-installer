# Redshift User Check

database_stats.sh script can be used to test connectivity with Redshift database as well as fetch some stats and metadata. 
The script supports 2 modes which can be specified with -m flag while running the script. One mode is stats mode which 
count of tables, rows, column, size per schema. Distribution of data by data type. Stats mode is the default mode. 
Another mode is full_metadata which will print complete information of all columns like their data type, constraints etc. 
The default port that Redshift uses is 5439.


### Pre-requisites

Install [psql](https://stackoverflow.com/questions/44654216/correct-way-to-install-psql-without-full-postgres-on-macos) on the machine.

From `sql_user_check_redshift` directory, run these commands depending on mode of script. You will be prompted for password 

Stats mode:
```shell
./database_stats.sh -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -d <DATABASE_NAME> -o <OUTPUT_FILE>  -P <PASSWORD>
```

Full metadata mode:
```shell
./database_stats.sh -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -d <DATABASE_NAME> -m full_metadata -o <OUTPUT_FILE> -P <PASSWORD>
```
