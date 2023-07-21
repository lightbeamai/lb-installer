# Check permissions on Snowflake instance

### Pre-requisites

Install [snowsql](https://docs.snowflake.com/en/user-guide/snowsql-install-config) on the machine.

### Run the script

The script supports 2 modes, `stats` and `full_metadata`. Running the script in `stats` mode
will print tables, columns, rows count per schema, data type distribution, schema size. 
Running in `full_metadata` will print a lot of details related to tables and columns.

```shell
WAREHOUSE_NAME=<WAREHOUSE NAME> ACCOUNT_NAME=<SNOWFLAKE ACCOUNT NAME> ROLE_NAME=<ROLE ASSIGNED TO USER> SF_USERNAME=<USERNAME> MODE=<stats> SF_DATABASE=<DATABASE TO CONNECT> bash run.sh
```
