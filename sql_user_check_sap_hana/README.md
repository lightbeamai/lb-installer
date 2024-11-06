Please run each of the .sql files on that database with the account credentials that you need to connect to LightBeam.

Prerequisites:
- Install [hdbsql](https://tools.hana.ondemand.com/#hanatools) on the machine.[Instruction](https://developers.sap.com/tutorials/hana-clients-install..html)

Fetch Schema List:
```shell
hdbsql -n <DATABASE_HOST_IP>:<PORT> -u <DATABASE_USER> -p <PASSWORD> -d <DATABASE_NAME> "SELECT SCHEMA_NAME FROM SCHEMAS" > schema_list
```

# HDBSQL User Check

database_stats.sh script can be used to test connectivity with SAP HANA database as well as fetch some stats and metadata. 
The script supports 2 modes which can be specified with -m flag while running the script. One mode is stats mode which 
will just print info like list of schemas with their size. Count of tables, rows, column, size per schema. 
Distribution of data by data type. Stats mode is the default mode. Another mode is full_metadata which will print 
complete information of all columns like their data type, constraints etc. hdbsql uses 443 as default port.

From `sql_user_check_sap_hana` directory, run these commands depending on mode of script. You will be prompted for password.

Stats mode:
```shell
./database_stats.sh -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -o <OUTPUT_FILE> -p <PORT_NUMBER>
```

Full metadata mode:
```shell
./database_stats.sh -u <DATABASE_USER> -h <DATABASE_HOSTNAME> -m full_metadata -o <OUTPUT_FILE> -p <PORT_NUMBER>
```