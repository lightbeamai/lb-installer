#!/usr/bin/env bash

set -e

readonly URL=$URL
readonly CLIENT_ID=$CLIENT_ID
readonly CLIENT_SECRET=$CLIENT_SECRET

response=$(curl -s -d "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET" "$URL/api/4.0/login")
access_token=$(echo "$response" | jq -r '.access_token')

all_models=$(curl -s -H "Authorization: token $access_token" -H "Content-Type: application/json" "$URL/api/4.0/lookml_models")

models_count=$(echo "$all_models" | jq 'length')
echo "Number of Models: $models_count"

explores_count=$(echo "$all_models" | jq '[.[] | .explores | length] | add')
echo "Number of Explores: $explores_count"
