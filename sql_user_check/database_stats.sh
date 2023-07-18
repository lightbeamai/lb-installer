#!/bin/bash
while getopts h:u:d:p: flag
do
    case "${flag}" in
        h) dbhost=${OPTARG};;
        u) username=${OPTARG};;
        d) database=${OPTARG};;
        p) port=${OPTARG};;
    esac
done
: ${port:="5432"}
echo "dbhost: $dbhost";
echo "username: $username";
echo "database: $database";
echo "port: $port";
if [ -z "$dbhost" ] || [ -z "$username" ] || [ -z "database" ]; then
        echo 'Missing mandatory args: -h <DB_HOST>, -u <DB_USER> or -d <DATABASE_NAME>' >&2
        exit 1
fi
echo -e "\n\n===============Database list with size============" > ~/test_database_stats.out
psql -h $dbhost -U $username -f ./database_list_with_size.sql -p $port -d $database >> ~/test_database_stats.out

echo -e "\n\n===============Total rows per schema============" >> ~/test_database_stats.out
psql -h $dbhost -U $username -f ./total_rows_per_schema.sql -p $port -d $database >> ~/test_database_stats.out

echo -e "\n\n===============Table rows count and size============" >> ~/test_database_stats.out
psql -h $dbhost -U $username -f ./table_rows_size.sql -p $port -d $database >> ~/test_database_stats.out

echo -e "\n\n===============Table columns count============" >> ~/test_database_stats.out
psql -h $dbhost -U $username -f ./table_columns.sql -p $port -d $database >> ~/test_database_stats.out

echo -e "\n\n===============Data type distribution============" >> ~/test_database_stats.out
psql -h $dbhost -U $username -f ./data_type_distribution.sql -p $port -d $database >> ~/test_database_stats.out
