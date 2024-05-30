#!/usr/bin/env bash

set -e

readonly CMD="az"
readonly RESOURCE_GROUP=$RESOURCE_GROUP
readonly ACCOUNT_NAME=$ACCOUNT_NAME
readonly CLIENT_ID=$CLIENT_ID
readonly CLIENT_SECRET=$CLIENT_SECRET
readonly TENANT_ID=$TENANT_ID

az login --service-principal --username $CLIENT_ID --password $CLIENT_SECRET --tenant $TENANT_ID

if [ $? -ne 0 ]; then
  echo "Azure login failed. Exiting script."
  exit 1
fi


echo "Listing all databases in the Cosmos DB account..."
az cosmosdb sql database list --resource-group $RESOURCE_GROUP --account-name $ACCOUNT_NAME --query "[].{Database:id}" --output table
