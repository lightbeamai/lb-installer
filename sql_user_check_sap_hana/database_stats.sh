#!/bin/bash

set -e

port="443"
mode="stats"

while getopts h:u:m:o:p:s: flag
do
    case "${flag}" in
        h) host=${OPTARG};;
        u) username=${OPTARG};;
        m) mode=${OPTARG};;
        o) outputfile=${OPTARG};;
        s) schema=${OPTARG};;
        p) port=${OPTARG};;
    esac
done

echo "host: $host username: $username mode: $mode outputfile: $outputfile port: $port schema: $schema";

# Check if hdbsql command is available
if ! command -v hdbsql q; then
    echo "hdbsql is not installed or available."
    exit 1
fi

echo "Enter User's $username password"
read -s password

if [ -z "$host" ] || [ -z "$username" ] || [ -z "$outputfile" ]; then
        echo 'Missing mandatory args: -h <HOST>, -u <USER> or -o <OUTPUT_FILE>' >&2
        exit 1
fi

if [ "$mode" == "stats" ]; then
  echo -e "\n\n===============Database list with size============" > $outputfile
  hdbsql -n "$host:$port" -u $username -p $password -I ./database_list_with_size.sql  >> $outputfile

  echo -e "\n\n===============Total tables, columns and size per schema============" >> $outputfile
  hdbsql -n "$host:$port" -u $username -p $password -I ./tables_rows_columns_count.sql >> $outputfile

  echo -e "\n\n===============Data type distribution============" >> $outputfile
  hdbsql -n "$host:$port" -u $username -p $password -I ./data_type_distribution.sql >> $outputfile

elif [ "$mode" == "full_metadata" ]; then
  if [ -z "$schema" ]; then
    echo 'Missing mandatory args: -s <SCHEMA>' >&2
    exit 1
  fi
  echo -e "\n\n===============Complete metadata============" > $outputfile
#  edit complete_metadata.sql to replace DATABASE_NAME with schema and store in temp_metadata.sql
  sed "s/DATABASE_NAME/$schema/g" ./complete_metadata.sql > ./temp_metadata.sql
  hdbsql -n "$host:$port" -u $username -p $password -I ./temp_metadata.sql >> $outputfile

else
  echo "Mode should be either stats or full_metadata, found: $mode"
  exit 1
fi

