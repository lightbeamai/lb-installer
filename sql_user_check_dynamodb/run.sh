#!/usr/bin/env bash


if ! command -v "aws" &> /dev/null
then
    echo "Command aws could not be found, please install it."
    exit 1
fi

aws configure

# Get list of regions
regions=(
    "us-east-1"
    "us-east-2"
    "us-west-1"
    "us-west-2"
    "af-south-1"
    "ap-east-1"
    "ap-south-1"
    "ap-northeast-1"
    "ap-northeast-2"
    "ap-northeast-3"
    "ap-southeast-1"
    "ap-southeast-2"
    "ca-central-1"
    "eu-central-1"
    "eu-west-1"
    "eu-west-2"
    "eu-west-3"
    "eu-north-1"
    "me-south-1"
    "sa-east-1"
)

# Loop through regions
for region in "${regions[@]}"; do
  total_records=0
  table_count=0
  tables=$(aws dynamodb list-tables --region "$region" --query "TableNames" --output text)
  for table in $tables; do
    table_count=$((table_count + 1))
    count=$(aws dynamodb scan --table-name "$table" --region "$region" --select "COUNT" --query "Count")
    total_records=$((total_records + count))
  done
  if [ $table_count -gt 0 ]; then
    echo "Total tables: $table_count, records: $total_records in region: $region"
  fi
done
