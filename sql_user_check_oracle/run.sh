#!/usr/bin/env bash

set -e

readonly CMD="sqlplus"
readonly ORACLE_USER=$ORACLE_USER
readonly ORACLE_PASSWORD=$ORACLE_PASSWORD
readonly ORACLE_HOST=$ORACLE_HOST
readonly ORACLE_PORT=$ORACLE_PORT
readonly ORACLE_SERVICE=$ORACLE_SERVICE

if ! command -v "$CMD" &> /dev/null
then
    echo "Command $CMD could not be found, Follow https://www.oracle.com/in/database/technologies/instant-client.html to install $CMD"
    exit 1
fi

SQL_QUERY="SELECT username FROM dba_users;"

EZCONNECT_STRING="${ORACLE_USER}/${ORACLE_PASSWORD}@${ORACLE_HOST}:${ORACLE_PORT}/${ORACLE_SERVICE}"

echo "Using EZConnect string: ${EZCONNECT_STRING}"

echo "$SQL_QUERY" | sqlplus -s "${EZCONNECT_STRING}"