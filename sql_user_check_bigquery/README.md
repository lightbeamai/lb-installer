# Check permissions for bigquery
### Pre-requisites

Install [bq](https://cloud.google.com/sdk/docs/install-sdk) on the machine.

Instruction to get service account json file [service account](https://docs.google.com/document/d/158OOKwQxv8bxotKwkuy5FLZ3or-0obYMwj0FKXUyrTw/edit#heading=h.hiriaxi7wof2)

Authenticate to bigquery 

``
gcloud auth activate-service-account  --key-file=<service-account.json file path> --project=<project id>
``

### Run the script (from sql_user_check_bigquery directory)

stats Mode:
```shell
MODE=stats DATASETID=<dataset id> OUTPUT=<output file path>  bash run.sh
```

full_metadata Mode:
```shell
MODE=full_metadata DATASETID=<dataset id> OUTPUT=<output file path>  bash run.sh
```
