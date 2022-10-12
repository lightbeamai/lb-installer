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
echo -e "\n\n===============Fetch Schema List============" > ~/test_user.out
psql -h $dbhost -U $username -f ./schema_list.sql -p $port -d $database >> ~/test_user.out

echo -e "\n\n==============Fetch All Relations List=========" >> ~/test_user.out
psql -h $dbhost -U $username -f ./fetch_all_relations.sql -p $port -d $database >> ~/test_user.out

echo -e "\n\n==============Fetch all_tables_columns List============" >> ~/test_user.out
psql -h $dbhost -U $username -f ./all_tables_columns.sql -p $port -d $database >> ~/test_user.out


