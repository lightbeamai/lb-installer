#!/usr/bin/env bash

set -e

readonly CMD="snowsql"
readonly ACCOUNT=$ACCOUNT_NAME
readonly USERNAME=$SF_USERNAME
readonly DATABASE=$SF_DATABASE
readonly WAREHOUSE=$WAREHOUSE_NAME
readonly ROLE=$ROLE_NAME
readonly MODE=$MODE

if ! command -v "$CMD" &> /dev/null
then
    echo "Command $CMD could not be found, Follow https://docs.snowflake.com/en/user-guide/snowsql-install-config to install $CMD"
    exit 1
fi


if [ "$MODE" == "stats" ]; then
  tempQueryFile=$(mktemp)
  sed "s/LB_DATABASE_NAME/$DATABASE/g" stats_queries.sql > "$tempQueryFile"
  snowsql -a "$ACCOUNT" --username "$USERNAME" -f "$tempQueryFile" -w "$WAREHOUSE" -r "$ROLE"

elif [ "$MODE" == "full_metadata" ]; then
  tempQueryFile=$(mktemp)
  sed "s/LB_DATABASE_NAME/$DATABASE/g" queries.sql > "$tempQueryFile"
  snowsql -a "$ACCOUNT" --username "$USERNAME" -f "$tempQueryFile" -w "$WAREHOUSE" -r "$ROLE"

else
  echo "Mode should be either stats or full_metadata, found: $mode"
  exit 1
fi

