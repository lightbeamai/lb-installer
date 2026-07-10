#!/usr/bin/env bash
#
# Creates (or reuses) everything a customer's GCP project needs to onboard one or more
# Lightbeam data source types:
#   1. A custom IAM role containing exactly the permissions the selected data source
#      type(s) require — no predefined-role guesswork, no unused permissions.
#   2. A service account (created once, reused on re-runs).
#   3. A binding of that role to that service account, at the ORG level if --org-id is
#      given, or looped across every project in --project-ids otherwise.
#   4. (Google Cloud Storage only) The shared bucket-notification Pub/Sub topic, plus a
#      grant of roles/pubsub.publisher on it to the project's GCS service agent — the
#      same one-time IAM setup that Lightbeam's producer otherwise has to self-heal at
#      runtime (grant_gcs_publisher_permission in aws-s3-extract/app/utils.py), done here
#      up front so live sync works on the very first run.
#   5. A JSON key for the service account, base64-encoded to the format Lightbeam's
#      cloud_platform configuration.serviceAccountKey field expects.
#
# Supported data source types / capabilities (selectable interactively, multiple at once):
#   - Google Cloud Storage (permissions verified against the aws-s3-extract GCS
#     producer/consumer code path: topic + notification + subscription management)
#   - BigQuery (permissions per
#     https://docs.lightbeam.ai/lxqobxw6ak7CTnsQjikH/core-features/spectra-ai/data-sources/databases-and-datalakes/bigquery)
#   - Auto-discovery: read-only permissions for finding scannable GCP resources ahead of
#     onboarding (Cloud SQL, Compute, Datastore, Spanner, buckets, BigQuery datasets), per
#     api-gateway/scripts/setup_gcp_discovery_service_account.sh. Combinable with the data
#     source types above into one service account/role if a single account should cover both.
#
# Idempotent: safe to re-run. Existing role/SA are detected and reused (the role's
# permission list is updated in place, so re-running after adding a data source type
# picks up the new permissions); IAM bindings are naturally idempotent in gcloud, and the
# GCS topic/grant step only creates or grants what's missing.
#
# Requires: gcloud CLI, already authenticated (gcloud auth login) as a principal with
# enough IAM admin rights to create org/project custom roles and service account keys.
# Designed to run as-is in Cloud Shell (gcloud is preinstalled there).
#
# Output: a JSON key file (path you choose, default ./service-account-key.json) and a
# base64-encoded copy next to it (<path>.b64, ready to paste into Lightbeam's
# serviceAccountKey field / Vault). Both are chmod 600. Treat both as secrets — delete
# the local copies once they're safely stored in Vault.

set -euo pipefail

# ---------------------------------------------------------------------------
# Permission sets per supported data source type
# ---------------------------------------------------------------------------
GCS_PERMISSIONS=(
  pubsub.subscriptions.consume
  pubsub.subscriptions.create
  pubsub.subscriptions.get
  pubsub.topics.attachSubscription
  pubsub.topics.create
  pubsub.topics.get
  pubsub.topics.getIamPolicy
  pubsub.topics.setIamPolicy
  storage.buckets.get
  storage.buckets.list
  storage.buckets.update
  storage.objects.get
  storage.objects.list
)

BIGQUERY_PERMISSIONS=(
  bigquery.bireservations.get
  bigquery.capacityCommitments.get
  bigquery.capacityCommitments.list
  bigquery.connections.get
  bigquery.connections.getIamPolicy
  bigquery.connections.list
  bigquery.connections.use
  bigquery.datasets.get
  bigquery.datasets.getIamPolicy
  bigquery.jobs.create
  bigquery.jobs.get
  bigquery.jobs.list
  bigquery.jobs.listAll
  bigquery.jobs.listExecutionMetadata
  bigquery.models.export
  bigquery.models.getData
  bigquery.models.getMetadata
  bigquery.models.list
  bigquery.readsessions.create
  bigquery.readsessions.getData
  bigquery.readsessions.update
  bigquery.reservationAssignments.list
  bigquery.reservationAssignments.search
  bigquery.reservations.get
  bigquery.reservations.list
  bigquery.routines.get
  bigquery.routines.list
  bigquery.rowAccessPolicies.getFilteredData
  bigquery.tables.createSnapshot
  bigquery.tables.export
  bigquery.tables.get
  bigquery.tables.getData
  bigquery.tables.getIamPolicy
  bigquery.tables.list
  resourcemanager.projects.get
)

