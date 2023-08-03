#!/usr/bin/env bash

trap 'kill $(jobs -p)' EXIT
/usr/bin/kubectl port-forward service/kong-proxy -n lightbeam --address 0.0.0.0 80:80 --kubeconfig /root/.kube/config &
PID=$!

/bin/systemd-notify --ready

while(true); do
    FAIL=0
    kill -0 $PID
    if [[ $? -ne 0 ]]; then FAIL=1; fi
    status_code=`curl -s -o /dev/null -w "%{http_code}" http://localhost/api/health`
    echo "Lightbeam cluster health check: $status_code"
    if [[ $? -ne 0 || $status_code -ne 200 ]]; then FAIL=1; fi
    if [[ $FAIL -eq 0 ]]; then /bin/systemd-notify WATCHDOG=1; fi
    sleep 1
done
