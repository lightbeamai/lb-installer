#!/bin/bash

readonly connection_string=$connection_string

if ! command -v "mongo" &> /dev/null
then
    echo "Command mongo could not be found, Follow https://stackoverflow.com/questions/58504865/install-mongo-shell-in-mac to install mongo"
    exit 1
fi

# Get list of databases excluding admin, config, and local
databases=$(mongo --quiet  --eval "db.adminCommand('listDatabases').databases.map(db => db.name).filter(db => !['admin',
'config', 'local'].includes(db)).forEach(function(db){print(db)})" "$connection_string")

for db in $databases
do
    echo "Database: $db"

    conn_string=$(echo "$connection_string" | sed 's#^\(.*\/[^/]*\/\)[^?]*\(\?.*\)#\1'"$db"'\2#')
    echo "$conn_string"
    # Get collections in the current database
    collections=$(mongo --quiet --eval "db.getCollectionNames().join('\n')" "$conn_string")
    collection_count=$(echo "$collections" | wc -l | xargs)
    echo "  Number of Collections: $collection_count"

     # Get database stats to retrieve total document count
    total_records=$(mongo --quiet --eval "db.stats().objects" "$conn_string")
    echo "Total Records in $db: $total_records"
done