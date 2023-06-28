#!/bin/bash

# Set your variable values here
instance_url="https://lightbeam.develop.my.salesforce.com"
client_key="3MVG9n_HvETGhr.......................................MC_twiaGbrj.pF._"
client_secret="A89A8605ADF6............................................B3B2A"

redirect_uri="https://login.salesforce.com"

function obtain_authorization_code {
    instance_url=$1
    client_key=$2
    redirect_uri=$3

    authorization_url="${instance_url}/services/oauth2/authorize?response_type=code&client_id=${client_key}&redirect_uri=${redirect_uri}"
    printf "\nPlease log in to Salesforce and visit the following URL to obtain the authorization code:"
    echo "$authorization_url"
}

function obtain_access_token {
    instance_url=$1
    client_key=$2
    client_secret=$3
    redirect_uri=$4
    authorization_code=$5

    token_url="${instance_url}/services/oauth2/token"
    params=("code=${authorization_code}&grant_type=authorization_code&client_id=${client_key}&client_secret=${client_secret}&redirect_uri=${redirect_uri}")

    response=$(curl -s -X POST "${token_url}" -d "${params[*]}")
    if [ $? -ne 0 ]; then
        echo "Failed to obtain refresh token. Response: $response" >&2
        exit 1
    fi

    echo "$response"
}


function main {
    obtain_authorization_code "$instance_url" "$client_key" "$redirect_uri"
    read -rp "Enter the authorization code: " authorization_code

    authorization_code=$(echo -e "${authorization_code//%/\\x}")

    obtain_access_token "$instance_url" "$client_key" "$client_secret" "$redirect_uri" "$authorization_code"
}

main
