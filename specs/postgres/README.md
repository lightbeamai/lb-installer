# Deploy Postgres and Import data from backup

The [setup-postgres.sh](./setup-postgres.sh) deploys a postgres instance using [specs](./base) and configurable storage
class and storage size. The script can also download the backup file from AWS S3 or use local file and import the data dump into a given database.

### Usage

```shell
bash setup-postgres.sh <ACTION> <STORAGE_CLASS TO USE> \
 <SIZE OF STORAGE TO PROVISION> <NAMESPACE TO DEPLOY POSTGRES> \
 '<LOCAL_OR_S3_PATH>' \
 <DATABASE TO CREATE AND DUMP DATA> <PG_PASSWORD> \
 <NAME OF POSTGRES DEPLOYMENT TO CREATE>
```

To create the postgres provide `ACTION=apply`, to destroy supply `ACTION=delete`.
For S3 files the path format is `s3://<bucket>/<path>` and for local files it's POSIX style path.
We only support importing from `.gz` compressed files. These files must contain only one SQL file.

### Customising Postgres configuration

Any postgres configuration described in the [docs](https://www.postgresql.org/docs/14/runtime-config.html) can be provided in the deployment's args to configure deployed postgres.

Ex: To customise [maximum runtime of a query](https://postgresqlco.nf/doc/en/param/statement_timeout/) we can put following change into [deployment](base/deployment.yaml).

```shell
+++ b/specs/postgres/base/deployment.yaml
@@ -23,6 +23,7 @@ spec:
       - name: lb-postgres
         image: postgres:11-bullseye
         imagePullPolicy: "IfNotPresent"
+        args: ["-c", statement_timeout=90000]
         ports:
         - containerPort: 5432
           name: lb-postgres
@@ -47,9 +48,17 @@ spec:
```
