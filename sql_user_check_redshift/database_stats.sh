#!/bin/bash

set -e

port="5439"
mode="stats"

while getopts h:u:d:m:o:P:p flag
do
    case "${flag}" in
        h) dbhost=${OPTARG};;
        u) username=${OPTARG};;
        d) database=${OPTARG};;
        m) mode=${OPTARG};;
        o) outputfile=${OPTARG};;
        P) password=${OPTARG};;
        p) port=${OPTARG};;
    esac
done

export PGPASSWORD=$password

echo "dbhost: $dbhost username: $username database: $database port: $port mode: $mode outputfile: $outputfile";

# Check if psql command is available
if ! command -v psql &>/dev/null; then
    echo "psql is installed and available."
    exit 1
fi

if [ -z "$dbhost" ] || [ -z "$username" ] || [ -z "$database" ] || [ -z "$outputfile" ]; then
        echo 'Missing mandatory args: -h <DB_HOST>, -u <DB_USER>, -o <OUTPUT_FILE> or -d <DATABASE_NAME>' >&2
        exit 1
fi


if [ "$mode" == "stats" ]; then
  echo -e "\n\n===============Total tables, rows and size per schema============" > $outputfile
  psql -h $dbhost -U $username -f ./table_rows_size_per_schema.sql -p $port -d $database >> $outputfile

  echo -e "\n\n===============Data type distribution============" >> $outputfile
  psql -h $dbhost -U $username -f ./data_type_distribution.sql -p $port -d $database >> $outputfile

elif [ "$mode" == "full_metadata" ]; then
  echo -e "\n\n===============Complete metadata============" > $outputfile
  psql -h $dbhost -U $username -f ./complete_metadata.sql -p $port -d $database >> $outputfile

  echo -e "\n\n===============Referential Relations============" >> $outputfile
  psql -h $dbhost -U $username -f ./referential_relations.sql -p $port -d $database >> $outputfile

else
  echo "Mode should be either stats or full_metadata, found: $mode"
  exit 1
fi


