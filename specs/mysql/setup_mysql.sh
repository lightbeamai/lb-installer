#!/usr/bin/env bash
# deploy mysql server on kube cluster
# Usage: ./setup_mysql.sh

set -euxo

readonly MYSQL_READY_TIMEOUT_SECONDS=300
readonly MYSQL_READY_WAIT_POLL_SECONDS=10
readonly WORK_DIR="$(mktemp -d)"

ACTION=$1
STORAGE_CLASS_NAME=$2
STORAGE_SIZE=$3
NAMESPACE=$4
DATABASE_DUMP_DIRECTORY_PATH=$5
DATABASE_NAME=$6
MYSQL_PASSWORD=$7
NAME=$8
SQL_CREATE_DB_STMT="CREATE DATABASE $DATABASE_NAME;"
GRANT_PERMISSION_STMT="GRANT SELECT ON *.* TO mysql;"

mkdir -p overlays

# Create the overlay
cat <<EOF > overlays/mysql_secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: lb-mysql-secret
  namespace: NAMESPACE
  labels:
    app: lb-mysql
type: Opaque
data:
  MYSQL_ROOT_PASSWORD: "MYSQLPASSWORD"
  MYSQL_PASSWORD: "MYSQLPASSWORD"
  MYSQL_USER: "bXlzcWw="
EOF

cat <<'EOF' > overlays/pv-patch.yaml
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
  - pv-patch.yaml
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


sed -i "s/STORAGE_CLASS_NAME/$STORAGE_CLASS_NAME/g" overlays/pv-patch.yaml
sed -i "s/STORAGE_SIZE/$STORAGE_SIZE/g" overlays/pv-patch.yaml
sed -i "s/NAMESPACE/$NAMESPACE/g" overlays/kustomization.yaml
sed -i "s/RELEASE_NAME/$NAME/g" overlays/kustomization.yaml
sed -i "s/NAMESPACE/$NAMESPACE/g" overlays/mysql_secret.yaml
mysqlPassword=$(echo -n "$MYSQL_PASSWORD" | base64)
sed -i "s/MYSQLPASSWORD/$mysqlPassword/g" overlays/mysql_secret.yaml
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
    for pod_name in $(kubectl get pods -n $NAMESPACE -l app="$NAME" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}')
    do
        if [[ $(kubectl  get po -n $NAMESPACE "$pod_name" -o jsonpath='{.status.containerStatuses[*].ready}') == 'true'  ]]
          then
            echo "The mysql instance is ready with pod name $pod_name. Starting data dump now."
            success=1
            break
        fi
    done
    if [[ "$success" == 1 ]]
     then
       break
    fi
    echo "The mysql instance is not yet ready. Waiting for $MYSQL_READY_WAIT_POLL_SECONDS seconds before checking again."
    sleep "$MYSQL_READY_WAIT_POLL_SECONDS"
    end_time=$(date +%s)
    timeElapsedSeconds=$(echo "$end_time - $start_time" | bc)

    if [[ "$timeElapsedSeconds" -gt "$MYSQL_READY_TIMEOUT_SECONDS" ]]; then
      echo "Spent $MYSQL_READY_TIMEOUT_SECONDS seconds waiting for mysql instance to come up. Giving up."
      exit 1
    fi
done

pushd "$WORK_DIR"
pod_name=$(kubectl get pods -n "$NAMESPACE" -l app="$NAME" -o jsonpath='{.items[0].metadata.name}')
for file in "$DATABASE_DUMP_DIRECTORY_PATH"/*.sql
do
  kubectl cp "$file" "$pod_name":/tmp/ -n "$NAMESPACE"
done

mysqlPod=$(kubectl get pods -l app="$NAME" -n "$NAMESPACE" -o 'jsonpath={.items[0].metadata.name}')
kubectl cp "$(ls $DATABASE_DUMP_DIRECTORY_PATH/*.sql)" "$mysqlPod":/tmp/ -n "$NAMESPACE"
filesList=$(kubectl exec -n "$NAMESPACE" deploy/"$NAME" -- ls tmp/)
kubectl exec -n "$NAMESPACE" deploy/"$NAME" -- mysql -u root -p"$MYSQL_PASSWORD" -e "$SQL_CREATE_DB_STMT"
kubectl exec -n "$NAMESPACE" deploy/"$NAME" -- mysql -u root -p"$MYSQL_PASSWORD" "$DATABASE_NAME" -e "source /tmp/$filesList"
kubectl exec -n "$NAMESPACE" deploy/"$NAME" -- mysql -u root -p"$MYSQL_PASSWORD" -e "$GRANT_PERMISSION_STMT"
