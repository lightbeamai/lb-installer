#!/usr/bin/env bash

set -euxo

readonly MYSQL_READY_TIMEOUT_SECONDS=300
readonly MYSQL_READY_WAIT_POLL_SECONDS=10
ACTION=$1
STORAGE_CLASS_NAME=$2
STORAGE_SIZE=$3
NAMESPACE=$4
MYSQL_PASSWORD=$5
NAME=$6

mkdir -p overlays

cat <<'EOF' > overlays/mysql_secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: lb-mysql-secret
  namespace: NAMESPACE
  labels:
    app: lb-mysql
type: Opaque
data:
  MY_PASSWORD: "MYSQL_PASSWORD"
EOF
cat <<'EOF' > overlays/mysql-patch.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: lb-mysql-data
spec:
  storageClassName: STORAGE_CLASS_NAME
  resources:
    requests:
      storage: STORAGE_SIZE
EOF

cat <<'EOF' > overlays/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
commonLabels:
  app: RELEASE_NAME
namespace: NAMESPACE
resources:
  - ../base
  - mysql_secret.yaml
patchesStrategicMerge:
  - mysql-patch.yaml
  - mysql_secret.yaml
patches:
- target:
    kind: Secret
    name: .*
  patch: |-
    - op: replace
      path: /metadata/name
      value: RELEASE_NAME
- target:
    kind: Service
    name: .*
  patch: |-
    - op: replace
      path: /metadata/name
      value: RELEASE_NAME
- target:
    kind: PersistentVolumeClaim
    name: .*
  patch: |-
    - op: replace
      path: /metadata/name
      value: RELEASE_NAME
- target:
    kind: Deployment
    name: .*
  patch: |-
    - op: replace
      path: /metadata/name
      value: RELEASE_NAME
EOF

sed -i "s/STORAGE_CLASS_NAME/$STORAGE_CLASS_NAME/g" overlays/mysql-patch.yaml
sed -i "s/STORAGE_SIZE/$STORAGE_SIZE/g" overlays/mysql-patch.yaml
sed -i "s/NAMESPACE/$NAMESPACE/g" overlays/kustomization.yaml
sed -i "s/RELEASE_NAME/$NAME/g" overlays/kustomization.yaml
sed -i "s/NAMESPACE/$NAMESPACE/g" overlays/mysql_secret.yaml
mysqlPassword=$(echo "$MYSQL_PASSWORD" | base64)
sed -i "s/MYSQL_PASSWORD/$mysqlPassword/g" overlays/mysql_secret.yaml
kubectl create ns "$NAMESPACE" || true
kubectl kustomize overlays/
if [[ "$ACTION" == delete ]]; then
  kubectl kustomize overlays/ | kubectl "$ACTION" --ignore-not-found=true -f -
  rm -rf overlays
  exit 0
fi

kubectl kustomize overlays/ | kubectl "$ACTION" -f -
rm -rf overlays

start_time=$(date +%s)
while true
do
    success=0
    for pod_name in $(kubectl get pods -l app="$NAME" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}')
    do
        if [[ $(kubectl  get po "$pod_name" -o jsonpath='{.status.containerStatuses[*].ready}') == 'true'  ]]
          then
            echo "The MySQL instance is ready with pod name $pod_name. Starting data dump now."
            success=1
            break
        fi
    done
    if [[ "$success" == 1 ]]
     then
       break
    fi
    echo "The MySQL instance is not yet ready. Waiting for $MYSQL_READY_WAIT_POLL_SECONDS seconds before checking again."
    sleep "$MYSQL_READY_WAIT_POLL_SECONDS"
    end_time=$(date +%s)
    timeElapsedSeconds=$(echo "$end_time - $start_time" | bc)

    if [[ "$timeElapsedSeconds" -gt "$MYSQL_READY_TIMEOUT_SECONDS" ]]; then
      echo "Spent $MYSQL_READY_TIMEOUT_SECONDS seconds waiting for MySQL instance to come up. Giving up."
      exit 1
    fi
done
