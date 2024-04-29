# Check permissions on SQL Server instance

### Pre-requisites

Install [sqlcmd](https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools) on the machine.

### Run the script

Specify the following options to run the script

* HOSTNAME: Hostname of the SQL server. Ex: `<IP of the instance>` or `<IP of the instance>,<port number>`
* USERNAME: Username to use for connecting to the instance.
DATABASE_NAME: Name of the database to connect to the instance.
* OUTPUT_FILE_PATH: Path to an output file to store the output of the script to fetch metadata and stats.
* Trust server certificate: To trust the server certificate using sqlcmd provide `-c 1` as an argument to the script.
* Using Entra ID authentication: To use Azure AD or Entra ID authentication provide `-a 1`
* Password: The script will prompt for password

stats Mode:
```shell
./database_stats.sh -h <HOSTNAME> -u <USERNAME> -d <DATABASE_NAME> -o <OUTPUT_FILE_PATH>
```

full_metadata Mode:
```shell
./database_stats.sh -h <HOSTNAME> -u <USERNAME> -d <DATABASE_NAME> -o <OUTPUT_FILE_PATH> -m full_metadata
```


