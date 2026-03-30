#!/bin/bash
# Usage (via env vars):
#   ACTION=check  CHECKPOINT_NAME=<name>  NODE_STATE_DIR=<dir>
#   ACTION=mark   CHECKPOINT_NAME=<name>  NODE_STATE_DIR=<dir>
set -euo pipefail

STATE_FILE="${NODE_STATE_DIR}/${CHECKPOINT_NAME}.done"

case "${ACTION}" in
  check)
    test -f "${STATE_FILE}" && echo DONE || echo PENDING
    ;;
  mark)
    mkdir -p "${NODE_STATE_DIR}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${STATE_FILE}"
    ;;
  *)
    echo "ERROR: unknown ACTION '${ACTION}'. Use check or mark." >&2
    exit 1
    ;;
esac
