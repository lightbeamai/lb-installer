#!/bin/bash
export KUBECONFIG=/root/.kube/config
if kubectl get nodes --no-headers >/tmp/lb-nodes 2>/dev/null; then
    total=$(wc -l < /tmp/lb-nodes)
    workers=$(awk '$3 !~ /control-plane/ {c++} END {print c+0}' /tmp/lb-nodes)
    ready=$(awk '$2 == "Ready" && $3 !~ /control-plane/ {c++} END {print c+0}' /tmp/lb-nodes)
    printf "NODES|%s|%s|%s\n" "$total" "$workers" "$ready"
else
    echo NOT_READY
fi
