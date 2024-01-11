#!/usr/bin/env bash


if ! command -v "aws" &> /dev/null
then
    echo "Command aws could not be found, Follow https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html to install aws"
    exit 1
fi

get_table_info() {
    local region=$1
    local mode=$2

    total_records=0
    table_count=0
    tables=$(aws dynamodb list-tables --region "$region" --query "TableNames" --output text)

    for table in $tables; do
        table_count=$((table_count + 1))
        count=$(aws dynamodb scan --table-name "$table" --region "$region" --select "COUNT" --query "Count")
        total_records=$((total_records + count))

        if [ "$mode" == "full_metadata" ]; then
            echo "  Table Name: $table, Records: $count"
        fi
    done

    if [ "$mode" == "stats" ] && [ $table_count -gt 0 ]; then
        echo "Total tables: $table_count, records: $total_records in region: $region"
    fi
}

read -p "AWS Access Key ID: " aws_access_key_id
read -p "AWS Secret Access Key: " aws_secret_access_key
read -p "Default region name: " aws_default_region

export AWS_ACCESS_KEY_ID="$aws_access_key_id"
export AWS_SECRET_ACCESS_KEY="$aws_secret_access_key"
export AWS_DEFAULT_REGION="$aws_default_region"

read -p "Enter regions to include (comma-separated, press Enter for all): " selected_regions_input

IFS=',' read -ra selected_regions <<< "${selected_regions_input:-us-east-1,us-east-2,us-west-1,us-west-2,af-south-1,ap-east-1,ap-south-1,ap-northeast-1,ap-northeast-2,ap-northeast-3,ap-southeast-1,ap-southeast-2,ca-central-1,eu-central-1,eu-west-1,eu-west-2,eu-west-3,eu-north-1,me-south-1,sa-east-1}"

read -p "Enter mode (stats or full_metadata, press Enter for stats): " mode
mode=${mode:-stats}

for region in "${selected_regions[@]}"; do
    echo "Region: $region"

    if [ "$mode" == "full_metadata" ]; then
        get_table_info "$region" "$mode"
    else
        get_table_info "$region" "$mode"
    fi
done

unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_DEFAULT_REGION