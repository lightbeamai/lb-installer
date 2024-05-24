#!/usr/bin/env bash

read -rp "Enter Salesforce instance URL: " instance_url
read -rp "Enter Client Key: " client_key
read -rp "Enter Client Secret: " client_secret
read -rp "Enter Redirect URI: " redirect_uri

function obtain_authorization_code {
    local instance_url=$1
    local client_key=$2
    local client_secret=$3
    local redirect_uri=$4
    local code_challenge=$5

    local authorization_url="${instance_url}/services/oauth2/authorize?response_type=code&client_id=${client_key}&client_secret=${client_secret}&redirect_uri=${redirect_uri}&code_challenge=${code_challenge}&code_challenge_method=S256"
    printf "\nPlease log in to Salesforce and visit the following URL to obtain the authorization code:\n"
    echo "$authorization_url"
}

function obtain_access_token {
    local instance_url=$1
    local client_key=$2
    local client_secret=$3
    local redirect_uri=$4
    local authorization_code=$5
    local code_verifier=$6

    local token_url="${instance_url}/services/oauth2/token"
    local params="code=${authorization_code}&grant_type=authorization_code&client_id=${client_key}&client_secret=${client_secret}&redirect_uri=${redirect_uri}&code_verifier=${code_verifier}"

    local response=$(curl -s -X POST "${token_url}" -d "${params}")
    if [ $? -ne 0 ]; then
        echo "Failed to obtain access token. Response: $response" >&2
        exit 1
    fi

    echo "Instance URL: $instance_url"
    echo "Client Key: $client_key"
    echo "Client Secret: $client_secret"
    echo "Redirect URL: $redirect_uri"
    echo "Response: $response"
}

function main {
    local code_verifier="eyIxIjo3MiwiMiI6MTM0LCIzIjoyMzUsIjQiOjM2fQ"
    local code_challenge="jx-xeR5u7ftCAUivPX_bF2LTuGl8fAQBtmEdTwl9Jm4"

    obtain_authorization_code "$instance_url" "$client_key" "$client_secret" "$redirect_uri" "$code_challenge"
    read -rp "Enter the authorization code: " authorization_code

    obtain_access_token "$instance_url" "$client_key" "$client_secret" "$redirect_uri" "$authorization_code" "$code_verifier"
}

main