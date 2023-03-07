#!/bin/bash

set -e

usage()
{
cat <<EOF
Usage: $0
    --stop <Stop LightBeam Cluster Services>
    --start <Start LightBeam Cluster Services>
    --lb-namespace <Lightbeam cluster namespace>

Examples:
    # Stop services.
    ./start-stop-lb-services.sh --stop

    # Start services.
    ./start-stop-lb-services.sh --start

EOF
exit 1
}

while [ "$1" != "" ]; do
    case $1 in
    --stop)             STOP_SERVICES="True"
                          ;;
    --start)            START_SERVICES="True"
                          ;;
    --lb-namespace)     shift
                        NAMESPACE=$1
                          ;;
    -h | --help )   usage
                    ;;
    * )             usage
    esac
    shift
done

LB_DEFAULT_NAMESPACE="lightbeam"
API_GATEWAY_DEPLOYMENT_NAME="lightbeam-api-gateway"
PRESIDIO_SERVER_DEPLOYMENT_NAME="lightbeam-presidio-server"
TEXT_EXTRACTION_DEPLOYMENT_NAME="lightbeam-text-extraction"
TIKA_DEPLOYMENT_NAME="lightbeam-tika-server"
DATASOURCE_STATS_AGGREGATOR_DEPLOY_NAME="lightbeam-datasource-stats-aggregator"
POLICY_ENGINE_DEPLOY_NAME="lightbeam-policy-engine"
POLICY_CONSUMER_DEPLOY_NAME="lightbeam-policy-consumer"
DATASOURCE_STATS_AGGREGATOR_KAFKA_QUEUE="datasource-stats"

if [ -z ${NAMESPACE} ]; then
  NAMESPACE=$LB_DEFAULT_NAMESPACE
fi

if [[ -z ${STOP_SERVICES} && -z ${START_SERVICES} ]]; then
   usage
fi

if [ ${STOP_SERVICES} ]; then
   CRONJOB_SUSPEND_ENABLED="true"
   REPLICAS="0"
fi

if [ ${START_SERVICES} ]; then
   CRONJOB_SUSPEND_ENABLED="false"
   REPLICAS="1"
fi

for cj in $(kubectl get cronjobs -n "$NAMESPACE" -o name); do
  echo "Resuming cronjob $cj in namespace $NAMESPACE"
  kubectl patch "$cj" -n "$NAMESPACE" -p '{"spec" : {"suspend" : '$CRONJOB_SUSPEND_ENABLED' }}';
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
