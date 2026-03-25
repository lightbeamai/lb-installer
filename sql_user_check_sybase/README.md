# Check permissions on Sybase ASE instance

### Pre-requisites

Install [isql](https://infocenter.sybase.com/help/index.jsp?topic=/com.sybase.infocenter.dc36272.1572/html/commands/commands89.htm) (part of Sybase Open Client) on the machine.

### Run the script

Specify the following options to run the script

* HOSTNAME: Hostname or IP of the Sybase ASE server.
* PORT: Port number of the Sybase ASE server (default: 5000).
* USERNAME: Username to use for connecting to the instance.
* DATABASE_NAME: Name of the database to connect to.
* OUTPUT_FILE_PATH: Path to an output file to store the output of the script.
* Password: The script will prompt for password.

stats Mode:
```shell
./database_stats.sh -h <HOSTNAME> -p <PORT> -u <USERNAME> -d <DATABASE_NAME> -o <OUTPUT_FILE_PATH>
```

full_metadata Mode:
```shell
./database_stats.sh -h <HOSTNAME> -p <PORT> -u <USERNAME> -d <DATABASE_NAME> -o <OUTPUT_FILE_PATH> -m full_metadata
```
