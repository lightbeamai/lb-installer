#!/bin/bash

mode="stats"
port=5000

set -e

while getopts h:u:d:o:m:p: flag
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

echo "dbhost: $dbhost username: $username database: $database mode: $mode outputfile: $outputfile port: $port";

# Check if isql command is available
if ! command -v isql &>/dev/null; then
    echo "isql is not installed and available. Install Sybase Open Client to get the isql utility."
    exit 1
fi

if [ -z "$dbhost" ] || [ -z "$username" ] || [ -z "$database" ] || [ -z "$outputfile" ]; then
        echo 'Missing mandatory args: -h <DB_HOST>, -u <DB_USER>, -o <OUTPUT_FILE> or -d <DATABASE_NAME>' >&2
        exit 1
fi

read -sp "Password: " password
echo

if [ "$mode" == "stats" ]; then
  isql -S $dbhost -U $username -P $password -D $database -w 999 \
    -i ./database_list_with_size.sql -i ./data_type_distribution.sql -i ./other_stats.sql \
    -o $outputfile

elif [ "$mode" == "full_metadata" ]; then
  isql -S $dbhost -U $username -P $password -D $database -w 999 \
    -i ./queries.sql -o $outputfile

else
  echo "Mode should be either stats or full_metadata, found: $mode"
  exit 1
fi
