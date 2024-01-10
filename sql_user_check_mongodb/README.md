# Check user permissions for MongoDB


### Run the script

Running the script will print all the databases along with total number of collections and records inside them
Connection string is input to this script. If looks something like this 
mongodb://username:password@hostname:port/<database_name>?authSource=admin

```shell
connection_string="mongodb://<username>:<password>@<hostname>:<port>/<database_name>?authSource=admin
" bash run.sh```