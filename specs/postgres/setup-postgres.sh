#!/usr/bin/env bash

set -euxo

readonly WORK_DIR="$(mktemp -d)"
STORAGE_CLASS_NAME=$1
STORAGE_SIZE=$2
NAMESPACE=$3
DATABASE_DUMP_FILE_PATH=$4
DATABASE_NAME=$5
SQL_CREATE_DB_STMT="CREATE DATABASE $DATABASE_NAME;"

mkdir -p overlays
cat <<'EOF' > overlays/pv-patch.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: lb-postgres-data
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
  app: lb-postgres
namespace: NAMESPACE
resources:
  - ../base
patchesStrategicMerge:
  - pv-patch.yaml
EOF

sed -i "s/STORAGE_CLASS_NAME/$STORAGE_CLASS_NAME/g" overlays/pv-patch.yaml
sed -i "s/STORAGE_SIZE/$STORAGE_SIZE/g" overlays/pv-patch.yaml
sed -i "s/NAMESPACE/$NAMESPACE/g" overlays/kustomization.yaml
kubectl create ns "$NAMESPACE" || true
kubectl kustomize overlays/ | kubectl apply -f -
rm -rf overlays
kubectl wait --for=condition=ready pod -l app=lb-postgres  -n "$NAMESPACE" --timeout 300s
pushd "$WORK_DIR"
aws s3 cp "$DATABASE_DUMP_FILE_PATH" dump.sql.gz
gzip -d dump.sql.gz
pgPod=$(kubectl get pods -l app=lb-postgres -o 'jsonpath={.items[0].metadata.name}')
kubectl cp "$(ls *.sql)" "$pgPod":/tmp/
filesList=$(kubectl exec deploy/lb-postgres -- ls /tmp/)
kubectl exec deploy/lb-postgres -- psql --username pgbench -c "$SQL_CREATE_DB_STMT"
kubectl exec deploy/lb-postgres -- psql --username pgbench -d "$DATABASE_NAME" -f /tmp/"$filesList"
