# check user permissions for IBM DB2 

### Prerequisites:
Install [ibm_db2 cli](https://github.com/ibmdb/db2drivers/tree/main/clidriver) on the machine.

Validate database
```shell
db2cli validate -database "<DATABASE_NAME>:<HOST>:<PORT>" -connect -user <USERNAME> -passwd <PASSWORD>
```

# DB2CLI User Permision Check
database_stats.sh script can be used to test connectivity with DB@ database as well as fetch some stats and metadata. 
The script supports 2 modes which can be specified with -m flag while running the script. One mode is stats mode which 
will just print info like list of schemas with their size. Count of tables, rows, column, size per schema. 
Distribution of data by data type. Stats mode is the default mode. Another mode is full_metadata which will print 
complete information of all columns like their data type, constraints etc. db2cli uses 50000 as default port.

From `sql_user_check_ibm_db2` directory, run these commands depending on mode of script. You will be prompted for password.

Stats mode:
```shell
./database_stats.sh -d <DATABASE_NAME> -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -o <OUTPUT_FILE> -p <PORT_NUMBER>

```

Full metadata mode:
```shell
./database_stats.sh -d <DATABASE_NAME> -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -m full_metadata -o <OUTPUT_FILE> -p <PORT_NUMBER>
```
