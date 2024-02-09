# Check user permissions for Glue

### Pre-requisites

Install [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) on the machine.

### Run the script
The script verifies user permissions for Glue and Athena services. 
It prompts for AWS access key, AWS secret key and region. 
First part is Glue permission check. All databases with their table count are printed.
Second part is Athena permission check. Script prompts for workgroup name. It then prints default output query result S3 location.
It then executes 
```sql
SHOW databases;
```
 SQL query and prints the result. The query doesn't scan any data, so no cost is incurred and no result files are created.


```shell 
bash run.sh
```