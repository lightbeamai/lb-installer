#!/usr/bin/env bash

set -e

readonly MODE=$MODE
readonly DATASETIDS=$DATASETIDS
readonly OUTPUT=$OUTPUT


if ! command -v bq &> /dev/null
then
    echo "Command bq could not be found, Follow https://cloud.google.com/sdk/docs/install-sdk to install bq"
    exit 1
fi

declare -a dataset_list

if [[ -z "$DATASETIDS" ]]; then
  echo "DATASETID not provided, the script will be executed for all dataset ids in the project"
  # Skip the first two lines and get the dataset names
  dataset_names=$(echo "$(bq ls)" | tail -n +3)

  # Loop over the dataset names and add them to the array
  while IFS= read -r dataset; do
    read -r trimmed_string <<< "$dataset"
    dataset_list+=("$trimmed_string")
  done <<< "$dataset_names"
else
  # Set the IFS to ',' (comma) to specify the delimiter
  IFS=','
  read -ra dataset_list <<< "$DATASETIDS"
fi

if [ "$MODE" == "stats" ]; then
  echo -e "\n" > $OUTPUT
  for datasetID in "${dataset_list[@]}"; do
    echo -e "\n\n===============Results for DatasetID $datasetID============" >> $OUTPUT
    tempQueryFile=$(mktemp)
    sed "s/db_name/$datasetID/g" data_type_distribution.sql > "$tempQueryFile"
    bq query --use_legacy_sql=false  --format=prettyjson < "$tempQueryFile" >> $OUTPUT

    tempQueryFile1=$(mktemp)
    sed "s/db_name/$datasetID/g" tables_columns_count_per_datasetid.sql > "$tempQueryFile1"
    bq query --use_legacy_sql=false  --format=prettyjson < "$tempQueryFile1" >> $OUTPUT
  done
elif [ "$MODE" == "full_metadata" ]; then
  echo -e "\n" > $OUTPUT
  for datasetID in "${dataset_list[@]}"; do
    echo -e "\n\n===============Results for DatasetID $datasetID============" >> $OUTPUT
    tempQueryFile=$(mktemp)
    sed "s/db_name/$datasetID/g" queries.sql > "$tempQueryFile"
    bq query --use_legacy_sql=false  --format=prettyjson < "$tempQueryFile" >> $OUTPUT
  done
else
  echo "Mode should be either stats or full_metadata, found: $MODE"
  exit 1
fi

