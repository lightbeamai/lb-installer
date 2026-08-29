#!/bin/bash
# ============================================================
# LightBeam AKS Backup — Native Azure Backup (DataProtection)
# Uses: Azure Backup Extension + Backup Vault + az CLI
# Run from Azure Cloud Shell (bash)
# Reference: https://learn.microsoft.com/en-us/azure/backup/azure-kubernetes-service-cluster-backup
# ============================================================

set -euo pipefail

# ─────────────────────────────────────────────
# COLORS & HELPERS
# ─────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header()  { echo -e "\n${CYAN}${BOLD}── $* ──${NC}"; }
die()     { error "$*"; exit 1; }
require() { command -v "$1" &>/dev/null || die "Required tool '$1' not found. Please run from Azure Cloud Shell."; }

# ─────────────────────────────────────────────
# PROMPT HELPER — ask with a default value
# Usage: prompt_input "Label" "default_value" VAR_NAME
# ─────────────────────────────────────────────
prompt_input() {
    local label="$1" default="$2" varname="$3"
    local current="${!varname:-}"
    if [[ -n "$current" ]]; then
        info "${label} already set to: ${current}"
        return
    fi
    if [[ -n "$default" ]]; then
        read -rp "  ${label} [${default}]: " value
        value="${value:-$default}"
    else
        read -rp "  ${label} (required): " value
        while [[ -z "$value" ]]; do
            read -rp "  ${label} cannot be empty. Enter value: " value
        done
    fi
    printf -v "$varname" '%s' "$value"
}

