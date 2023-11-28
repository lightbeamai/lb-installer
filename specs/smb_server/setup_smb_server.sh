#!/usr/bin/env bash

set -euxo

readonly SMB_SERVER_READY_TIMEOUT_SECONDS=300
readonly SMB_SERVER_READY_WAIT_POLL_SECONDS=10
ACTION=$1
STORAGE_CLASS_NAME=$2
STORAGE_SIZE=$3
NAMESPACE=$4
NAME="lb-smb"
SMB_USERNAME=$5
SMB_PASSWORD=$6

mkdir -p overlays

cat <<'EOF' > overlays/smb_secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: smbcreds
  namespace: NAMESPACE
  labels:
    app: lb-smb-server
type: Opaque
data:
  username: "SMB_USERNAME"
  password: "SMB_PASSWORD"
EOF

cat <<'EOF' > overlays/pvc-patch.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: lb-smbshare
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
  - smb_secret.yaml
patchesStrategicMerge:
  - pvc-patch.yaml
  - smb_secret.yaml
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

sed -i "s/STORAGE_CLASS_NAME/$STORAGE_CLASS_NAME/g" overlays/pvc-patch.yaml
sed -i "s/STORAGE_SIZE/$STORAGE_SIZE/g" overlays/pvc-patch.yaml
sed -i "s/NAMESPACE/$NAMESPACE/g" overlays/kustomization.yaml
sed -i "s/RELEASE_NAME/$NAME/g" overlays/kustomization.yaml
sed -i "s/NAMESPACE/$NAMESPACE/g" overlays/smb_secret.yaml
smbUsername=$(echo "$SMB_USERNAME" | base64)
sed -i "s/SMB_USERNAME/$smbUsername/g" overlays/smb_secret.yaml
smbPassword=$(echo "$SMB_PASSWORD" | base64)
sed -i "s/SMB_PASSWORD/$smbPassword/g" overlays/smb_secret.yaml
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
        if [[ $(kubectl  get po -n $NAMESPACE "$pod_name" -o jsonpath='{.status.containerStatuses[*].ready}') == 'true' ]]
          then
            echo "The SMB server is ready with pod name $pod_name."
            success=1
            break
        fi
    done
    if [[ "$success" == 1 ]]
     then
       break
    fi
    echo "The SMB server is not yet ready. Waiting for $SMB_SERVER_READY_WAIT_POLL_SECONDS seconds before checking again."
    sleep "$SMB_SERVER_READY_WAIT_POLL_SECONDS"
    end_time=$(date +%s)
    timeElapsedSeconds=$(echo "$end_time - $start_time" | bc)

    if [[ "$timeElapsedSeconds" -gt "$SMB_SERVER_READY_TIMEOUT_SECONDS" ]]; then
      echo "Spent $SMB_SERVER_READY_TIMEOUT_SECONDS seconds waiting for SMB server to come up."
      exit 1
    fi
done
