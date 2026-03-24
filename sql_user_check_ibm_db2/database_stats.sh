#!/bin/bash

set -e

port="50000"
mode="stats"

while getopts d:h:u:m:o:p: flag
do
    case "${flag}" in
        d) database=${OPTARG};;
        h) host=${OPTARG};;
        u) username=${OPTARG};;
        m) mode=${OPTARG};;
        o) outputfile=${OPTARG};;
        p) port=${OPTARG};;
    esac
done

run_query_to_csv() {
  local sql_file=$1
  local outputfile=$2

  if [ ! -f "$sql_file" ]; then
    echo "SQL file $sql_file does not exist."
    exit 1
  fi

  local conn="DATABASE=$database;HOSTNAME=$host;PORT=$port;PROTOCOL=TCPIP;UID=$username;PWD=$password"

  db2cli execsql -connstring "$conn" -inputsql "$sql_file" -statementdelimiter ";" 2>&1 |
  awk '/^FetchAll:/ { inData=1; next } inData && /^[[:space:]]+[A-Za-z0-9_]/' >> "$outputfile"
}


echo "host: $host username: $username mode: $mode outputfile: $outputfile port: $port database: $database";

# Check if db2cli command is available
if ! command -v db2cli q; then
    echo "db2cli is not installed or available."
    exit 1
fi

echo "Enter User's $username password"
read -s password

if [ -z "$host" ] || [ -z "$username" ] || [ -z "$outputfile" ]; then
        echo 'Missing mandatory args: -h <HOST>, -u <USER> or -o <OUTPUT_FILE>' >&2
        exit 1
fi

if [ "$mode" == "stats" ]; then

  echo -e "\n\n===============Database size============" > "$outputfile"
  run_query_to_csv "./database_size.sql" "$outputfile"

  echo -e "\n\n===============Total tables, columns and size per schema============" >> "$outputfile"
  run_query_to_csv "./tables_rows_columns_count.sql" "$outputfile"

  echo -e "\n\n===============Data type distribution============" >> "$outputfile"
  run_query_to_csv "./data_type_distribution.sql" "$outputfile"

elif [ "$mode" == "full_metadata" ]; then
  echo -e "\n\n===============Complete metadata============" > "$outputfile"
  run_query_to_csv "./complete_metadata.sql" "$outputfile"

else
  echo "Mode should be either stats or full_metadata, found: $mode"
  exit 1
fi

