# Deploy MYSQL and Import data from .sql file

The [setup_mysql.sh](./setup_mysql.sh) deploys a mysql instance using [specs](./base) and configurable storage class and storage size. The script can also import the data dump into a given database.

### Usage

```shell
bash setup_mysql.sh <ACTION> <STORAGE_CLASS TO USE> \
 <SIZE OF STORAGE TO PROVISION> <NAMESPACE TO DEPLOY MYSQL> \
 '<LOCAL_PATH_OF_DUMP_FILE>' \
 <DATABASE TO CREATE AND DUMP DATA> <MYSQL_PASSWORD> \
 <NAME OF MYSQL DEPLOYMENT TO CREATE>
```

Action can be `apply` to create the mysql instance or `delete` to destroy it.
For using different mysql version or customising the mysql configuration, you can modify image tag in  the [base/deployment.yaml](./base/deployment.yaml) file.