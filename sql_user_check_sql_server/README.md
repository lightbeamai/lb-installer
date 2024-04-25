# Check permissions on SQL Server instance

### Pre-requisites

Install [sqlcmd](https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools) on the machine.

### Run the script

Below command will ask password. If database name is not supplied, script will be executed for all databases in SQL Server.
One or multiple database names can be provided, in that case script will be executed only for them.
For trusting server certificate add -c 1. For Microsoft Entra/AD authentication add -a 1 

stats Mode:
```shell
./database_stats.sh -h <HOSTNAME> -u <USERNAME> -d <DATABASE_NAME> -o <OUTPUT_FILE_PATH> -p <PORT_NUMBER>
```

full_metadata Mode:
```shell
./database_stats.sh -h <HOSTNAME> -u <USERNAME> -d <DATABASE_NAME> -o <OUTPUT_FILE_PATH> -m full_metadata -p <PORT_NUMBER>
```


