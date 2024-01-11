#!/usr/bin/env bash


read -p "MongoDB connection string: " connection_string

if ! command -v "mongosh" &> /dev/null
then
    echo "Command mongosh could not be found, Follow https://www.mongodb.com/docs/mongodb-shell/install/ to install mongosh"
    exit 1
fi

read -p "Enter a comma-separated list of databases (press Enter for all): " user_databases_input
IFS=',' read -ra user_databases <<< "$user_databases_input"

# If the user provided databases, use them; otherwise, fetch all databases
if [ "${#user_databases[@]}" -eq 0 ]; then
    # Get list of databases excluding admin, config, and local
    databases=$(mongosh --quiet  --eval "db.adminCommand('listDatabases').databases.map(db => db.name).filter(db => !['admin', 'config', 'local'].includes(db)).forEach(function(db){print(db)})" "$connection_string")
else
    databases=("${user_databases[@]}")
fi

read -p "Enter mode (stats or full_metadata, press Enter for stats): " mode
mode=${mode:-stats}

for db in "${databases[@]}"
do
    echo "Database: $db"

    conn_string=$(echo "$connection_string" | sed 's#^\(.*\/[^/]*\/\)[^?]*\(\?.*\)#\1'"$db"'\2#')
    # Get collections in the current database
    collections=$(mongosh --quiet --eval "db.getCollectionNames().join('\n')" "$conn_string")
    collection_count=$(echo "$collections" | wc -l | xargs)

    if [ "$mode" == "full_metadata" ]; then
        echo "  Number of Collections: $collection_count"
        echo "  Collections:"
        echo "$collections"
    fi

    # Get database stats to retrieve total document count
    total_records=$(mongosh --quiet --eval "db.stats().objects" "$conn_string")
    echo "Total Records in $db: $total_records"
done