# ─────────────────────────────────────────────
# STEP 0 — COLLECT USER INPUTS
# ─────────────────────────────────────────────
collect_inputs() {
    header "AKS Azure Backup Configuration"
    echo -e "  Press ${BOLD}Enter${NC} to accept the default shown in [brackets].\n"

    # ── Azure context ──────────────────────────
    echo -e "${BOLD}Azure Subscription & Location${NC}"

    # Show available subscriptions
    echo ""
    info "Available subscriptions:"
    az account list --query '[].{Name:name, SubscriptionId:id, Default:isDefault}' -o table 2>/dev/null || true
    echo ""
    prompt_input "Subscription ID (leave blank to use current default)" \
        "$(az account list --query '[?isDefault].id' -o tsv 2>/dev/null || true)" \
        SUBSCRIPTION_ID

    az account set --subscription "$SUBSCRIPTION_ID" \
        || die "Could not set subscription to '${SUBSCRIPTION_ID}'."

    prompt_input "Azure region for Backup Vault & storage (e.g. eastus, westus, westeurope)" \
        "eastus" LOCATION

    # ── AKS cluster ───────────────────────────
    echo -e "\n${BOLD}AKS Cluster${NC}"
    echo ""
    info "Available AKS clusters in subscription:"
    az aks list --query '[].{Name:name, ResourceGroup:resourceGroup, Location:location}' -o table 2>/dev/null || warn "Could not list AKS clusters."
    echo ""
    prompt_input "AKS cluster name"                      ""         AKS_CLUSTER_NAME
    prompt_input "AKS cluster resource group"             ""         AKS_CLUSTER_RG

    # Auto-detect AKS node resource group (MC_... group)
    if [[ -z "${AKS_NODE_RG:-}" ]]; then
        AKS_NODE_RG=$(az aks show \
            --name "$AKS_CLUSTER_NAME" \
            --resource-group "$AKS_CLUSTER_RG" \
            --query nodeResourceGroup -o tsv 2>/dev/null || true)
    fi
    if [[ -n "$AKS_NODE_RG" ]]; then
        info "Auto-detected AKS node resource group: ${AKS_NODE_RG}"
    else
        prompt_input "AKS node resource group (MC_... group)" "" AKS_NODE_RG
    fi

    # ── Backup Vault ──────────────────────────
    echo -e "\n${BOLD}Backup Vault${NC}"
    prompt_input "Backup Vault name"           "lb-backup-vault"       VAULT_NAME
    prompt_input "Backup Vault resource group" "${AKS_CLUSTER_RG}"     VAULT_RG

    # ── Storage (for Backup Extension) ────────
    echo -e "\n${BOLD}Storage Account & Blob Container${NC}"
    echo -e "  ${YELLOW}Note: Must be in the same region and subscription as the AKS cluster.${NC}"
    prompt_input "Storage account name for backups (globally unique, lowercase, 3-24 chars)" \
        "lbaksbackup$(echo "$RANDOM" | md5sum | head -c6)" STORAGE_ACCOUNT_NAME
    prompt_input "Storage account resource group" "${AKS_CLUSTER_RG}" STORAGE_RG
    prompt_input "Blob container name"             "aks-backup"         BLOB_CONTAINER

    # ── Snapshot resource group ───────────────
    echo -e "\n${BOLD}Snapshot Resource Group${NC}"
    echo -e "  ${YELLOW}PVC (persistent volume) snapshots will be stored here.${NC}"
    prompt_input "Snapshot resource group name" "lb-aks-snapshots" SNAPSHOT_RG

    # ── Backup policy ─────────────────────────
    echo -e "\n${BOLD}Backup Policy${NC}"
    prompt_input "Backup policy name"      "lb-aks-backup-policy"  POLICY_NAME
    prompt_input "Backup frequency (Daily/Hourly)"  "Daily"        BACKUP_FREQUENCY
    prompt_input "Backup retention in days (1–360)" "30"           RETENTION_DAYS
    prompt_input "Backup instance friendly name"    "${AKS_CLUSTER_NAME}-backup" FRIENDLY_NAME

    # ── Namespace scope ───────────────────────
    echo -e "\n${BOLD}Namespace Scope${NC}"
    echo -e "  Leave blank to back up ${BOLD}all${NC} namespaces."
    echo -e "  Or enter comma-separated list, e.g.: default,monitoring,lightbeam"
    prompt_input "Namespaces to include (blank = all)" "" INCLUDE_NAMESPACES

    # ── Volume type ───────────────────────────
    echo -e "\n${BOLD}Volume Types${NC}"
    echo -e "  Options: AzureDisk | AzureFileShareCSIDriver | all"
    prompt_input "Volume types to back up" "AzureDisk" VOLUME_TYPES

    # ── On-demand backup ──────────────────────
    echo -e "\n${BOLD}On-Demand Backup${NC}"
    read -rp "  Trigger an on-demand backup after configuration? [Y/n]: " RUN_ADHOC
    RUN_ADHOC="${RUN_ADHOC:-Y}"

    echo ""
    header "Configuration Summary"
    echo -e "  Subscription          : ${SUBSCRIPTION_ID}"
    echo -e "  Region                : ${LOCATION}"
    echo -e "  AKS Cluster           : ${AKS_CLUSTER_NAME} (RG: ${AKS_CLUSTER_RG})"
    echo -e "  AKS Node RG           : ${AKS_NODE_RG}"
    echo -e "  Backup Vault          : ${VAULT_NAME} (RG: ${VAULT_RG})"
    echo -e "  Storage Account       : ${STORAGE_ACCOUNT_NAME} (RG: ${STORAGE_RG})"
    echo -e "  Blob Container        : ${BLOB_CONTAINER}"
    echo -e "  Snapshot RG           : ${SNAPSHOT_RG}"
    echo -e "  Policy                : ${POLICY_NAME} | ${BACKUP_FREQUENCY} | Retain ${RETENTION_DAYS} days"
    echo -e "  Namespaces            : ${INCLUDE_NAMESPACES:-ALL}"
    echo -e "  Volume types          : ${VOLUME_TYPES}"
    echo -e "  On-demand backup      : ${RUN_ADHOC}"
    echo ""
    read -rp "  Proceed with these settings? [Y/n]: " CONFIRM
    CONFIRM="${CONFIRM:-Y}"
    [[ "${CONFIRM,,}" == "y" ]] || die "Aborted by user."
}

