#!/usr/bin/env bash

set -euxo

readonly WORK_DIR="$(mktemp -d)"
STORAGE_CLASS_NAME=$1
STORAGE_SIZE=$2
NAMESPACE=$3
DATABASE_DUMP_FILE_PATH=$4
DATABASE_NAME=$5
POSTGRES_PASSWORD=$6
SQL_CREATE_DB_STMT="CREATE DATABASE $DATABASE_NAME;"

mkdir -p overlays

cat <<'EOF' > overlays/pg_secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: lb-postgres-secret
  namespace: NAMESPACE
  labels:
    app: lb-postgres
type: Opaque
data:
  POSTGRES_PASSWORD: "PG_PASSWORD"
EOF
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
  - pg_secret.yaml
patchesStrategicMerge:
  - pv-patch.yaml
  - pg_secret.yaml
EOF

sed -i "s/STORAGE_CLASS_NAME/$STORAGE_CLASS_NAME/g" overlays/pv-patch.yaml
sed -i "s/STORAGE_SIZE/$STORAGE_SIZE/g" overlays/pv-patch.yaml
sed -i "s/NAMESPACE/$NAMESPACE/g" overlays/kustomization.yaml
sed -i "s/NAMESPACE/$NAMESPACE/g" overlays/pg_secret.yaml
pgPassword=$(echo "$POSTGRES_PASSWORD" | base64)
sed -i "s/PG_PASSWORD/$pgPassword/g" overlays/pg_secret.yaml
kubectl create ns "$NAMESPACE" || true
kubectl kustomize overlays/ | kubectl apply -f -
rm -rf overlays
kubectl wait --for=condition=ready pod -l app=lb-postgres  -n "$NAMESPACE" --timeout 300s
pushd "$WORK_DIR"
if [[ "$DATABASE_DUMP_FILE_PATH" == s3://* ]]; then
  aws s3 cp "$DATABASE_DUMP_FILE_PATH" dump.sql.gz
else
  cp "$DATABASE_DUMP_FILE_PATH" dump.sql.gz
fi
gzip -d dump.sql.gz
pgPod=$(kubectl get pods -l app=lb-postgres -o 'jsonpath={.items[0].metadata.name}')
kubectl cp "$(ls *.sql)" "$pgPod":/tmp/
filesList=$(kubectl exec deploy/lb-postgres -- ls /tmp/)
kubectl exec deploy/lb-postgres -- psql --username postgres -c "$SQL_CREATE_DB_STMT"
kubectl exec deploy/lb-postgres -- psql --username postgres -d "$DATABASE_NAME" -f /tmp/"$filesList"
