#!/bin/bash
# Expects: BUNDLE_B64       — base64-encoded bootstrap tarball
#          REMOTE_BOOTSTRAP_DIR — destination directory on the node
set -euo pipefail

mkdir -p "${REMOTE_BOOTSTRAP_DIR}/cloud" "${REMOTE_BOOTSTRAP_DIR}/os" "${REMOTE_BOOTSTRAP_DIR}/wg-clients"
printf '%s' "${BUNDLE_B64}" | base64 -d > /tmp/bootstrap-bundle.tar.gz
tar -xzf /tmp/bootstrap-bundle.tar.gz -C "${REMOTE_BOOTSTRAP_DIR}"
find "${REMOTE_BOOTSTRAP_DIR}" -name '*.sh' -exec chmod +x {} \;
rm -f /tmp/bootstrap-bundle.tar.gz

echo DEPLOY_DONE
