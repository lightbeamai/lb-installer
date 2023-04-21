#!/usr/bin/env bash

set -e

readonly CMD="snowsql"
readonly ACCOUNT=$ACCOUNT_NAME
readonly USERNAME=$SF_USERNAME
readonly DATABASE=$SF_DATABASE
readonly WAREHOUSE=$WAREHOUSE_NAME
readonly ROLE=$ROLE_NAME

if ! command -v "$CMD" &> /dev/null
then
    echo "Command $CMD could not be found, Follow https://docs.snowflake.com/en/user-guide/snowsql-install-config to install $CMD"
    exit 1
fi

tempQueryFile=$(mktemp)
sed "s/LB_DATABASE_NAME/$DATABASE/g" queries.sql > "$tempQueryFile"
snowsql -a "$ACCOUNT" --username "$USERNAME" -f "$tempQueryFile" -w "$WAREHOUSE" -r "$ROLE"
