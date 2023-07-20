# MYSQL User Check

database_stats.sh script can be used to test connectivity with MYSQL database as well as fetch some stats and metadata. 
The script supports 2 modes which can be specified with -m flag while running the script. One mode is stats mode which 
will just print info like list of databases with their size. Count of tables, rows, column, size per schema. 
Distribution of data by data type. Stats mode is the default mode. Another mode is full_metadata which will print 
complete information of all columns like their data type, constraints etc.

### Pre-requisites

1. Open or create the ~/.my.cnf file in your user's home directory.
2. Update the permissions `chmod 600 ~/.my.cnf`
3. Put your password there like this

```
[client] 
password=<your_password>
```


From `sql_user_check_mysql` directory, run these commands depending on mode of script. 

stats mode:
```shell
./database_stats.sh -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -o <OUTPUT_FILE>
```

full_metadata mode:
```shell
./database_stats.sh -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -m full_metadata -o <OUTPUT_FILE>
```