# Read-only permissions for Lightbeam's GCP resource discovery (finding scannable
# resources — Cloud SQL, Compute, Datastore, Spanner, buckets, BigQuery datasets — ahead
# of onboarding any specific data source), matching api-gateway/scripts/setup_gcp_discovery_service_account.sh.
DISCOVERY_PERMISSIONS=(
  bigquery.datasets.get
  cloudsql.instances.get
  cloudsql.instances.list
  compute.instances.get
  compute.instances.list
  compute.regions.list
  compute.zones.list
  datastore.databases.list
  resourcemanager.projects.get
  spanner.instances.list
  storage.buckets.get
  storage.buckets.list
)

command -v gcloud >/dev/null 2>&1 || { echo "ERROR: gcloud CLI not found on PATH."; exit 1; }

# This script is interactive, so it needs to read prompts from the terminal even when
# invoked as `curl ... | bash` — in that case bash's own stdin is the pipe carrying the
# rest of the script source, not the keyboard, so every `read` below is pinned to
# /dev/tty instead of plain stdin. Fail fast with a clear message if there's no
# controlling terminal to read from (e.g. running non-interactively in CI).
if [[ ! -r /dev/tty ]]; then
  echo "ERROR: this script is interactive and needs a terminal (/dev/tty) to read your" >&2
  echo "answers from — it can't run non-interactively (e.g. piped in CI)." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Interactive prompts
# ---------------------------------------------------------------------------
# prompt VAR "question text" ["default"]
# Blank default means the field is required and re-prompts until non-empty.
prompt() {
  local __var_name="$1" __question="$2" __default="${3:-}" __input
  if [[ -n "$__default" ]]; then
    read -r -p "$__question [$__default]: " __input < /dev/tty
    __input="${__input:-$__default}"
  else
    while [[ -z "${__input:-}" ]]; do
      read -r -p "$__question: " __input < /dev/tty
      [[ -z "$__input" ]] && echo "  This field is required."
    done
  fi
  printf -v "$__var_name" '%s' "$__input"
}

echo "================================================================================"
echo "Lightbeam GCP data source service account setup"
echo "================================================================================"
echo "This walks through picking which Lightbeam GCP data source type(s) you're"
echo "onboarding, then creates a custom IAM role, a service account, binds them"
echo "together (org-wide or per-project), and generates a key for Lightbeam to use."
echo

# ---------------------------------------------------------------------------
# Data source selection — builds the deduped union of required permissions
# ---------------------------------------------------------------------------
declare -A seen_permission
PERMISSIONS=()
SELECTED_LABELS=()

add_permissions() {
  local perm
  for perm in "$@"; do
    if [[ -z "${seen_permission[$perm]:-}" ]]; then
      seen_permission[$perm]=1
      PERMISSIONS+=("$perm")
    fi
  done
}

