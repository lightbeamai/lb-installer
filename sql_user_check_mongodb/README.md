# Check user permissions for MongoDB

### Pre-requisites

Install [mongosh](https://www.mongodb.com/docs/mongodb-shell/install/) on the machine.

### Run the script

The script prompts for mongo connection string, it looks something like this 
mongodb://username:password@hostname:port/<database_name>?authSource=admin. It then prompts for databases where comma 
separated list can be provided for which stats needs to be fetched. If nothing is provided, it defaults for all 
databases.
The script supports 2 modes, `stats` and `full_metadata`. It prompts for mode, default is stats.
Running the script in `stats` mode will print table and record count per database.
Running in `full_metadata` will print table names too along with above stats.


```shell 
bash run.sh
```