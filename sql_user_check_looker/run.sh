#!/usr/bin/env bash

set -e

readonly URL=$URL
readonly CLIENT_ID=$CLIENT_ID
readonly CLIENT_SECRET=$CLIENT_SECRET

commands=("curl" "jq")

for cmd in "${commands[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Command $cmd could not be found."
        exit 1
    fi
done


response=$(curl -s -w "\n%{http_code}" -d "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" "$URL/api/4.0/login")
http_status_code="$(echo "$response" | tail -n 1)"
if [[ $http_status_code != "200" ]]; then
    echo "Error getting access_token, HTTP status code is $http_status_code"
    exit 1
fi


access_token="$(echo "$response" | sed '$d' | jq -r .access_token)"

all_models=$(curl -s -w "\n%{http_code}" -H "Authorization: token $access_token" -H "Content-Type: application/json" "$URL/api/4.0/lookml_models")
http_status_code="$(echo "$all_models" | tail -n 1)"
if [[ $http_status_code != "200" ]]; then
    echo "Error getting LookML models, HTTP status code is $http_status_code"
    exit 1
fi

models_count=$(echo "$all_models" | sed '$d' | jq 'length')
echo "Number of Models: $models_count"

explores_count=$(echo "$all_models" | sed '$d' | jq '[.[] | .explores | length] | add')
echo "Number of Explores: $explores_count"
