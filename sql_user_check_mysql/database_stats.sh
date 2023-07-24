#!/bin/bash

set -e

port="3306"
mode="stats"

while getopts h:u:m:o:P:p flag
do
    case "${flag}" in
        h) dbhost=${OPTARG};;
        u) username=${OPTARG};;
        m) mode=${OPTARG};;
        o) outputfile=${OPTARG};;
        P) password=${OPTARG};;
        p) port=${OPTARG};;
    esac
done


echo "dbhost: $dbhost username: $username port: $port mode: $mode outputfile: $outputfile";

# Check if mysql command is available
if ! command -v mysql &>/dev/null; then
    echo "mysql is NOT installed or available."
    exit 1
fi

if [ -z "$dbhost" ] || [ -z "$username" ] || [ -z "$outputfile" ] || [ -z "$password" ]; then
        echo 'Missing mandatory args: -h <DB_HOST>, -u <DB_USER>, -P <password> or -o <OUTPUT_FILE>' >&2
        exit 1
fi


if [ "$mode" == "stats" ]; then
  echo -e "\n\n===============Database list with size============" > $outputfile
  mysql -h $dbhost -u $username -p$password -P $port  < ./database_list_with_size.sql  >> $outputfile

  echo -e "\n\n===============Total tables, rows, columns and size per schema============" >> $outputfile
  mysql -h $dbhost -u $username -p$password -P $port  < ./tables_rows_columns_count.sql >> $outputfile

  echo -e "\n\n===============Data type distribution============" >> $outputfile
  mysql -h $dbhost -u $username -p$password -P $port  < ./data_type_distribution.sql >> $outputfile

elif [ "$mode" == "full_metadata" ]; then
  echo -e "\n\n===============Complete metadata============" > $outputfile
  mysql -h $dbhost -u $username -p$password -P $port < ./complete_metadata.sql >> $outputfile

  echo -e "\n\n===============Referential Relations============" >> $outputfile
  mysql -h $dbhost -u $username -p$password -P $port < ./referential_relations.sql >> $outputfile

else
  echo "Mode should be either stats or full_metadata, found: $mode"
  exit 1
fi