# ─────────────────────────────────────────────
# STEP 1 — VALIDATE PERMISSIONS
# ─────────────────────────────────────────────
validate_permissions() {
    header "Validating Permissions"

    CURRENT_USER=$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null \
        || az account show --query user.name -o tsv 2>/dev/null \
        || echo "unknown")
    info "Authenticated as: ${CURRENT_USER}"

    # Check Contributor/Owner at subscription scope
    ROLES=$(az role assignment list \
        --assignee "$CURRENT_USER" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}" \
        --query '[].roleDefinitionName' -o tsv 2>/dev/null || true)

    HAS_PERM=false
    for role in $ROLES; do
        if [[ "$role" == "Contributor" || "$role" == "Owner" ]]; then
            HAS_PERM=true; break
        fi
    done

    if [[ "$HAS_PERM" != "true" ]]; then
        warn "No Contributor/Owner at subscription scope. Checking cluster resource group..."
        RG_ROLES=$(az role assignment list \
            --assignee "$CURRENT_USER" \
            --resource-group "$AKS_CLUSTER_RG" \
            --query '[].roleDefinitionName' -o tsv 2>/dev/null || true)
        for role in $RG_ROLES; do
            if [[ "$role" == "Contributor" || "$role" == "Owner" ]]; then
                HAS_PERM=true; break
            fi
        done
        [[ "$HAS_PERM" == "true" ]] || die "Insufficient permissions. Contributor or Owner role required on subscription or resource group '${AKS_CLUSTER_RG}'."
    fi
    info "Permission check passed."
}

