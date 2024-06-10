# Check permissions on SQL Server instance

### Pre-requisites

Install [sqlcmd](https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools) on the machine.

### Run the script

Specify the following options to run the script

* HOSTNAME: Hostname of the SQL server. Ex: `<IP of the instance>` or `<IP of the instance>,<port number>` 
            In case of Named instances, Host field would be <Hostname/IP of the machine>\<Instance name>.
            For example, if hostname is sqlserver.com and INST1 is the name of an instance that needs to be
            onboarded, then put sqlserver.com\INST1 as HOSTNAME
* USERNAME: Username to use for connecting to the instance.
* DATABASE_NAME: Name of the database to connect to the instance.
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


