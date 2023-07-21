#!/bin/bash

mode="stats"
port="1433"


while getopts h:u:d:o:m:p flag
do
    case "${flag}" in
        h) dbhost=${OPTARG};;
        u) username=${OPTARG};;
        d) database=${OPTARG};;
        o) outputfile=${OPTARG};;
        m) mode=${OPTARG};;
        p) port=${OPTARG};;
    esac
done


echo "dbhost: $dbhost";
echo "username: $username";
echo "database: $database";
echo "mode: $mode";
echo "outputfile: $outputfile";
echo "port: $port";


# Check if psql command is available
if command -v sqlcmd &>/dev/null; then
    echo "sqlcmd is installed and available."
else
    echo "sqlcmd is NOT installed or not in the system's PATH. \
    Follow https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools to install sqlcmd"
fi

if [ -z "$dbhost" ] || [ -z "$username" ] || [ -z "$database" ] || [ -z "$outputfile" ]; then
        echo 'Missing mandatory args: -h <DB_HOST>, -u <DB_USER>, -o <OUTPUT_FILE> or -d <DATABASE_NAME>' >&2
        exit 1
fi


if [ "$mode" == "stats" ]; then
  sqlcmd -S $dbhost -U $username -i ./database_list_with_size.sql -i ./data_type_distribution.sql -i ./other_stats.sql\
  -d $database -o $outputfile

elif [ "$mode" == "full_metadata" ]; then
  sqlcmd -S $dbhost -U $username -i ./queries.sql -d $database -o $outputfile

else
  echo "Mode should be either stats or full_metadata, found: $mode"
  exit 1
fi