# ─────────────────────────────────────────────
# STEP 2 — REGISTER RESOURCE PROVIDERS
# ─────────────────────────────────────────────
register_providers() {
    header "Registering Required Resource Providers"
    local providers=("Microsoft.KubernetesConfiguration" "Microsoft.DataProtection" "Microsoft.ContainerService")
    for provider in "${providers[@]}"; do
        STATE=$(az provider show --namespace "$provider" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$STATE" == "Registered" ]]; then
            info "${provider}: already registered."
        else
            info "Registering ${provider}..."
            az provider register --namespace "$provider" --wait
            info "${provider}: registered."
        fi
    done
}

# ─────────────────────────────────────────────
# STEP 3 — CREATE STORAGE ACCOUNT & CONTAINER
# ─────────────────────────────────────────────
create_storage() {
    header "Setting Up Storage Account"

    # Create storage RG if needed
    az group create -n "$STORAGE_RG" --location "$LOCATION" -o none
    info "Resource group '${STORAGE_RG}' ready."

    if az storage account show --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$STORAGE_RG" &>/dev/null; then
        info "Storage account '${STORAGE_ACCOUNT_NAME}' already exists."
    else
        info "Creating storage account '${STORAGE_ACCOUNT_NAME}'..."
        az storage account create \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$STORAGE_RG" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --encryption-services blob \
            --https-only true \
            --kind StorageV2 \
            -o none
        info "Storage account created."
    fi

    if az storage container show \
        --name "$BLOB_CONTAINER" \
        --account-name "$STORAGE_ACCOUNT_NAME" &>/dev/null 2>&1; then
        info "Blob container '${BLOB_CONTAINER}' already exists."
    else
        info "Creating blob container '${BLOB_CONTAINER}'..."
        az storage container create \
            -n "$BLOB_CONTAINER" \
            --public-access off \
            --account-name "$STORAGE_ACCOUNT_NAME" \
            -o none
        info "Blob container created."
    fi

    export STORAGE_ACCOUNT_ID
    STORAGE_ACCOUNT_ID=$(az storage account show \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$STORAGE_RG" \
        --query id -o tsv)
}

# ─────────────────────────────────────────────
# STEP 4 — CREATE SNAPSHOT RESOURCE GROUP
# ─────────────────────────────────────────────
create_snapshot_rg() {
    header "Setting Up Snapshot Resource Group"
    az group create -n "$SNAPSHOT_RG" --location "$LOCATION" -o none
    info "Snapshot resource group '${SNAPSHOT_RG}' ready."

    SNAPSHOT_RG_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${SNAPSHOT_RG}"
    export SNAPSHOT_RG_ID
}

# ─────────────────────────────────────────────
# STEP 5 — INSTALL BACKUP EXTENSION ON AKS
# ─────────────────────────────────────────────
install_backup_extension() {
    header "Installing AKS Backup Extension"

    EXT_STATE=$(az k8s-extension show \
        --name azure-aks-backup \
        --cluster-type managedClusters \
        --cluster-name "$AKS_CLUSTER_NAME" \
        --resource-group "$AKS_CLUSTER_RG" \
        --query "provisioningState" -o tsv 2>/dev/null || echo "NotInstalled")

    if [[ "$EXT_STATE" == "Succeeded" ]]; then
        info "Backup Extension already installed and provisioned."
    else
        info "Installing Backup Extension (this may take a few minutes)..."
        az k8s-extension create \
            --name azure-aks-backup \
            --extension-type microsoft.dataprotection.kubernetes \
            --scope cluster \
            --cluster-type managedClusters \
            --cluster-name "$AKS_CLUSTER_NAME" \
            --resource-group "$AKS_CLUSTER_RG" \
            --release-train stable \
            --configuration-settings \
                blobContainer="$BLOB_CONTAINER" \
                storageAccount="$STORAGE_ACCOUNT_NAME" \
                storageAccountResourceGroup="$STORAGE_RG" \
                storageAccountSubscriptionId="$SUBSCRIPTION_ID"

        # Wait for extension to provision
        info "Waiting for extension to reach Succeeded state..."
        for i in $(seq 1 24); do
            STATE=$(az k8s-extension show \
                --name azure-aks-backup \
                --cluster-type managedClusters \
                --cluster-name "$AKS_CLUSTER_NAME" \
                --resource-group "$AKS_CLUSTER_RG" \
                --query "provisioningState" -o tsv 2>/dev/null || echo "Unknown")
            info "Extension state: ${STATE} (attempt ${i}/24)"
            [[ "$STATE" == "Succeeded" ]] && break
            [[ "$STATE" == "Failed" ]]    && die "Backup Extension installation failed. Check portal for details."
            sleep 15
        done
        [[ "$STATE" != "Succeeded" ]] && die "Backup Extension did not reach Succeeded state in time."
        info "Backup Extension installed successfully."
    fi
}

# ─────────────────────────────────────────────
# STEP 6 — GRANT STORAGE BLOB DATA CONTRIBUTOR
#          TO EXTENSION MANAGED IDENTITY
# ─────────────────────────────────────────────
grant_storage_permission() {
    header "Granting Storage Permission to Backup Extension Identity"

    EXT_PRINCIPAL=$(az k8s-extension show \
        --name azure-aks-backup \
        --cluster-name "$AKS_CLUSTER_NAME" \
        --resource-group "$AKS_CLUSTER_RG" \
        --cluster-type managedClusters \
        --query aksAssignedIdentity.principalId -o tsv 2>/dev/null || true)

    if [[ -z "$EXT_PRINCIPAL" ]]; then
        warn "Could not retrieve extension managed identity principal ID. Skipping role assignment."
        warn "Manually run: az role assignment create --assignee-object-id <principalId> --role 'Storage Blob Data Contributor' --scope ${STORAGE_ACCOUNT_ID}"
        return
    fi

    info "Extension managed identity principal: ${EXT_PRINCIPAL}"

    EXISTING=$(az role assignment list \
        --assignee "$EXT_PRINCIPAL" \
        --scope "$STORAGE_ACCOUNT_ID" \
        --query "[?roleDefinitionName=='Storage Blob Data Contributor'].id" -o tsv 2>/dev/null || true)

    if [[ -n "$EXISTING" ]]; then
        info "Storage Blob Data Contributor already assigned."
    else
        az role assignment create \
            --assignee-object-id "$EXT_PRINCIPAL" \
            --assignee-principal-type ServicePrincipal \
            --role "Storage Blob Data Contributor" \
            --scope "$STORAGE_ACCOUNT_ID" \
            -o none
        info "Storage Blob Data Contributor role assigned."
    fi
}

# ─────────────────────────────────────────────
# STEP 7 — CREATE BACKUP VAULT
# ─────────────────────────────────────────────
create_backup_vault() {
    header "Creating Backup Vault"

    az group create -n "$VAULT_RG" --location "$LOCATION" -o none

    VAULT_EXISTS=$(az dataprotection backup-vault list \
        --resource-group "$VAULT_RG" \
        --query "[?name=='${VAULT_NAME}'].name" -o tsv 2>/dev/null || true)

    if [[ -n "$VAULT_EXISTS" ]]; then
        info "Backup Vault '${VAULT_NAME}' already exists."
    else
        info "Creating Backup Vault '${VAULT_NAME}'..."
        az dataprotection backup-vault create \
            --resource-group "$VAULT_RG" \
            --vault-name "$VAULT_NAME" \
            --location "$LOCATION" \
            --type SystemAssigned \
            --storage-settings datastore-type="OperationalStore" type="LocallyRedundant" \
            -o none
        info "Backup Vault created."
    fi

    VAULT_ID=$(az dataprotection backup-vault show \
        --resource-group "$VAULT_RG" \
        --vault-name "$VAULT_NAME" \
        --query id -o tsv)

    VAULT_PRINCIPAL=$(az dataprotection backup-vault show \
        --resource-group "$VAULT_RG" \
        --vault-name "$VAULT_NAME" \
        --query identity.principalId -o tsv 2>/dev/null || true)

    export VAULT_ID VAULT_PRINCIPAL
    info "Vault ID: ${VAULT_ID}"
    info "Vault MSI principal: ${VAULT_PRINCIPAL}"
}

# ─────────────────────────────────────────────
# STEP 8 — ENABLE TRUSTED ACCESS
# ─────────────────────────────────────────────
enable_trusted_access() {
    header "Enabling Trusted Access (Backup Vault ↔ AKS)"

    BINDING_NAME="lb-backup-trusted-access"

    EXISTING_BINDING=$(az aks trustedaccess rolebinding list \
        --resource-group "$AKS_CLUSTER_RG" \
        --cluster-name "$AKS_CLUSTER_NAME" \
        --query "[?name=='${BINDING_NAME}'].name" -o tsv 2>/dev/null || true)

    if [[ -n "$EXISTING_BINDING" ]]; then
        info "Trusted Access role binding already exists."
    else
        info "Creating Trusted Access role binding..."
        az aks trustedaccess rolebinding create \
            --resource-group "$AKS_CLUSTER_RG" \
            --cluster-name "$AKS_CLUSTER_NAME" \
            --name "$BINDING_NAME" \
            --source-resource-id "$VAULT_ID" \
            --roles Microsoft.DataProtection/backupVaults/backup-operator
        info "Trusted Access enabled."
    fi
}

# ─────────────────────────────────────────────
# STEP 9 — GRANT VAULT MSI PERMISSIONS
#   • Contributor on AKS cluster
#   • Contributor on snapshot RG
#   • Storage Blob Data Contributor on storage account
# ─────────────────────────────────────────────
grant_vault_permissions() {
    header "Granting Vault Managed Identity Permissions"

    if [[ -z "$VAULT_PRINCIPAL" ]]; then
        warn "Vault MSI principal not found — skipping role assignments."
        warn "Assign roles manually: Contributor on AKS, snapshot RG, and storage account."
        return
    fi

    AKS_ID=$(az aks show \
        --name "$AKS_CLUSTER_NAME" \
        --resource-group "$AKS_CLUSTER_RG" \
        --query id -o tsv)

    # Helper: assign role if not already assigned
    assign_role() {
        local principal="$1" role="$2" scope="$3" desc="$4"
        EXISTING=$(az role assignment list \
            --assignee "$principal" \
            --scope "$scope" \
            --query "[?roleDefinitionName=='${role}'].id" -o tsv 2>/dev/null || true)
        if [[ -n "$EXISTING" ]]; then
            info "${role} on ${desc}: already assigned."
        else
            az role assignment create \
                --assignee-object-id "$principal" \
                --assignee-principal-type ServicePrincipal \
                --role "$role" \
                --scope "$scope" \
                -o none
            info "${role} on ${desc}: assigned."
        fi
    }

    assign_role "$VAULT_PRINCIPAL" "Contributor"                   "$AKS_ID"             "AKS cluster"
    assign_role "$VAULT_PRINCIPAL" "Contributor"                   "$SNAPSHOT_RG_ID"     "snapshot resource group"
    assign_role "$VAULT_PRINCIPAL" "Storage Blob Data Contributor" "$STORAGE_ACCOUNT_ID" "storage account"

    # AKS cluster also needs Contributor on snapshot RG
    AKS_PRINCIPAL=$(az aks show \
        --name "$AKS_CLUSTER_NAME" \
        --resource-group "$AKS_CLUSTER_RG" \
        --query identity.principalId -o tsv 2>/dev/null || true)
    if [[ -n "$AKS_PRINCIPAL" ]]; then
        assign_role "$AKS_PRINCIPAL" "Contributor" "$SNAPSHOT_RG_ID" "snapshot RG (AKS identity)"
    fi
}

# ─────────────────────────────────────────────
# STEP 10 — CREATE BACKUP POLICY
# ─────────────────────────────────────────────
create_backup_policy() {
    header "Creating Backup Policy"

    EXISTING_POLICY=$(az dataprotection backup-policy list \
        --resource-group "$VAULT_RG" \
        --vault-name "$VAULT_NAME" \
        --query "[?name=='${POLICY_NAME}'].name" -o tsv 2>/dev/null || true)

    if [[ -n "$EXISTING_POLICY" ]]; then
        info "Backup policy '${POLICY_NAME}' already exists."
    else
        # Build schedule: daily or hourly
        if [[ "${BACKUP_FREQUENCY,,}" == "daily" ]]; then
            SCHEDULE="R/$(date -u +%Y-%m-%dT02:00:00+00:00)/P1D"
        else
            SCHEDULE="R/$(date -u +%Y-%m-%dT00:00:00+00:00)/PT4H"
        fi

        RETENTION_ISO="P${RETENTION_DAYS}D"

        # Build the policy JSON inline
        POLICY_JSON=$(cat <<EOF
{
  "datasourceTypes": ["Microsoft.ContainerService/managedClusters"],
  "objectType": "BackupPolicy",
  "policyRules": [
    {
      "objectType": "AzureBackupRule",
      "name": "BackupSchedule",
      "backupParameters": {
        "objectType": "AzureBackupParams",
        "backupType": "Incremental"
      },
      "dataStore": {
        "dataStoreType": "OperationalStore",
        "objectType": "DataStoreInfoBase"
      },
      "trigger": {
        "objectType": "ScheduleBasedTriggerContext",
        "schedule": {
          "repeatingTimeIntervals": ["${SCHEDULE}"]
        },
        "taggingCriteria": [
          {
            "isDefault": true,
            "tagInfo": { "tagName": "Default" },
            "taggingPriority": 99
          }
        ]
      }
    },
    {
      "objectType": "AzureRetentionRule",
      "name": "Default",
      "isDefault": true,
      "lifecycles": [
        {
          "deleteAfter": {
            "objectType": "AbsoluteDeleteOption",
            "duration": "${RETENTION_ISO}"
          },
          "sourceDataStore": {
            "dataStoreType": "OperationalStore",
            "objectType": "DataStoreInfoBase"
          }
        }
      ]
    }
  ]
}
EOF
)
        echo "$POLICY_JSON" > /tmp/aks_backup_policy.json
        az dataprotection backup-policy create \
            --resource-group "$VAULT_RG" \
            --vault-name "$VAULT_NAME" \
            --name "$POLICY_NAME" \
            --policy /tmp/aks_backup_policy.json \
            -o none
        info "Backup policy '${POLICY_NAME}' created."
    fi

    POLICY_ID=$(az dataprotection backup-policy show \
        --resource-group "$VAULT_RG" \
        --vault-name "$VAULT_NAME" \
        --name "$POLICY_NAME" \
        --query id -o tsv)
    export POLICY_ID
}

# ─────────────────────────────────────────────
# STEP 11 — CONFIGURE BACKUP INSTANCE
# ─────────────────────────────────────────────
configure_backup_instance() {
    header "Configuring Backup Instance"

    # Check if backup instance already exists
    EXISTING_INSTANCE=$(az dataprotection backup-instance list \
        --resource-group "$VAULT_RG" \
        --vault-name "$VAULT_NAME" \
        --query "[?properties.friendlyName=='${FRIENDLY_NAME}'].name" -o tsv 2>/dev/null || true)

    if [[ -n "$EXISTING_INSTANCE" ]]; then
        info "Backup instance '${FRIENDLY_NAME}' already exists."
        BACKUP_INSTANCE_NAME="$EXISTING_INSTANCE"
        return
    fi

    AKS_RESOURCE_ID=$(az aks show \
        --name "$AKS_CLUSTER_NAME" \
        --resource-group "$AKS_CLUSTER_RG" \
        --query id -o tsv)

    # Build backup configuration
    BACKUP_CONFIG_ARGS=(
        "--snapshot-volume" "true"
        "--include-cluster-scope-resource" "true"
        "--datasource-type" "AzureKubernetesService"
    )

    # Add namespace filter if specified
    if [[ -n "$INCLUDE_NAMESPACES" ]]; then
        # Convert comma list to space-separated for CLI
        NS_LIST=$(echo "$INCLUDE_NAMESPACES" | tr ',' ' ')
        BACKUP_CONFIG_ARGS+=("--included-namespaces" $NS_LIST)
    fi

    # Volume type
    case "${VOLUME_TYPES,,}" in
        azuredisk|azureddisk)
            BACKUP_CONFIG_ARGS+=("--volume-types" "AzureDisk") ;;
        azurefileshare*|azuresmb*)
            BACKUP_CONFIG_ARGS+=("--volume-types" "AzureFileShareCSIDriver" "--include-secret" "true") ;;
        all)
            BACKUP_CONFIG_ARGS+=("--volume-types" "AzureDisk" "AzureFileShareCSIDriver" "--include-secret" "true") ;;
    esac

    info "Preparing backup instance request..."
    az dataprotection backup-instance initialize \
        --datasource-type "AzureKubernetesService" \
        --datasource-location "$LOCATION" \
        --datasource-id "$AKS_RESOURCE_ID" \
        --policy-id "$POLICY_ID" \
        --snapshot-resource-group-name "$SNAPSHOT_RG" \
        --friendly-name "$FRIENDLY_NAME" \
        "${BACKUP_CONFIG_ARGS[@]}" \
        > /tmp/aks_backup_instance.json

    info "Assigning required permissions via MSI..."
    az dataprotection backup-instance update-msi-permissions \
        --resource-group "$VAULT_RG" \
        --vault-name "$VAULT_NAME" \
        --datasource-type "AzureKubernetesService" \
        --operation "Backup" \
        --permissions-scope "ResourceGroup" \
        --backup-instance /tmp/aks_backup_instance.json \
        -o none 2>/dev/null || warn "MSI permission update returned a warning — continuing."

    info "Validating backup instance readiness..."
    az dataprotection backup-instance validate-for-backup \
        --resource-group "$VAULT_RG" \
        --vault-name "$VAULT_NAME" \
        --backup-instance /tmp/aks_backup_instance.json \
        -o none 2>/dev/null \
        || warn "Validation returned warnings — review portal for missing role assignments."

    info "Creating backup instance..."
    az dataprotection backup-instance create \
        --resource-group "$VAULT_RG" \
        --vault-name "$VAULT_NAME" \
        --backup-instance /tmp/aks_backup_instance.json \
        -o none

    info "Backup instance '${FRIENDLY_NAME}' created."

    # Retrieve instance name for on-demand use
    BACKUP_INSTANCE_NAME=$(az dataprotection backup-instance list \
        --resource-group "$VAULT_RG" \
        --vault-name "$VAULT_NAME" \
        --query "[?properties.friendlyName=='${FRIENDLY_NAME}'].name" -o tsv 2>/dev/null || true)
    export BACKUP_INSTANCE_NAME
}

