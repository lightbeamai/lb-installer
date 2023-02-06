#!/usr/bin/env bash

set -euxo

readonly WORK_DIR="$(mktemp -d)"
ACTION=$1
STORAGE_CLASS_NAME=$2
STORAGE_SIZE=$3
NAMESPACE=$4
DATABASE_DUMP_FILE_PATH=$5
DATABASE_NAME=$6
POSTGRES_PASSWORD=$7
NAME=$8
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
  POSTGRES_USER: "cG9zdGdyZXMK"
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
  app: RELEASE_NAME
namespace: NAMESPACE
resources:
  - ../base
  - pg_secret.yaml
patchesStrategicMerge:
  - pv-patch.yaml
  - pg_secret.yaml
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

sed -i "s/STORAGE_CLASS_NAME/$STORAGE_CLASS_NAME/g" overlays/pv-patch.yaml
sed -i "s/STORAGE_SIZE/$STORAGE_SIZE/g" overlays/pv-patch.yaml
sed -i "s/NAMESPACE/$NAMESPACE/g" overlays/kustomization.yaml
sed -i "s/RELEASE_NAME/$NAME/g" overlays/kustomization.yaml
sed -i "s/NAMESPACE/$NAMESPACE/g" overlays/pg_secret.yaml
pgPassword=$(echo "$POSTGRES_PASSWORD" | base64)
sed -i "s/PG_PASSWORD/$pgPassword/g" overlays/pg_secret.yaml
kubectl create ns "$NAMESPACE" || true
kubectl kustomize overlays/
if [[ "$ACTION" == delete ]]; then
  kubectl kustomize overlays/ | kubectl "$ACTION" --ignore-not-found=true -f -
  rm -rf overlays
  exit 0
fi

kubectl kustomize overlays/ | kubectl "$ACTION" -f -
rm -rf overlays
kubectl wait --for=condition=ready pod -l app="$NAME"  -n "$NAMESPACE" --timeout 300s
pushd "$WORK_DIR"
if [[ "$DATABASE_DUMP_FILE_PATH" == s3://* ]]; then
  aws s3 cp "$DATABASE_DUMP_FILE_PATH" dump.sql.gz
else
  cp "$DATABASE_DUMP_FILE_PATH" dump.sql.gz
fi
if [[ "$DATABASE_DUMP_FILE_PATH" == *.gz ]]; then
  gzip -d dump.sql.gz
else
  mv dump.sql.gz dump.sql
fi

pgPod=$(kubectl get pods -l app="$NAME" -o 'jsonpath={.items[0].metadata.name}')
kubectl cp "$(ls *.sql)" "$pgPod":/tmp/
filesList=$(kubectl exec deploy/"$NAME" -- ls /tmp/)
kubectl exec deploy/"$NAME" -- psql --username postgres -c "$SQL_CREATE_DB_STMT"
kubectl exec deploy/"$NAME" -- psql --username postgres -d "$DATABASE_NAME" -f /tmp/"$filesList"
