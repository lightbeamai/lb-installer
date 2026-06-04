#!/usr/bin/env bash
set -Eeuo pipefail

NODE_NAME=""
MODE="memory"
NAMESPACE="lb-node-pressure-test"
DURATION_SECONDS=600
CHUNK_MIB=64
SLEEP_SECONDS=2
MAX_MEMORY_MIB=""
MAX_DISK_MIB=""
SPIKE_MEMORY_MIB=102400
ALLOW_CONTROL_PLANE=false
ACK_DESTRUCTIVE=false
CLEANUP_ONLY=false
KEEP_NAMESPACE_ON_FAILURE=false
IMAGE="python:3.12-alpine"

TIMESTAMP="$(date +%Y%m%d%H%M%S)"
TEST_ID="lb-node-pressure-$TIMESTAMP"
ARTIFACT_DIR="${LB_NODE_PRESSURE_ARTIFACT_DIR:-artifacts/node-pressure-test-$TIMESTAMP}"
LABEL_SELECTOR="app.kubernetes.io/name=lb-node-pressure-test,lb.lightbeam.ai/test-id=$TEST_ID"
TEST_SUCCEEDED=false
ADMISSION_LIMITS_DETECTED=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/validate-node-pressure-eviction.sh --node <node-name> [options] --i-understand-this-is-destructive

Required:
  --node <node-name>
  --i-understand-this-is-destructive

Options:
  --mode memory|memory-spike|disk|both Default: memory
  --namespace <namespace>              Default: lb-node-pressure-test
  --duration-seconds <seconds>         Default: 600
  --chunk-mib <MiB>                    Default: 64
  --sleep-seconds <seconds>            Default: 2
  --max-memory-mib <MiB>               Optional cap for memory mode
  --spike-memory-mib <MiB>             Default: 102400 for memory-spike mode
  --max-disk-mib <MiB>                 Optional cap for disk mode; defaults to 4096 when disk is enabled
  --allow-control-plane                Required for control-plane/master nodes
  --cleanup-only                       Delete the test namespace and exit
  --keep-namespace-on-failure          Leave namespace for debugging on failure
  --image <image>                      Default: python:3.12-alpine
  -h, --help                           Show this help

This intentionally creates memory and/or disk pressure on the selected node.
Do not run it on production nodes.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

warn() {
  echo "WARN: $*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required."
}

is_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

validate_name() {
  local value=$1
  local label=$2
  [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || die "$label contains unsupported characters: $value"
}

validate_namespace() {
  local value=$1
  [[ "$value" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || die "--namespace must be a valid Kubernetes namespace name."
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --node)
        NODE_NAME="${2:-}"
        shift 2
        ;;
      --mode)
        MODE="${2:-}"
        shift 2
        ;;
      --namespace)
        NAMESPACE="${2:-}"
        shift 2
        ;;
      --duration-seconds)
        DURATION_SECONDS="${2:-}"
        shift 2
        ;;
      --chunk-mib)
        CHUNK_MIB="${2:-}"
        shift 2
        ;;
      --sleep-seconds)
        SLEEP_SECONDS="${2:-}"
        shift 2
        ;;
      --max-memory-mib)
        MAX_MEMORY_MIB="${2:-}"
        shift 2
        ;;
      --spike-memory-mib)
        SPIKE_MEMORY_MIB="${2:-}"
        shift 2
        ;;
      --max-disk-mib)
        MAX_DISK_MIB="${2:-}"
        shift 2
        ;;
      --allow-control-plane)
        ALLOW_CONTROL_PLANE=true
        shift
        ;;
      --i-understand-this-is-destructive)
        ACK_DESTRUCTIVE=true
        shift
        ;;
      --cleanup-only)
        CLEANUP_ONLY=true
        shift
        ;;
      --keep-namespace-on-failure)
        KEEP_NAMESPACE_ON_FAILURE=true
        shift
        ;;
      --image)
        IMAGE="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

