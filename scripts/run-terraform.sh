#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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
    echo "Missing required environment variables. Set ARM_CLIENT_ID/AZURE_CLIENT_ID, ARM_TENANT_ID/AZURE_TENANT_ID, and ARM_SUBSCRIPTION_ID/AZURE_SUBSCRIPTION_ID."
    exit 1
  fi

  ARM_OIDC_TOKEN="${ARM_OIDC_TOKEN:-}"

  if [[ -z "${ARM_OIDC_TOKEN}" && -n "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" && -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
    ARM_OIDC_TOKEN="$(curl -sS \
      -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
      -H "Accept: application/json; api-version=2.0" \
      "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" \
      | python -c 'import json, sys; data=json.load(sys.stdin); print(data.get("value", ""))' 2>/dev/null || true)"
  fi

  if [[ -z "${ARM_OIDC_TOKEN}" && -n "${AZURE_FEDERATED_TOKEN:-}" ]]; then
    ARM_OIDC_TOKEN="${AZURE_FEDERATED_TOKEN}"
  fi

  if [[ -z "${ARM_OIDC_TOKEN}" ]]; then
    echo "Unable to determine a federated OIDC token. Ensure ARM_OIDC_TOKEN is set, or run this script from GitHub Actions with id-token: write enabled."
    exit 1
  fi

  az login --service-principal \
    --username "${ARM_CLIENT_ID}" \
    --tenant "${ARM_TENANT_ID}" \
    --federated-token "${ARM_OIDC_TOKEN}" >/dev/null

  az account set --subscription "${ARM_SUBSCRIPTION_ID}"

  export ARM_USE_OIDC="true"
  export ARM_USE_MSI="false"
  export ARM_CLIENT_ID="${ARM_CLIENT_ID}"
  export ARM_TENANT_ID="${ARM_TENANT_ID}"
  export ARM_SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID}"
  export ARM_SKIP_PROVIDER_REGISTRATION="true"
fi

append_default_var_file() {
  local -a args=("$@")
  local has_var_file=false

  for arg in "${args[@]}"; do
    if [[ "${arg}" == "-var-file="* || "${arg}" == "-var-file" ]]; then
      has_var_file=true
      break
    fi
  done

  if [[ "${has_var_file}" == "false" ]]; then
    if [[ -f "${REPO_ROOT}/terraform/example.tfvars" ]]; then
      args+=("-var-file=${REPO_ROOT}/terraform/example.tfvars")
    elif [[ -f "${TERRAFORM_DIR}/example.tfvars" ]]; then
      args+=("-var-file=${TERRAFORM_DIR}/example.tfvars")
    fi
  fi

  printf '%s\n' "${args[@]}"
}

cd "${TERRAFORM_DIR}"

tf_command="${1:-plan}"
shift || true

case "${tf_command}" in
  init)
    terraform init
    ;;
  plan)
    terraform init
    plan_args=()
    while IFS= read -r arg; do
      plan_args+=("$arg")
    done < <(append_default_var_file "$@")
    terraform plan "${plan_args[@]}"
    ;;
  apply)
    terraform init
    apply_args=()
    while IFS= read -r arg; do
      apply_args+=("$arg")
    done < <(append_default_var_file "$@")
    terraform apply "${apply_args[@]}"
    ;;
  destroy)
    terraform init
    destroy_args=()
    while IFS= read -r arg; do
      destroy_args+=("$arg")
    done < <(append_default_var_file "$@")
    terraform destroy "${destroy_args[@]}"
    ;;
  *)
    echo "Unsupported command: ${tf_command}"
    echo "Use: init | plan | apply | destroy"
    exit 1
    ;;
esac
