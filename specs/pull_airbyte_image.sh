kubectl apply -f https://raw.githubusercontent.com/lightbeamai/lb-installer/master/specs/airbyte-servicenow-ds.yaml
kubectl patch cm/lightbeam-airbyte-env -n lightbeam --type merge -p '{"data": {"JOB_KUBE_MAIN_CONTAINER_IMAGE_PULL_POLICY": "IfNotPresent", "JOB_KUBE_MAIN_CONTAINER_IMAGE_PULL_SECRET": "docregistry-secret"}}'
kubectl get pods -n lightbeam | grep lightbeam-airbyte | awk '{print $1}' | xargs kubectl delete pods -n lightbeam