validate_args() {
  [ "$ACK_DESTRUCTIVE" = true ] || die "Refusing to run without --i-understand-this-is-destructive."
  [ -n "$NAMESPACE" ] || die "--namespace must not be empty."
  validate_namespace "$NAMESPACE"

  if [ "$CLEANUP_ONLY" = true ]; then
    return
  fi

  [ -n "$NODE_NAME" ] || die "--node <node-name> is required."
  validate_name "$NODE_NAME" "--node"
  [ "$MODE" = "memory" ] || [ "$MODE" = "memory-spike" ] || [ "$MODE" = "disk" ] || [ "$MODE" = "both" ] || die "--mode must be memory, memory-spike, disk, or both."
  is_positive_int "$DURATION_SECONDS" || die "--duration-seconds must be a positive integer."
  is_positive_int "$CHUNK_MIB" || die "--chunk-mib must be a positive integer."
  is_positive_int "$SLEEP_SECONDS" || die "--sleep-seconds must be a positive integer."
  [ -z "$MAX_MEMORY_MIB" ] || is_positive_int "$MAX_MEMORY_MIB" || die "--max-memory-mib must be a positive integer."
  is_positive_int "$SPIKE_MEMORY_MIB" || die "--spike-memory-mib must be a positive integer."
  [ -z "$MAX_DISK_MIB" ] || is_positive_int "$MAX_DISK_MIB" || die "--max-disk-mib must be a positive integer."
  [[ "$IMAGE" != *" "* ]] || die "--image must not contain spaces."

  if [ "$MODE" = "disk" ] || [ "$MODE" = "both" ]; then
    if [ -z "$MAX_DISK_MIB" ]; then
      MAX_DISK_MIB=4096
      warn "Disk mode enabled without --max-disk-mib; using safety cap of ${MAX_DISK_MIB}MiB."
    fi
  fi
}

print_warning() {
  cat <<EOF
===============================================================================
DESTRUCTIVE NODE PRESSURE VALIDATION

This test intentionally creates $MODE pressure on Kubernetes node: $NODE_NAME
It may evict Pods and may destabilize the target node if kubelet protection is
misconfigured. It does not use hostPath, privileged containers, hostPID, or
hostNetwork, but it still consumes real node resources.

Artifacts will be written to: $ARTIFACT_DIR
Namespace: $NAMESPACE
Memory spike target: ${SPIKE_MEMORY_MIB}MiB
===============================================================================
EOF
}

node_json_file() {
  local output=$1
  kubectl get node "$NODE_NAME" -o json --request-timeout=10s > "$output"
}

node_is_ready() {
  local json_file
  json_file="$(mktemp)"
  if ! node_json_file "$json_file"; then
    rm -f "$json_file"
    return 2
  fi

  python3 - "$json_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    node = json.load(handle)

for condition in node.get("status", {}).get("conditions", []):
    if condition.get("type") == "Ready":
        raise SystemExit(0 if condition.get("status") == "True" else 1)

raise SystemExit(2)
PY
  local result=$?
  rm -f "$json_file"
  return "$result"
}

node_has_control_plane_role() {
  local json_file
  json_file="$(mktemp)"
  node_json_file "$json_file"
  python3 - "$json_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    node = json.load(handle)

labels = node.get("metadata", {}).get("labels", {})
if "node-role.kubernetes.io/control-plane" in labels or "node-role.kubernetes.io/master" in labels:
    raise SystemExit(0)
raise SystemExit(1)
PY
  local result=$?
  rm -f "$json_file"
  return "$result"
}

create_namespace() {
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace "$NAMESPACE" \
    app.kubernetes.io/name=lb-node-pressure-test \
    "lb.lightbeam.ai/test-id=$TEST_ID" \
    --overwrite >/dev/null
}

