#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
CONFIG_DIR="${TERRAFORM_DIR}/configurations"

ACTION="${1:-plan}"
ENV_NAME="${2:-${TF_ENVIRONMENT:-${ENVIRONMENT:-dev}}}"
TF_VAR_FILE="${TF_VAR_FILE:-${CONFIG_DIR}/${ENV_NAME}/config.tfvars}"

if [[ ! -f "${TF_VAR_FILE}" ]]; then
  echo "Terraform variables file not found: ${TF_VAR_FILE}"
  echo "Expected location: ${CONFIG_DIR}/${ENV_NAME}/config.tfvars"
  exit 1
fi

ARM_CLIENT_ID="${ARM_CLIENT_ID:-${AZURE_CLIENT_ID:-}}"
ARM_TENANT_ID="${ARM_TENANT_ID:-${AZURE_TENANT_ID:-}}"
ARM_SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID:-${AZURE_SUBSCRIPTION_ID:-}}"

if [[ -z "${ARM_SUBSCRIPTION_ID}" ]]; then
  echo "ARM_SUBSCRIPTION_ID / AZURE_SUBSCRIPTION_ID is required."
  exit 1
fi

if [[ "${USE_MANAGED_IDENTITY:-false}" == "true" ]]; then
  if ! az account show >/dev/null 2>&1; then
    if [[ -n "${ARM_CLIENT_ID}" ]]; then
      az login --identity --username "${ARM_CLIENT_ID}" >/dev/null
    else
      az login --identity >/dev/null
    fi
  fi

  az account set --subscription "${ARM_SUBSCRIPTION_ID}"
  export ARM_USE_MSI="true"
  export ARM_USE_OIDC="false"
  export ARM_CLIENT_ID="${ARM_CLIENT_ID}"
  export ARM_TENANT_ID="${ARM_TENANT_ID:-$(az account show --query tenantId -o tsv)}"
  export ARM_SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID}"
  export ARM_SKIP_PROVIDER_REGISTRATION="true"
else
  if [[ -z "${ARM_CLIENT_ID}" || -z "${ARM_TENANT_ID}" ]]; then
    echo "Missing required environment variables. Set ARM_CLIENT_ID/AZURE_CLIENT_ID and ARM_TENANT_ID/AZURE_TENANT_ID."
    exit 1
  fi

  OIDC_TOKEN="${ARM_OIDC_TOKEN:-}"

  if [[ -z "${OIDC_TOKEN}" && -n "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" && -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
    OIDC_TOKEN="$(curl -sS \
      -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
      -H "Accept: application/json; api-version=2.0" \
      "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" \
      | python -c 'import json, sys; data=json.load(sys.stdin); print(data.get("value", ""))' 2>/dev/null || true)"
  fi

  if [[ -z "${OIDC_TOKEN}" && -n "${AZURE_FEDERATED_TOKEN:-}" ]]; then
    OIDC_TOKEN="${AZURE_FEDERATED_TOKEN}"
  fi

  if [[ -z "${OIDC_TOKEN}" ]]; then
    echo "Unable to determine Azure OIDC federated token."
    echo "Set ARM_OIDC_TOKEN, AZURE_FEDERATED_TOKEN, or run this from GitHub Actions with id-token: write enabled."
    exit 1
  fi

  az login --service-principal \
    --username "${ARM_CLIENT_ID}" \
    --tenant "${ARM_TENANT_ID}" \
    --federated-token "${OIDC_TOKEN}" >/dev/null

  az account set --subscription "${ARM_SUBSCRIPTION_ID}"

  export ARM_USE_OIDC="true"
  export ARM_USE_MSI="false"
  export ARM_CLIENT_ID="${ARM_CLIENT_ID}"
  export ARM_TENANT_ID="${ARM_TENANT_ID}"
  export ARM_SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID}"
  export ARM_SKIP_PROVIDER_REGISTRATION="true"
fi

case "${ACTION}" in
  plan)
    echo "Running terraform plan for environment: ${ENV_NAME}"
    cd "${TERRAFORM_DIR}"
    terraform init
    terraform plan -var-file="${TF_VAR_FILE}"
    ;;
  apply)
    echo "Running terraform apply for environment: ${ENV_NAME}"
    cd "${TERRAFORM_DIR}"
    terraform init
    terraform apply -var-file="${TF_VAR_FILE}" -auto-approve
    ;;
  destroy)
    echo "Running terraform destroy for environment: ${ENV_NAME}"
    cd "${TERRAFORM_DIR}"
    terraform init
    terraform destroy -var-file="${TF_VAR_FILE}" -auto-approve
    ;;
  *)
    echo "Unsupported action: ${ACTION}"
    echo "Usage: $0 <plan|apply|destroy> [environment]"
    exit 1
    ;;
esac
