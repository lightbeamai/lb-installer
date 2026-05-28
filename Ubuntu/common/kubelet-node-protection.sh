# Shared Bash library for kubelet reservation and node-pressure eviction
# defaults used by Ubuntu installers and maintenance scripts.

lb_set_kubelet_node_protection_defaults() {
  : "${LB_KUBE_RESERVED_CPU:=300m}"
  : "${LB_KUBE_RESERVED_MEMORY:=512Mi}"
  : "${LB_KUBE_RESERVED_EPHEMERAL_STORAGE:=2Gi}"
  : "${LB_KUBE_RESERVED_PID:=1000}"
  : "${LB_SYSTEM_RESERVED_CPU:=300m}"
  : "${LB_SYSTEM_RESERVED_MEMORY:=512Mi}"
  : "${LB_SYSTEM_RESERVED_EPHEMERAL_STORAGE:=2Gi}"
  : "${LB_SYSTEM_RESERVED_PID:=1000}"
  : "${LB_EVICTION_MEMORY_AVAILABLE:=500Mi}"
  : "${LB_EVICTION_NODEFS_AVAILABLE:=10%}"
  : "${LB_EVICTION_NODEFS_INODES_FREE:=5%}"
  : "${LB_EVICTION_IMAGEFS_AVAILABLE:=15%}"
  : "${LB_EVICTION_IMAGEFS_INODES_FREE:=5%}"
  : "${LB_EVICTION_RECLAIM_MEMORY_AVAILABLE:=256Mi}"
  : "${LB_EVICTION_RECLAIM_NODEFS_AVAILABLE:=1Gi}"
  : "${LB_EVICTION_RECLAIM_IMAGEFS_AVAILABLE:=1Gi}"
  : "${LB_ENFORCE_NODE_ALLOCATABLE:=pods}"
}

lb_export_kubelet_node_protection_env() {
  export LB_KUBE_RESERVED_CPU
  export LB_KUBE_RESERVED_MEMORY
  export LB_KUBE_RESERVED_EPHEMERAL_STORAGE
  export LB_KUBE_RESERVED_PID
  export LB_SYSTEM_RESERVED_CPU
  export LB_SYSTEM_RESERVED_MEMORY
  export LB_SYSTEM_RESERVED_EPHEMERAL_STORAGE
  export LB_SYSTEM_RESERVED_PID
  export LB_EVICTION_MEMORY_AVAILABLE
  export LB_EVICTION_NODEFS_AVAILABLE
  export LB_EVICTION_NODEFS_INODES_FREE
  export LB_EVICTION_IMAGEFS_AVAILABLE
  export LB_EVICTION_IMAGEFS_INODES_FREE
  export LB_EVICTION_RECLAIM_MEMORY_AVAILABLE
  export LB_EVICTION_RECLAIM_NODEFS_AVAILABLE
  export LB_EVICTION_RECLAIM_IMAGEFS_AVAILABLE
  export LB_ENFORCE_NODE_ALLOCATABLE
}

lb_yaml_quote() {
  local value=${1//\\/\\\\}
  value=${value//\"/\\\"}
  printf '"%s"' "$value"
}

lb_render_enforce_node_allocatable() {
  local raw item trimmed
  local -a items
  raw="${LB_ENFORCE_NODE_ALLOCATABLE:-pods}"
  IFS=',' read -r -a items <<< "$raw"
  for item in "${items[@]}"; do
    trimmed="${item#"${item%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if [ -n "$trimmed" ]; then
      printf '  - %s\n' "$(lb_yaml_quote "$trimmed")"
    fi
  done
}

lb_render_kubelet_configuration() {
  lb_set_kubelet_node_protection_defaults

  cat <<EOF
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
kubeReserved:
  cpu: $(lb_yaml_quote "$LB_KUBE_RESERVED_CPU")
  memory: $(lb_yaml_quote "$LB_KUBE_RESERVED_MEMORY")
  ephemeral-storage: $(lb_yaml_quote "$LB_KUBE_RESERVED_EPHEMERAL_STORAGE")
  pid: $(lb_yaml_quote "$LB_KUBE_RESERVED_PID")
systemReserved:
  cpu: $(lb_yaml_quote "$LB_SYSTEM_RESERVED_CPU")
  memory: $(lb_yaml_quote "$LB_SYSTEM_RESERVED_MEMORY")
  ephemeral-storage: $(lb_yaml_quote "$LB_SYSTEM_RESERVED_EPHEMERAL_STORAGE")
  pid: $(lb_yaml_quote "$LB_SYSTEM_RESERVED_PID")
evictionHard:
  memory.available: $(lb_yaml_quote "$LB_EVICTION_MEMORY_AVAILABLE")
  nodefs.available: $(lb_yaml_quote "$LB_EVICTION_NODEFS_AVAILABLE")
  nodefs.inodesFree: $(lb_yaml_quote "$LB_EVICTION_NODEFS_INODES_FREE")
  imagefs.available: $(lb_yaml_quote "$LB_EVICTION_IMAGEFS_AVAILABLE")
  imagefs.inodesFree: $(lb_yaml_quote "$LB_EVICTION_IMAGEFS_INODES_FREE")
evictionMinimumReclaim:
  memory.available: $(lb_yaml_quote "$LB_EVICTION_RECLAIM_MEMORY_AVAILABLE")
  nodefs.available: $(lb_yaml_quote "$LB_EVICTION_RECLAIM_NODEFS_AVAILABLE")
  imagefs.available: $(lb_yaml_quote "$LB_EVICTION_RECLAIM_IMAGEFS_AVAILABLE")
mergeDefaultEvictionSettings: true
enforceNodeAllocatable:
EOF
  lb_render_enforce_node_allocatable
}

lb_print_kubelet_node_protection_summary() {
  lb_set_kubelet_node_protection_defaults

  cat <<EOF
Kubelet node protection settings:
  kubeReserved:
    cpu: $LB_KUBE_RESERVED_CPU
    memory: $LB_KUBE_RESERVED_MEMORY
    ephemeral-storage: $LB_KUBE_RESERVED_EPHEMERAL_STORAGE
    pid: $LB_KUBE_RESERVED_PID
  systemReserved:
    cpu: $LB_SYSTEM_RESERVED_CPU
    memory: $LB_SYSTEM_RESERVED_MEMORY
    ephemeral-storage: $LB_SYSTEM_RESERVED_EPHEMERAL_STORAGE
    pid: $LB_SYSTEM_RESERVED_PID
  evictionHard:
    memory.available: $LB_EVICTION_MEMORY_AVAILABLE
    nodefs.available: $LB_EVICTION_NODEFS_AVAILABLE
    nodefs.inodesFree: $LB_EVICTION_NODEFS_INODES_FREE
    imagefs.available: $LB_EVICTION_IMAGEFS_AVAILABLE
    imagefs.inodesFree: $LB_EVICTION_IMAGEFS_INODES_FREE
  evictionMinimumReclaim:
    memory.available: $LB_EVICTION_RECLAIM_MEMORY_AVAILABLE
    nodefs.available: $LB_EVICTION_RECLAIM_NODEFS_AVAILABLE
    imagefs.available: $LB_EVICTION_RECLAIM_IMAGEFS_AVAILABLE
  mergeDefaultEvictionSettings: true
  enforceNodeAllocatable: $LB_ENFORCE_NODE_ALLOCATABLE
EOF
}

lb_set_kubelet_node_protection_defaults
