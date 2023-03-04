#!/bin/bash

set -e

NAMESPACE="lightbeam"
API_GATEWAY_DEPLOYMENT_NAME="lightbeam-api-gateway"
PRESIDIO_SERVER_DEPLOYMENT_NAME="lightbeam-presidio-server"
TEXT_EXTRACTION_DEPLOYMENT_NAME="lightbeam-text-extraction"
TIKA_DEPLOYMENT_NAME="lightbeam-tika-server"
DATASOURCE_STATS_AGGREGATOR_DEPLOY_NAME="lightbeam-datasource-stats-aggregator"
POLICY_ENGINE_DEPLOY_NAME="lightbeam-policy-engine"
POLICY_CONSUMER_DEPLOY_NAME="lightbeam-policy-consumer"
DATASOURCE_STATS_AGGREGATOR_KAFKA_QUEUE="datasource-stats"
REPLICAS="1"
REQUIRED_COMMANDS=('jq' 'mongodump')

for cmd in "${REQUIRED_COMMANDS[@]}"
do
  echo "Checking for command $cmd"
  if ! command -v "$cmd" &> /dev/null
  then
      echo "Command $cmd could not be found, Exiting"
      exit 1
  fi
done

for cj in $(kubectl get cronjobs -n "$NAMESPACE" -o name); do
  echo "Resuming cronjob $cj in namespace $NAMESPACE"
  kubectl patch "$cj" -n "$NAMESPACE" -p '{"spec" : {"suspend" : false }}';
done

for deploy in $(kubectl get deploy -o=jsonpath="{.items[*]['metadata.name']}" -n $NAMESPACE); do
  if [[ "$deploy" =~ lb-.*-consumer.* ]] || [[ "$deploy" =~ lb-.*-producer.* ]] ||
  [[ "$deploy" == "$API_GATEWAY_DEPLOYMENT_NAME" ]] || [[ "$deploy" == "$PRESIDIO_SERVER_DEPLOYMENT_NAME" ]] ||
  [[ "$deploy" == "$TEXT_EXTRACTION_DEPLOYMENT_NAME" ]] || [[ "$deploy" == "$POLICY_ENGINE_DEPLOY_NAME" ]] ||
  [[ "$deploy" == "$POLICY_CONSUMER_DEPLOY_NAME" ]] || [[ "$deploy" == "$TIKA_DEPLOYMENT_NAME" ]] ||
  [[ "$deploy" == "$DATASOURCE_STATS_AGGREGATOR_DEPLOY_NAME" ]]; then
    echo "Scaling up replicas of deployment $deploy to $REPLICAS"
    kubectl scale deploy "$deploy" -n $NAMESPACE --replicas=$REPLICAS
  fi
done