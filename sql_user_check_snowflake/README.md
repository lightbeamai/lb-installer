# Check permissions on Snowflake instance

### Pre-requisites

Install [snowsql](https://docs.snowflake.com/en/user-guide/snowsql-install-config) on the machine.

### Run the script

```shell
WAREHOUSE_NAME=<WAREHOUSE NAME> ACCOUNT_NAME=<SNOWFLAKE ACCOUNT NAME> ROLE_NAME=<ROLE ASSIGNED TO USER> SF_USERNAME=<USERNAME> SF_DATABASE=<DATABASE TO CONNECT> bash run.sh
```
