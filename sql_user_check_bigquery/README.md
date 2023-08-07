# Check permissions for bigquery
### Pre-requisites

Install [bq](https://cloud.google.com/sdk/docs/install-sdk) on the machine.

Instructions to get service account json file [service account](https://docs.google.com/document/d/158OOKwQxv8bxotKwkuy5FLZ3or-0obYMwj0FKXUyrTw/edit#heading=h.hiriaxi7wof2)

Authenticate to bigquery using service accounts file and Project ID. Project ID is used to group the resources together 
for easier management e.g. dev, prod. It is comparable to an AWS sub account or AWS account. It can be obtained from 
top of google cloud console page. It looks something like this `essential-smoke-393811`.


``
gcloud auth activate-service-account  --key-file=<service-account.json file path> --project=<project id>
``

### Run the script from `sql_user_check_bigquery` directory

The script can be run by providing 0 or more DATASETIDS. If DATASETIDS are not provided, script
will fetch list of DATASETIDS in the given project and run queries for each of them. Multiple DATASETIDS
can also be provided as comma seperate list like DATASETIDS=a1,a2,a3

stats Mode:
```shell
MODE=stats DATASETIDS=<dataset id> OUTPUT=<output file path>  bash run.sh
```

full_metadata Mode:
```shell
MODE=full_metadata DATASETIDS=<dataset id> OUTPUT=<output file path>  bash run.sh
```
