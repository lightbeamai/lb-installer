#!/bin/bash
command -v kubelet >/dev/null 2>&1 && echo PACKAGES_READY || echo PACKAGES_MISSING
systemctl is-active --quiet wg-quick@wg0 && echo WG_READY || echo WG_WAITING
systemctl is-active --quiet kubelet && echo KUBELET_READY || echo KUBELET_WAITING
test -f /etc/kubernetes/kubelet.conf && echo KUBECONF_READY || echo KUBECONF_WAITING
