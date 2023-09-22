# Check permissions on SQL Server instance

### Pre-requisites

Install [sqlcmd](https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools) on the machine.

### Run the script

Below command will ask password.

stats Mode:
```shell
./database_stats.sh -h <HOSTNAME> -u <USERNAME> -d <DATABASE_NAME> -o <OUTPUT_FILE_PATH> -p <PORT_NUMBER>
```

full_metadata Mode:
```shell
./database_stats.sh -h <HOSTNAME> -u <USERNAME> -d <DATABASE_NAME> -o <OUTPUT_FILE_PATH> -m full_metadata -p <PORT_NUMBER>
```
