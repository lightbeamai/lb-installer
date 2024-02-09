#!/usr/bin/env bash


if ! command -v "aws" &> /dev/null
then
    echo "Command aws could not be found, Follow https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html to install aws CLI"
    exit 1
fi


read -p "AWS Access Key ID: " aws_access_key_id
read -p "AWS Secret Access Key: " aws_secret_access_key
read -p "Default region name: " aws_default_region

export AWS_ACCESS_KEY_ID="$aws_access_key_id"
export AWS_SECRET_ACCESS_KEY="$aws_secret_access_key"
export AWS_DEFAULT_REGION="$aws_default_region"

echo "Checking Glue permissions..."
databases=$(aws glue get-databases --query 'DatabaseList[*].Name' --output text)

for database in $databases; do
    table_count=$(aws glue get-tables --database-name "$database" --query 'TableList | length(@)')
    echo "Database: $database, Table Count: $table_count"
done

echo "Checking Athena permissions..."
read -p "Athena workgroup name: " athena_workgroup_name
output_location=$(aws athena get-work-group --work-group "$athena_workgroup_name" --query 'WorkGroup.Configuration.ResultConfiguration.OutputLocation' --output text)

echo "Output Location for Workgroup $athena_workgroup_name: $output_location"

# Following query doesn't scan any data. So, no cost incurred and no result files are created.
QUERY="SHOW DATABASES;"
query_execution_id=$(aws athena start-query-execution --query-string "$QUERY" --work-group "$athena_workgroup_name" --query 'QueryExecutionId' --output text)

while true; do
    query_execution_status=$(aws athena get-query-execution --query-execution-id "$query_execution_id" --query 'QueryExecution.Status.State' --output text)
    if [[ "$query_execution_status" == "SUCCEEDED" ]]; then
        break
    elif [[ "$query_execution_status" == "FAILED" || "$query_execution_status" == "CANCELLED" ]]; then
        echo "Query execution failed or was cancelled."
        exit 1
    fi
    sleep 1
done

results=$(aws athena get-query-results --query-execution-id "$query_execution_id")
echo "$results"

unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_DEFAULT_REGION