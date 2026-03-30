#!/bin/bash
# Expects: SCRIPT_NAME          — filename inside REMOTE_BOOTSTRAP_DIR
#          LOG_FILE             — absolute path for stdout/stderr
#          PID_FILE             — absolute path to write the background PID
#          REMOTE_BOOTSTRAP_DIR — directory containing the script
# All other exported env vars are inherited by the launched script.
set -euo pipefail

[ -f "${LOG_FILE}" ] && mv "${LOG_FILE}" "${LOG_FILE}.bak"

nohup bash "${REMOTE_BOOTSTRAP_DIR}/${SCRIPT_NAME}" > "${LOG_FILE}" 2>&1 &
echo $! > "${PID_FILE}"
echo "${SCRIPT_NAME} started (PID $(cat "${PID_FILE}"))"
