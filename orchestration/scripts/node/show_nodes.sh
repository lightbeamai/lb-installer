#!/bin/bash
export KUBECONFIG=/root/.kube/config
kubectl get nodes -o wide
