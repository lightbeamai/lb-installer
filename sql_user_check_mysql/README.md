# MySQL User Check

database_stats.sh script can be used to test connectivity with MySQL database as well as fetch some stats and metadata. 
The script supports 2 modes which can be specified with -m flag while running the script. One mode is stats mode which 
will just print info like list of databases with their size. Count of tables, rows, column, size per schema. 
Distribution of data by data type. Stats mode is the default mode. Another mode is full_metadata which will print 
complete information of all columns like their data type, constraints etc. MySQL uses 3306 as default port.

### Pre-requisites

Install [mysql](https://stackoverflow.com/questions/30990488/how-do-i-install-command-line-mysql-client-on-mac) on the machine.

From `sql_user_check_mysql` directory, run these commands depending on mode of script. You will be prompted for password.

Stats mode:
```shell
./database_stats.sh -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -o <OUTPUT_FILE> -P <PASSWORD>
```

Full metadata mode:
```shell
./database_stats.sh -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -m full_metadata -o <OUTPUT_FILE> -P <PASSWORD>
```