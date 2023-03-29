# Check permissions on SQL Server instance

### Pre-requisites

Install [sqlcmd](https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools) on the machine.

### Run the script

```shell
SERVER='<HOSTNAME>,<PORT_NUMBER>' SS_USERNAME=<USERNAME> SS_DATABASE=<DATABASE TO CONNECT> bash run.sh
```

This will produce an output file called `lb_ss_output.txt`. Check the content of the file to see whether there are any errors.