create_memory_pod() {
  local pod_name="${TEST_ID}-memory"
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: lb-node-pressure-test
    lb.lightbeam.ai/test-id: $TEST_ID
    lb.lightbeam.ai/mode: memory
spec:
  activeDeadlineSeconds: $DURATION_SECONDS
  automountServiceAccountToken: false
  hostNetwork: false
  hostPID: false
  nodeName: "$NODE_NAME"
  restartPolicy: Never
  tolerations:
  - operator: Exists
  containers:
  - name: memory-stress
    image: "$IMAGE"
    imagePullPolicy: IfNotPresent
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
    env:
    - name: CHUNK_MIB
      value: "$CHUNK_MIB"
    - name: SLEEP_SECONDS
      value: "$SLEEP_SECONDS"
    - name: MAX_MEMORY_MIB
      value: "$MAX_MEMORY_MIB"
    command:
    - python3
    - -u
    - -c
    args:
    - |
      import os
      import time

      chunk_mib = int(os.environ["CHUNK_MIB"])
      sleep_seconds = int(os.environ["SLEEP_SECONDS"])
      max_raw = os.environ.get("MAX_MEMORY_MIB", "").strip()
      max_mib = int(max_raw) if max_raw else 0
      allocations = []
      total_mib = 0

      print(f"memory pressure ramp: chunk_mib={chunk_mib} sleep_seconds={sleep_seconds} max_mib={max_mib or 'unbounded'}", flush=True)
      while True:
          if max_mib and total_mib >= max_mib:
              print(f"reached max_memory_mib={max_mib}; holding allocated memory", flush=True)
              while True:
                  time.sleep(sleep_seconds)

          next_mib = chunk_mib
          if max_mib:
              next_mib = min(next_mib, max_mib - total_mib)
          block = bytearray(next_mib * 1024 * 1024)
          for index in range(0, len(block), 4096):
              block[index] = 1
          allocations.append(block)
          total_mib += next_mib
          print(f"allocated_mib={total_mib}", flush=True)
          time.sleep(sleep_seconds)
EOF
}

create_memory_spike_pod() {
  local pod_name="${TEST_ID}-memory-spike"
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: lb-node-pressure-test
    lb.lightbeam.ai/test-id: $TEST_ID
    lb.lightbeam.ai/mode: memory-spike
spec:
  activeDeadlineSeconds: $DURATION_SECONDS
  automountServiceAccountToken: false
  hostNetwork: false
  hostPID: false
  nodeName: "$NODE_NAME"
  restartPolicy: Never
  tolerations:
  - operator: Exists
  containers:
  - name: memory-spike
    image: "$IMAGE"
    imagePullPolicy: IfNotPresent
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
    env:
    - name: SPIKE_MEMORY_MIB
      value: "$SPIKE_MEMORY_MIB"
    command:
    - python3
    - -u
    - -c
    args:
    - |
      import os
      import time

      target_mib = int(os.environ["SPIKE_MEMORY_MIB"])
      chunk_mib = min(1024, target_mib)
      allocations = []
      allocated_mib = 0

      print(f"instant memory spike target_mib={target_mib} chunk_mib={chunk_mib}", flush=True)
      while allocated_mib < target_mib:
          next_mib = min(chunk_mib, target_mib - allocated_mib)
          block = bytearray(next_mib * 1024 * 1024)
          for index in range(0, len(block), 4096):
              block[index] = 1
          allocations.append(block)
          allocated_mib += next_mib
          print(f"allocated_mib={allocated_mib}", flush=True)

      print(f"holding allocated_mib={allocated_mib}", flush=True)
      while True:
          time.sleep(60)
EOF
}

