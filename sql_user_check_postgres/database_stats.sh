#!/bin/bash

port="5432"
mode="stats"

while getopts h:u:d:m:o:p flag
do
    case "${flag}" in
        h) dbhost=${OPTARG};;
        u) username=${OPTARG};;
        d) database=${OPTARG};;
        m) mode=${OPTARG};;
        o) outputfile=${OPTARG};;
        p) port=${OPTARG};;
    esac
done


echo "dbhost: $dbhost";
echo "username: $username";
echo "database: $database";
echo "port: $port";
echo "mode: $mode";
echo "outputfile: $outputfile";

# Check if psql command is available
if command -v psql &>/dev/null; then
    echo "psql is installed and available."
else
    echo "psql is NOT installed or not in the system's PATH."
fi

if [ -z "$dbhost" ] || [ -z "$username" ] || [ -z "$database" ] || [ -z "$outputfile" ]; then
        echo 'Missing mandatory args: -h <DB_HOST>, -u <DB_USER>, -o <OUTPUT_FILE> or -d <DATABASE_NAME>' >&2
        exit 1
fi


if [ "$mode" == "stats" ]; then
  echo -e "\n\n===============Database list with size============" > $outputfile
  psql -h $dbhost -U $username -f ./database_list_with_size.sql -p $port -d $database >> $outputfile

  echo -e "\n\n===============Total tables, rows, columns and size per schema============" >> $outputfile
  psql -h $dbhost -U $username -f ./tables_rows_columns_size_per_schema.sql -p $port -d $database >> $outputfile

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