# ─────────────────────────────────────────────
# STEP 12 — OPTIONAL ON-DEMAND BACKUP
# ─────────────────────────────────────────────
run_adhoc_backup() {
    [[ "${RUN_ADHOC,,}" != "y" ]] && return

    header "Triggering On-Demand Backup"

    if [[ -z "${BACKUP_INSTANCE_NAME:-}" ]]; then
        warn "Backup instance name not available — skipping on-demand backup."
        return
    fi

    info "Triggering ad-hoc backup for instance '${BACKUP_INSTANCE_NAME}'..."
    JOB_ID=$(az dataprotection backup-instance adhoc-backup \
        --name "$BACKUP_INSTANCE_NAME" \
        --resource-group "$VAULT_RG" \
        --vault-name "$VAULT_NAME" \
        --rule-name "Default" \
        --query jobId -o tsv 2>/dev/null || true)

    if [[ -z "$JOB_ID" ]]; then
        warn "Could not retrieve job ID. Check backup jobs in the Azure portal."
        return
    fi

    info "Backup job started. Job ID: ${JOB_ID}"
    info "Monitoring job status (timeout: 30 min)..."

    for i in $(seq 1 60); do
        STATUS=$(az dataprotection job show \
            --job-id "$JOB_ID" \
            --resource-group "$VAULT_RG" \
            --vault-name "$VAULT_NAME" \
            --query "properties.status" -o tsv 2>/dev/null || echo "Unknown")
        info "  Job status: ${STATUS} (check ${i}/60)"
        case "$STATUS" in
            Completed)
                info "✅ On-demand backup completed successfully."
                return ;;
            Failed|Cancelled)
                error "Backup job ${STATUS}. Job ID: ${JOB_ID}"
                warn "Run: az dataprotection job show --job-id ${JOB_ID} --resource-group ${VAULT_RG} --vault-name ${VAULT_NAME}"
                return ;;
        esac
        sleep 30
    done
    warn "Job did not complete within 30 minutes. Monitor via portal or:"
    warn "  az dataprotection job show --job-id ${JOB_ID} --resource-group ${VAULT_RG} --vault-name ${VAULT_NAME}"
}

