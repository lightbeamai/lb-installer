# Deploy Postgres and Import data from backup

The [setup-postgres.sh](./setup-postgres.sh) deploys a postgres instance using [specs](./base) and configurable storage
class and storage size. The script can also download the backup file from AWS S3 or use local file and import the data dump into a given database.

### Usage

```shell
bash setup-postgres.sh <STORAGE_CLASS TO USE> \
 <SIZE OF STORAGE TO PROVISION> <NAMESPACE TO DEPLOY POSTGRES> \
 '<LOCAL_OR_S3_PATH>' \
 <DATABASE TO CREATE AND DUMP DATA> <PG_PASSWORD>
```

For S3 files the path format is `s3://<bucket>/<path>` and for local files it's POSIX style path.
We only support importing from `.gz` compressed files. These files must contain only one SQL file.