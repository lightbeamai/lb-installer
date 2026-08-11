#!/bin/bash

mode="stats"
use_ad_auth=0
trust_server_cert=0
port=""

set -e

while getopts h:u:d:o:m:p:a:t: flag
do
    case "${flag}" in
        h) dbhost=${OPTARG};;
        u) username=${OPTARG};;
        d) database=${OPTARG};;
        o) outputfile=${OPTARG};;
        m) mode=${OPTARG};;
        p) port=${OPTARG};;
        a) use_ad_auth=${OPTARG};;
        t) trust_server_cert=${OPTARG};;
    esac
done


echo "dbhost: $dbhost username: $username database: $database mode: $mode outputfile: $outputfile port: $port AD Auth: $use_ad_auth Trust Server Cert: $trust_server_cert";

# Check if sqlcmd command is available
if ! command -v sqlcmd &>/dev/null; then
    echo "sqlcmd is not installed and available. Follow https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools to install sqlcmd"
    exit 1
fi

if [ -z "$dbhost" ] || [ -z "$username" ] || [ -z "$database" ] || [ -z "$outputfile" ]; then
        echo 'Missing mandatory args: -h <DB_HOST>, -u <DB_USER>, -o <OUTPUT_FILE> or -d <DATABASE_NAME>' >&2
        exit 1
fi

# Append the port to the server address if one was supplied.
server="$dbhost"
if [ -n "$port" ]; then
    server="$dbhost,$port"
fi

# Read the password without letting the shell mangle it.
#   -r : do not treat backslashes as escape characters (a password such as
#        'Pa55\word' would otherwise lose its backslash)
#   -s : do not echo the password to the terminal
# The password is handed to sqlcmd through the SQLCMDPASSWORD environment
# variable rather than the -P flag, so it never passes through argv and no
# shell quoting/escaping is applied to it.
if [ -z "${SQLCMDPASSWORD:-}" ]; then
    read -r -s -p "Password: " SQLCMDPASSWORD || true
    echo
fi
export SQLCMDPASSWORD

auth_flag=()
if [ "$use_ad_auth" -eq 1 ]; then
    auth_flag=("-G")  # Use AD authentication
fi

trust_cert_flag=()
if [ "$trust_server_cert" -eq 1 ]; then
    trust_cert_flag=("-C")  # Trust server certificate
fi


if [ "$mode" == "stats" ]; then
  sqlcmd -S "$server" -U "$username" -i ./database_list_with_size.sql -i ./data_type_distribution.sql -i ./other_stats.sql \
  -d "$database" -o "$outputfile" "${auth_flag[@]}" "${trust_cert_flag[@]}"

elif [ "$mode" == "full_metadata" ]; then
  sqlcmd -S "$server" -U "$username" -i ./queries.sql -d "$database" -o "$outputfile" "${auth_flag[@]}" "${trust_cert_flag[@]}"

else
  echo "Mode should be either stats or full_metadata, found: $mode"
  exit 1
fi
