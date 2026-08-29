#!/bin/bash

set -e

port="3306"
mode="stats"

while getopts h:u:m:o:p: flag
do
    case "${flag}" in
        h) dbhost=${OPTARG};;
        u) username=${OPTARG};;
        m) mode=${OPTARG};;
        o) outputfile=${OPTARG};;
        p) port=${OPTARG};;
    esac
done


echo "dbhost: $dbhost username: $username port: $port mode: $mode outputfile: $outputfile";

# Prefer the mariadb client; fall back to mysql if mariadb is not installed.
if command -v mariadb &>/dev/null; then
    DB_CLIENT="mariadb"
elif command -v mysql &>/dev/null; then
    DB_CLIENT="mysql"
else
    echo "Neither mariadb nor mysql client is installed or available."
    exit 1
fi

echo "Using client: $DB_CLIENT"

echo "Enter User's $username password"
read -s password

if [ -z "$dbhost" ] || [ -z "$username" ] || [ -z "$outputfile" ]; then
        echo 'Missing mandatory args: -h <DB_HOST>, -u <DB_USER> or -o <OUTPUT_FILE>' >&2
        exit 1
fi


if [ "$mode" == "stats" ]; then
  echo -e "\n\n===============Database list with size============" > $outputfile
  $DB_CLIENT -h $dbhost -u $username -p$password -P $port  < ./database_list_with_size.sql  >> $outputfile

  echo -e "\n\n===============Total tables, rows, columns and size per schema============" >> $outputfile
  $DB_CLIENT -h $dbhost -u $username -p$password -P $port  < ./tables_rows_columns_count.sql >> $outputfile

  echo -e "\n\n===============Data type distribution============" >> $outputfile
  $DB_CLIENT -h $dbhost -u $username -p$password -P $port  < ./data_type_distribution.sql >> $outputfile

elif [ "$mode" == "full_metadata" ]; then
  echo -e "\n\n===============Complete metadata============" > $outputfile
  $DB_CLIENT -h $dbhost -u $username -p$password -P $port < ./complete_metadata.sql >> $outputfile

  echo -e "\n\n===============Referential Relations============" >> $outputfile
  $DB_CLIENT -h $dbhost -u $username -p$password -P $port < ./referential_relations.sql >> $outputfile

else
  echo "Mode should be either stats or full_metadata, found: $mode"
  exit 1
fi
