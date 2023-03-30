#!/usr/bin/env bash

set -euxo

readonly SQLCMD="sqlcmd"
readonly SERVER=$SERVER
readonly USERNAME=$SS_USERNAME
readonly DATABASE=$SS_DATABASE

if ! command -v "$SQLCMD" &> /dev/null
then
    echo "Command $SQLCMD could not be found, Follow https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools to install sqlcmd"
    exit 1
fi

$SQLCMD -S "$SERVER" -e -U "$USERNAME" -i queries.sql -o lb_ss_output.txt -d "$DATABASE"
