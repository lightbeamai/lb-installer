#!/usr/bin/env bash

set -e

readonly MODE=$MODE
readonly DATASETID=$DATASETID
readonly OUTPUT=$OUTPUT


if ! command -v bq &> /dev/null
then
    echo "Command bq could not be found, Follow https://cloud.google.com/sdk/docs/install-sdk to install bq"
    exit 1
fi


if [ "$MODE" == "stats" ]; then
  tempQueryFile=$(mktemp)
  sed "s/db_name/$DATASETID/g" data_type_distribution.sql > "$tempQueryFile"
  bq query --use_legacy_sql=false  --format=prettyjson < "$tempQueryFile" > $OUTPUT

  tempQueryFile1=$(mktemp)
  sed "s/db_name/$DATASETID/g" tables_columns_count_per_datasetid.sql > "$tempQueryFile1"
  bq query --use_legacy_sql=false  --format=prettyjson < "$tempQueryFile1" >> $OUTPUT

elif [ "$MODE" == "full_metadata" ]; then
  tempQueryFile=$(mktemp)
  sed "s/db_name/$DATASETID/g" queries.sql > "$tempQueryFile"
  bq query --use_legacy_sql=false  --format=prettyjson < "$tempQueryFile" > $OUTPUT

else
  echo "Mode should be either stats or full_metadata, found: $MODE"
  exit 1
fi