create_disk_pod() {
  local pod_name="${TEST_ID}-disk"
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  namespace: $NAMESPACE
  labels:
    app.kubernetes.io/name: lb-node-pressure-test
    lb.lightbeam.ai/test-id: $TEST_ID
    lb.lightbeam.ai/mode: disk
spec:
  activeDeadlineSeconds: $DURATION_SECONDS
  automountServiceAccountToken: false
  hostNetwork: false
  hostPID: false
  nodeName: "$NODE_NAME"
  restartPolicy: Never
  tolerations:
  - operator: Exists
  containers:
  - name: disk-stress
    image: "$IMAGE"
    imagePullPolicy: IfNotPresent
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
    env:
    - name: CHUNK_MIB
      value: "$CHUNK_MIB"
    - name: SLEEP_SECONDS
      value: "$SLEEP_SECONDS"
    - name: MAX_DISK_MIB
      value: "$MAX_DISK_MIB"
    command:
    - python3
    - -u
    - -c
    args:
    - |
      import os
      import time

      chunk_mib = int(os.environ["CHUNK_MIB"])
      sleep_seconds = int(os.environ["SLEEP_SECONDS"])
      max_mib = int(os.environ["MAX_DISK_MIB"])
      total_mib = 0
      block = b"0" * (1024 * 1024)

      print(f"disk pressure ramp: chunk_mib={chunk_mib} sleep_seconds={sleep_seconds} max_mib={max_mib}", flush=True)
      os.makedirs("/work", exist_ok=True)
      with open("/work/fill.bin", "ab", buffering=0) as handle:
          while total_mib < max_mib:
              next_mib = min(chunk_mib, max_mib - total_mib)
              for _ in range(next_mib):
                  handle.write(block)
              handle.flush()
              os.fsync(handle.fileno())
              total_mib += next_mib
              print(f"written_mib={total_mib}", flush=True)
              time.sleep(sleep_seconds)

      print(f"reached max_disk_mib={max_mib}; holding data on emptyDir", flush=True)
      while True:
          time.sleep(sleep_seconds)
    volumeMounts:
    - name: pressure-data
      mountPath: /work
  volumes:
  - name: pressure-data
    emptyDir: {}
EOF
}

wait_for_pods_to_exist() {
  local deadline=$((SECONDS + 60))
  while [ "$SECONDS" -lt "$deadline" ]; do
    local count
    count="$(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$MODE" = "both" ] && [ "$count" -ge 2 ]; then
      return
    fi
    if [ "$MODE" != "both" ] && [ "$count" -ge 1 ]; then
      return
    fi
    sleep 2
  done
  die "Timed out waiting for stress Pods to be created."
}

detect_admission_resources() {
  local pods_json report
  pods_json="$(mktemp)"
  kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json > "$pods_json"
  report="$(python3 - "$pods_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    pods = json.load(handle)

found = False
for pod in pods.get("items", []):
    pod_name = pod.get("metadata", {}).get("name", "<unknown>")
    for container in pod.get("spec", {}).get("containers", []):
        resources = container.get("resources", {})
        if resources.get("requests") or resources.get("limits"):
            found = True
            print(f"{pod_name}/{container.get('name')}: resources={resources}")

if found:
    print("ADMISSION_LIMITS_DETECTED=true")
PY
)"
  rm -f "$pods_json"

  if [ -n "$report" ]; then
    echo "=== Admission-injected resource settings detected ===" | tee "$ARTIFACT_DIR/admission-resources.txt"
    echo "$report" | tee -a "$ARTIFACT_DIR/admission-resources.txt"
    warn "Admission injected requests or limits. OOMKilled results may be container-limit behavior, not kubelet node-pressure eviction."
    ADMISSION_LIMITS_DETECTED=true
  fi
}