echo "Which Lightbeam data source type(s) / capabilities is this service account for?"
echo "  1) Google Cloud Storage"
echo "  2) BigQuery"
echo "  3) Auto-discovery (read-only GCP resource discovery)"
while [[ ${#SELECTED_LABELS[@]} -eq 0 ]]; do
  read -r -p "Enter comma-separated numbers (e.g. 1,2): " ds_choice < /dev/tty
  IFS=',' read -r -a ds_selections <<< "$ds_choice"
  for selection in "${ds_selections[@]}"; do
    selection="$(echo "$selection" | tr -d '[:space:]')"
    case "$selection" in
      1)
        add_permissions "${GCS_PERMISSIONS[@]}"
        SELECTED_LABELS+=("cloud-storage")
        ;;
      2)
        add_permissions "${BIGQUERY_PERMISSIONS[@]}"
        SELECTED_LABELS+=("bigquery")
        ;;
      3)
        add_permissions "${DISCOVERY_PERMISSIONS[@]}"
        SELECTED_LABELS+=("auto-discovery")
        ;;
      *)
        echo "  Ignoring unrecognized option '$selection'."
        ;;
    esac
  done
  [[ ${#SELECTED_LABELS[@]} -eq 0 ]] && echo "  Select at least one valid option."
done

LABELS_JOINED=$(IFS=+; echo "${SELECTED_LABELS[*]}")
ROLE_TITLE="Lightbeam ${LABELS_JOINED}"
ROLE_DESCRIPTION="Lightbeam data source access for: ${SELECTED_LABELS[*]}."

# GCP service account IDs must be 6-30 chars, lowercase letters/digits/hyphens only, and
# can't end in a hyphen ('+' from LABELS_JOINED is invalid, and joining 2-3 labels easily
# blows past 30 chars) — so build the default separately: hyphen-joined, then truncated
# and trimmed of any trailing hyphen left by the cut.
SA_LABELS_JOINED=$(IFS=-; echo "${SELECTED_LABELS[*]}")
DEFAULT_SA_NAME="lightbeam-${SA_LABELS_JOINED}"
DEFAULT_SA_NAME="${DEFAULT_SA_NAME:0:30}"
DEFAULT_SA_NAME="${DEFAULT_SA_NAME%-}"

# Builds a camelCase role ID suffix from hyphen/plus-delimited labels (e.g.
# "cloud-storage+bigquery" -> "CloudStorageBigquery") using only portable
# bash/tr, since sed's \U case-conversion is a GNU extension that silently no-ops on
# BSD/macOS sed.
build_role_id_suffix() {
  local joined="$1" word first rest result=""
  local IFS='+-'
  read -r -a words <<< "$joined"
  for word in "${words[@]}"; do
    first="$(printf '%s' "${word:0:1}" | tr '[:lower:]' '[:upper:]')"
    rest="${word:1}"
    result+="${first}${rest}"
  done
  printf '%s' "$result"
}
DEFAULT_ROLE_ID="lightbeam$(build_role_id_suffix "$LABELS_JOINED")"

# Offer the gcloud CLI's currently configured project as the default, if one is set
# (gcloud prints the literal string "(unset)" instead of failing when it isn't).
DETECTED_SA_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
[[ "$DETECTED_SA_PROJECT" == "(unset)" ]] && DETECTED_SA_PROJECT=""
prompt SA_PROJECT "GCP project ID to host the service account" "$DETECTED_SA_PROJECT"
prompt SA_NAME "Service account name" "$DEFAULT_SA_NAME"
prompt ROLE_ID "Custom IAM role ID" "$DEFAULT_ROLE_ID"

TOPIC_PROJECT=""
TOPIC_NAME=""
if [[ " ${SELECTED_LABELS[*]} " == *" cloud-storage "* ]]; then
  prompt TOPIC_PROJECT "GCP project ID hosting the GCS bucket-notification Pub/Sub topic" "$SA_PROJECT"
  prompt TOPIC_NAME "Pub/Sub topic name used for GCS bucket notifications" "gc-storage-publisher-topic"
fi

# Walks the project's resource hierarchy (project -> folder(s) -> organization) to find
# the organization ID that owns it, so we can offer it as a confirmable default instead
# of making the user look it up by hand. Prints nothing (and the caller falls back to a
# required prompt) if there's no access or the project has no organization ancestor.
detect_org_id() {
  local project="$1"
  gcloud projects get-ancestors "$project" --format="value(id,type)" 2>/dev/null \
    | awk '$2 == "organization" { print $1; exit }'
}

ORG_ID=""
PROJECT_IDS=()
read -r -p "Do you have org-level IAM access to bind the role once at the org? [y/N] " has_org < /dev/tty
if [[ "$has_org" =~ ^[Yy]$ ]]; then
  echo "Looking up the organization that owns project ${SA_PROJECT}..."
  DETECTED_ORG_ID="$(detect_org_id "$SA_PROJECT")"
  if [[ -n "$DETECTED_ORG_ID" ]]; then
    prompt ORG_ID "GCP organization ID" "$DETECTED_ORG_ID"
  else
    echo "  Couldn't auto-detect one (no access to view ancestors, or no org ancestor) — enter it manually."
    prompt ORG_ID "GCP organization ID"
  fi
else
  echo "No org-level access — the role will be bound on each project individually instead."
  while [[ ${#PROJECT_IDS[@]} -eq 0 ]]; do
    read -r -p "Comma-separated project IDs to bind the role to: " project_ids_input < /dev/tty
    if [[ -n "$project_ids_input" ]]; then
      IFS=',' read -r -a PROJECT_IDS <<< "$project_ids_input"
    else
      echo "  At least one project ID is required."
    fi
  done
fi

prompt KEY_OUTPUT_FILE "Path to write the JSON key to" "service-account-key.json"
ENCODED_OUTPUT_FILE="${KEY_OUTPUT_FILE}.b64"

DRY_RUN=false
read -r -p "Dry run only — print the gcloud commands without making any changes? [y/N] " dry_run_answer < /dev/tty
[[ "$dry_run_answer" =~ ^[Yy]$ ]] && DRY_RUN=true

# Prints the command instead of running it when dry-run was chosen. Only wraps mutating
# gcloud calls — the read-only "describe" checks below always run for real so the
# create-vs-update branching reflects actual state.
run() {
  if $DRY_RUN; then
    echo "[DRY RUN] would run: $*"
  else
    "$@"
  fi
}

# Retries a command a few times with backoff. Used around the IAM policy binding below:
# a freshly-created service account is visible to the IAM API immediately but can take a
# few seconds to propagate to the Resource Manager API that add-iam-policy-binding hits,
# so the very next binding call can fail with "Service account ... does not exist" even
# though the SA was just created successfully.
retry() {
  local attempt max_attempts=6 delay=5
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    "$@" && return 0
    if (( attempt < max_attempts )); then
      echo "  (attempt ${attempt}/${max_attempts} failed — likely IAM propagation delay, retrying in ${delay}s...)"
      sleep "$delay"
    fi
  done
  return 1
}

SA_EMAIL="${SA_NAME}@${SA_PROJECT}.iam.gserviceaccount.com"

echo "================================================================================"
$DRY_RUN && echo "[DRY RUN] Nothing below will actually be created/modified."
echo "About to set up GCP data source access with the following gcloud identity:"
gcloud config get-value account 2>/dev/null || true
echo "--------------------------------------------------------------------------------"
echo "  Data source type(s):  ${SELECTED_LABELS[*]}"
echo "  Custom role:          ${ROLE_ID} (scope: $( [[ -n "$ORG_ID" ]] && echo "organization ${ORG_ID}" || echo "projects: ${PROJECT_IDS[*]}" ))"
echo "  Service account:      ${SA_EMAIL} (hosted in project ${SA_PROJECT})"
echo "  Permissions (${#PERMISSIONS[@]}): ${PERMISSIONS[*]}"
if [[ -n "$TOPIC_NAME" ]]; then
  echo "  GCS notification topic: ${TOPIC_NAME} (project ${TOPIC_PROJECT}) — will grant the GCS service agent roles/pubsub.publisher"
fi
echo "  Key output:           ${KEY_OUTPUT_FILE} (+ base64 at ${ENCODED_OUTPUT_FILE})"
echo "================================================================================"
if ! $DRY_RUN; then
  read -r -p "Proceed? [y/N] " confirm < /dev/tty
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# ---------------------------------------------------------------------------
# 1. Custom role — org-level or per-project
# ---------------------------------------------------------------------------
PERMISSIONS_CSV=$(IFS=,; echo "${PERMISSIONS[*]}")

create_or_update_role() {
  local scope_flag="$1"   # e.g. "--organization=123" or "--project=my-proj"
  local describe_flag="$2"

  if gcloud iam roles describe "$ROLE_ID" $describe_flag >/dev/null 2>&1; then
    echo "Role ${ROLE_ID} already exists ($scope_flag) — updating its permission list."
    run gcloud iam roles update "$ROLE_ID" $scope_flag \
      --title="$ROLE_TITLE" \
      --description="$ROLE_DESCRIPTION" \
      --permissions="$PERMISSIONS_CSV" \
      --stage=GA
  else
    echo "Creating role ${ROLE_ID} ($scope_flag)."
    run gcloud iam roles create "$ROLE_ID" $scope_flag \
      --title="$ROLE_TITLE" \
      --description="$ROLE_DESCRIPTION" \
      --permissions="$PERMISSIONS_CSV" \
      --stage=GA
  fi
}

if [[ -n "$ORG_ID" ]]; then
  create_or_update_role "--organization=${ORG_ID}" "--organization=${ORG_ID}"
  ROLE_RESOURCE="organizations/${ORG_ID}/roles/${ROLE_ID}"
else
  for project_id in "${PROJECT_IDS[@]}"; do
    create_or_update_role "--project=${project_id}" "--project=${project_id}"
  done
fi

# ---------------------------------------------------------------------------
# 2. Service account — create once, reuse thereafter
# ---------------------------------------------------------------------------
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$SA_PROJECT" >/dev/null 2>&1; then
  echo "Service account ${SA_EMAIL} already exists — reusing it."
else
  echo "Creating service account ${SA_EMAIL}."
  run gcloud iam service-accounts create "$SA_NAME" \
    --project="$SA_PROJECT" \
    --display-name="Lightbeam ${LABELS_JOINED}"
fi

# ---------------------------------------------------------------------------
# 3. Bind the role to the service account
# ---------------------------------------------------------------------------
if [[ -n "$ORG_ID" ]]; then
  echo "Binding ${ROLE_RESOURCE} to ${SA_EMAIL} at organization ${ORG_ID}."
  retry run gcloud organizations add-iam-policy-binding "$ORG_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${ROLE_RESOURCE}" \
    --condition=None
else
  for project_id in "${PROJECT_IDS[@]}"; do
    echo "Binding projects/${project_id}/roles/${ROLE_ID} to ${SA_EMAIL} on project ${project_id}."
    retry run gcloud projects add-iam-policy-binding "$project_id" \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="projects/${project_id}/roles/${ROLE_ID}" \
      --condition=None
  done
fi

# ---------------------------------------------------------------------------
# 4. (Google Cloud Storage only) Ensure the shared bucket-notification topic exists
#    and grant the project's GCS service agent publish rights on it — mirrors
#    grant_gcs_publisher_permission's runtime self-heal (aws-s3-extract/app/utils.py),
#    done here up front so live sync works on the very first run.
# ---------------------------------------------------------------------------
# Looks up the GCS service agent email for a project via the same Cloud Storage REST
# endpoint Lightbeam's own runtime code calls (storage.Client.get_service_account_email
# in aws-s3-extract/app/utils.py), so the two stay consistent.
gcs_service_agent_email() {
  local project="$1"
  curl -sf -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    "https://storage.googleapis.com/storage/v1/projects/${project}/serviceAccount" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["email_address"])'
}

if [[ -n "$TOPIC_NAME" ]]; then
  echo "Ensuring Pub/Sub topic '${TOPIC_NAME}' exists in project ${TOPIC_PROJECT}."
  if gcloud pubsub topics describe "$TOPIC_NAME" --project="$TOPIC_PROJECT" >/dev/null 2>&1; then
    echo "Topic ${TOPIC_NAME} already exists."
  else
    run gcloud pubsub topics create "$TOPIC_NAME" --project="$TOPIC_PROJECT"
  fi

  echo "Looking up the GCS service agent for project ${TOPIC_PROJECT}."
  GCS_SERVICE_AGENT="$(gcs_service_agent_email "$TOPIC_PROJECT")"
  echo "Granting roles/pubsub.publisher on ${TOPIC_NAME} to ${GCS_SERVICE_AGENT}."
  # gcloud's own add-iam-policy-binding dedupes existing (role, member) pairs, so this
  # is safe to re-run without accumulating duplicate bindings.
  run gcloud pubsub topics add-iam-policy-binding "$TOPIC_NAME" \
    --project="$TOPIC_PROJECT" \
    --member="serviceAccount:${GCS_SERVICE_AGENT}" \
    --role="roles/pubsub.publisher"
fi

# ---------------------------------------------------------------------------
# 5. Key creation + base64 encoding (matches configuration["serviceAccountKey"] format)
# ---------------------------------------------------------------------------
if $DRY_RUN; then
  echo "[DRY RUN] would run: gcloud iam service-accounts keys create ${KEY_OUTPUT_FILE} --iam-account=${SA_EMAIL} --project=${SA_PROJECT}"
  echo "[DRY RUN] would then base64-encode ${KEY_OUTPUT_FILE} into ${ENCODED_OUTPUT_FILE} (chmod 600 both)."
  echo "================================================================================"
  echo "[DRY RUN] complete — nothing was created or modified. Re-run without --dry-run to apply."
  echo "================================================================================"
  exit 0
fi

echo "Creating a new JSON key for ${SA_EMAIL}."
gcloud iam service-accounts keys create "$KEY_OUTPUT_FILE" \
  --iam-account="$SA_EMAIL" \
  --project="$SA_PROJECT"
chmod 600 "$KEY_OUTPUT_FILE"

# base64 wraps output differently on GNU vs BSD/macOS; stripping newlines makes it portable.
base64 < "$KEY_OUTPUT_FILE" | tr -d '\n' > "$ENCODED_OUTPUT_FILE"
chmod 600 "$ENCODED_OUTPUT_FILE"

echo "================================================================================"
echo "Done."
echo "  Data source type(s): ${SELECTED_LABELS[*]}"
echo "  Service account:     ${SA_EMAIL}"
echo "  Raw key:              ${KEY_OUTPUT_FILE}"
echo "  Base64 key:           ${ENCODED_OUTPUT_FILE}  <- paste this into serviceAccountKey"
echo ""
echo "Both files are chmod 600 and contain a live credential. Move the base64 content"
echo "into Vault (or wherever this platform's configuration is stored) and then delete"
echo "both local files — don't leave long-lived keys sitting on disk."
echo "================================================================================"