# ─────────────────────────────────────────────
# FINAL SUMMARY
# ─────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║              AKS AZURE BACKUP — SETUP COMPLETE              ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  AKS Cluster         : ${AKS_CLUSTER_NAME} (${AKS_CLUSTER_RG})"
    echo -e "  Backup Vault        : ${VAULT_NAME} (${VAULT_RG})"
    echo -e "  Backup Policy       : ${POLICY_NAME} | ${BACKUP_FREQUENCY} | ${RETENTION_DAYS}-day retention"
    echo -e "  Backup Instance     : ${FRIENDLY_NAME}"
    echo -e "  Storage Account     : ${STORAGE_ACCOUNT_NAME}"
    echo -e "  Blob Container      : ${BLOB_CONTAINER}"
    echo -e "  Snapshot RG         : ${SNAPSHOT_RG}"
    echo -e "  Namespaces          : ${INCLUDE_NAMESPACES:-ALL}"
    echo -e "  Volume types        : ${VOLUME_TYPES}"
    echo ""
    echo -e "  ${BOLD}Useful commands:${NC}"
    echo -e "  # List backup instances"
    echo -e "  az dataprotection backup-instance list -g ${VAULT_RG} --vault-name ${VAULT_NAME} -o table"
    echo ""
    echo -e "  # Trigger on-demand backup"
    echo -e "  az dataprotection backup-instance adhoc-backup \\"
    echo -e "    --name ${BACKUP_INSTANCE_NAME:-<instance-name>} \\"
    echo -e "    -g ${VAULT_RG} --vault-name ${VAULT_NAME} --rule-name Default"
    echo ""
    echo -e "  # List backup jobs"
    echo -e "  az dataprotection job list -g ${VAULT_RG} --vault-name ${VAULT_NAME} -o table"
    echo ""
    echo -e "  # Show extension status"
    echo -e "  az k8s-extension show --name azure-aks-backup \\"
    echo -e "    --cluster-type managedClusters --cluster-name ${AKS_CLUSTER_NAME} -g ${AKS_CLUSTER_RG}"
    echo ""
}

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────
main() {
    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║   LightBeam AKS — Azure Backup Setup             ║"
    echo "  ║   Native Azure Backup (DataProtection API)        ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"

    require az

    collect_inputs
    validate_permissions
    register_providers
    create_storage
    create_snapshot_rg
    install_backup_extension
    grant_storage_permission
    create_backup_vault
    enable_trusted_access
    grant_vault_permissions
    create_backup_policy
    configure_backup_instance
    run_adhoc_backup
    print_summary
}

main "$@"
