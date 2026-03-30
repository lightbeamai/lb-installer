#!/bin/bash
# Expects: FILE_CONTENT_B64 — base64-encoded file content
#          REMOTE_PATH       — absolute destination path on the node
set -euo pipefail

printf '%s' "${FILE_CONTENT_B64}" | base64 -d > "${REMOTE_PATH}"
chmod 600 "${REMOTE_PATH}"
chown root:root "${REMOTE_PATH}"

echo ENVFILE_DONE
