#!/bin/bash

port="5432"
mode="stats"

while getopts h:u:d:m:p flag
do
    case "${flag}" in
        h) dbhost=${OPTARG};;
        u) username=${OPTARG};;
        d) database=${OPTARG};;
        m) mode=${OPTARG};;
        p) port=${OPTARG};;
    esac
done


echo "dbhost: $dbhost";
echo "username: $username";
echo "database: $database";
echo "port: $port";
echo "mode: $mode";

if [ -z "$dbhost" ] || [ -z "$username" ] || [ -z "$database" ]; then
        echo 'Missing mandatory args: -h <DB_HOST>, -u <DB_USER> or -d <DATABASE_NAME>' >&2
        exit 1
fi


if [ "$mode" == "stats" ]; then
  echo -e "\n\n===============Database list with size============" > ~/test_database_stats.out
  psql -h $dbhost -U $username -f ./database_list_with_size.sql -p $port -d $database >> ~/test_database_stats.out

  echo -e "\n\n===============Total tables, rows, columns and size per schema============" >> ~/test_database_stats.out
  psql -h $dbhost -U $username -f ./tables_rows_columns_size_per_schema.sql -p $port -d $database >> ~/test_database_stats.out

  echo -e "\n\n===============Data type distribution============" >> ~/test_database_stats.out
  psql -h $dbhost -U $username -f ./data_type_distribution.sql -p $port -d $database >> ~/test_database_stats.out

elif [ "$mode" == "full_metadata" ]; then
  echo -e "\n\n===============Complete metadata============" > ~/test_database_stats.out
  psql -h $dbhost -U $username -f ./complete_metadata.sql -p $port -d $database >> ~/test_database_stats.out

  echo -e "\n\n===============Referential Relations============" >> ~/test_database_stats.out
  psql -h $dbhost -U $username -f ./referential_relations.sql -p $port -d $database >> ~/test_database_stats.out

else
  echo "Mode should be either stats or full_metadata"
  exit 1
fi