collect_artifacts() {
  mkdir -p "$ARTIFACT_DIR"
  {
    echo "timestamp=$TIMESTAMP"
    echo "node=$NODE_NAME"
    echo "mode=$MODE"
    echo "namespace=$NAMESPACE"
    echo "duration_seconds=$DURATION_SECONDS"
    echo "chunk_mib=$CHUNK_MIB"
    echo "sleep_seconds=$SLEEP_SECONDS"
    echo "max_memory_mib=$MAX_MEMORY_MIB"
    echo "spike_memory_mib=$SPIKE_MEMORY_MIB"
    echo "max_disk_mib=$MAX_DISK_MIB"
    echo "image=$IMAGE"
  } > "$ARTIFACT_DIR/summary.env"

  kubectl get node "$NODE_NAME" -o yaml > "$ARTIFACT_DIR/node.yaml" 2>&1 || true
  kubectl describe node "$NODE_NAME" > "$ARTIFACT_DIR/describe-node.txt" 2>&1 || true
  kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o wide > "$ARTIFACT_DIR/pods-wide.txt" 2>&1 || true
  kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o yaml > "$ARTIFACT_DIR/pods.yaml" 2>&1 || true
  kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp > "$ARTIFACT_DIR/events.txt" 2>&1 || true

  local pod
  while IFS= read -r pod; do
    [ -n "$pod" ] || continue
    kubectl describe pod "$pod" -n "$NAMESPACE" > "$ARTIFACT_DIR/describe-pod-$pod.txt" 2>&1 || true
    kubectl logs "$pod" -n "$NAMESPACE" --all-containers=true > "$ARTIFACT_DIR/logs-$pod.txt" 2>&1 || true
  done < <(kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
}

cleanup() {
  local exit_code=$?
  collect_artifacts

  if [ "$KEEP_NAMESPACE_ON_FAILURE" = true ] && [ "$TEST_SUCCEEDED" != true ]; then
    warn "Keeping namespace $NAMESPACE because --keep-namespace-on-failure was set. Artifacts: $ARTIFACT_DIR"
  else
    kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi

  exit "$exit_code"
}

append_monitor_snapshot() {
  {
    echo ""
    echo "===== $(date -Is) ====="
    kubectl get node "$NODE_NAME" -o wide || true
    kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o wide || true
    kubectl get node "$NODE_NAME" -o json > "$ARTIFACT_DIR/node-last.json" 2>/dev/null || true
    if [ -s "$ARTIFACT_DIR/node-last.json" ]; then
      python3 - "$ARTIFACT_DIR/node-last.json" <<'PY' || true
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    node = json.load(handle)

for condition in node.get("status", {}).get("conditions", []):
    if condition.get("type") in {"Ready", "MemoryPressure", "DiskPressure", "PIDPressure"}:
        print(f"{condition.get('type')}={condition.get('status')} reason={condition.get('reason', '')} message={condition.get('message', '')}")
PY
    fi
  } >> "$ARTIFACT_DIR/monitor.log" 2>&1

  kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp >> "$ARTIFACT_DIR/events-watch.log" 2>&1 || true
}

pod_status_report() {
  local pods_json
  pods_json="$(mktemp)"
  kubectl get pods -n "$NAMESPACE" -l "$LABEL_SELECTOR" -o json > "$pods_json"
  python3 - "$pods_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    pods = json.load(handle)

evicted = []
pressure_failed = []
oom_killed = []
succeeded = []
failed = []
pending = []
running = []

for pod in pods.get("items", []):
    name = pod.get("metadata", {}).get("name", "<unknown>")
    status = pod.get("status", {})
    phase = status.get("phase", "")
    reason = status.get("reason", "")
    message = status.get("message", "")
    text = f"{reason} {message}".lower()

    if reason == "Evicted":
        evicted.append(f"{name}: {message}")
    elif phase == "Failed" and "pressure" in text:
        pressure_failed.append(f"{name}: reason={reason} message={message}")
    elif phase == "Succeeded":
        succeeded.append(name)
    elif phase == "Pending":
        pending.append(f"{name}: reason={reason} message={message}")
    elif phase == "Running":
        running.append(name)
    elif phase == "Failed":
        failed.append(f"{name}: reason={reason} message={message}")

    for container_status in status.get("containerStatuses", []):
        terminated = container_status.get("state", {}).get("terminated")
        if terminated and terminated.get("reason") == "OOMKilled":
            oom_killed.append(f"{name}/{container_status.get('name')}: exitCode={terminated.get('exitCode')} message={terminated.get('message', '')}")

print("RUNNING=" + "|".join(running))
print("PENDING=" + "|".join(pending))
print("SUCCEEDED=" + "|".join(succeeded))
print("FAILED=" + "|".join(failed))
print("OOMKILLED=" + "|".join(oom_killed))
print("EVICTED=" + "|".join(evicted))
print("PRESSURE_FAILED=" + "|".join(pressure_failed))
PY
  rm -f "$pods_json"
}

monitor_until_eviction() {
  local deadline=$((SECONDS + DURATION_SECONDS))
  local saw_oom=false

  while [ "$SECONDS" -lt "$deadline" ]; do
    if ! node_is_ready; then
      append_monitor_snapshot
      die "Target node became NotReady or stopped reporting during the pressure test."
    fi

    append_monitor_snapshot

    local report
    report="$(pod_status_report)"
    echo "$report" >> "$ARTIFACT_DIR/pod-status.log"

    local evicted pressure_failed oomkilled succeeded failed
    evicted="$(printf '%s\n' "$report" | awk -F= '/^EVICTED=/{print $2}')"
    pressure_failed="$(printf '%s\n' "$report" | awk -F= '/^PRESSURE_FAILED=/{print $2}')"
    oomkilled="$(printf '%s\n' "$report" | awk -F= '/^OOMKILLED=/{print $2}')"
    succeeded="$(printf '%s\n' "$report" | awk -F= '/^SUCCEEDED=/{print $2}')"
    failed="$(printf '%s\n' "$report" | awk -F= '/^FAILED=/{print $2}')"

    if [ -n "$evicted" ] || [ -n "$pressure_failed" ]; then
      if node_is_ready; then
        echo "Observed kubelet node-pressure eviction while node stayed Ready."
        echo "$report"
        TEST_SUCCEEDED=true
        return 0
      fi
      die "Observed eviction, but target node was not Ready at final check."
    fi

    if [ -n "$oomkilled" ]; then
      saw_oom=true
    fi

    if [ -n "$succeeded" ]; then
      die "Stress Pod completed without eviction: $succeeded"
    fi

    if [ -n "$failed" ] && [ -z "$oomkilled" ]; then
      die "Stress Pod failed without node-pressure eviction: $failed"
    fi

    sleep 5
  done

  if [ "$saw_oom" = true ] && [ "$ADMISSION_LIMITS_DETECTED" = true ]; then
    die "No kubelet eviction occurred. A stress container was OOMKilled and admission-injected limits were detected, so the result is inconclusive."
  fi

  if [ "$saw_oom" = true ]; then
    die "No kubelet eviction occurred. A stress container was OOMKilled instead of being evicted by node-pressure behavior."
  fi

  die "No kubelet node-pressure eviction occurred within ${DURATION_SECONDS}s."
}

main() {
  parse_args "$@"
  validate_args
  require_cmd kubectl
  require_cmd python3

  if [ "$CLEANUP_ONLY" = true ]; then
    kubectl delete namespace "$NAMESPACE" --ignore-not-found
    exit 0
  fi

  mkdir -p "$ARTIFACT_DIR"
  print_warning

  kubectl get node "$NODE_NAME" >/dev/null
  if node_has_control_plane_role && [ "$ALLOW_CONTROL_PLANE" != true ]; then
    die "Target node has a control-plane/master role. Re-run with --allow-control-plane to test it."
  fi

  if ! node_is_ready; then
    die "Target node must be Ready before starting."
  fi

  trap cleanup EXIT

  create_namespace
  if [ "$MODE" = "memory" ] || [ "$MODE" = "both" ]; then
    create_memory_pod
  fi
  if [ "$MODE" = "memory-spike" ]; then
    create_memory_spike_pod
  fi
  if [ "$MODE" = "disk" ] || [ "$MODE" = "both" ]; then
    create_disk_pod
  fi

  wait_for_pods_to_exist
  detect_admission_resources
  monitor_until_eviction
}

main "$@"
