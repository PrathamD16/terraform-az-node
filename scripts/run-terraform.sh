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

resolve_var_file() {
  local requested_path="${1:-}"
  local workspace_root="${GITHUB_WORKSPACE:-${REPO_ROOT:-}}"
  local candidate_paths=()

  echo "Requested Path: ${requested_path}"

  if [[ -n "${requested_path}" ]]; then
    candidate_paths+=(
      "${requested_path}"
      "${workspace_root}/${requested_path}"
      "${REPO_ROOT}/${requested_path}"
      "${TERRAFORM_DIR}/${requested_path}"
      "${REPO_ROOT}/terraform/${requested_path}"
      "${workspace_root}/terraform/${requested_path}"
      "${REPO_ROOT}/${requested_path#./}"
      "${workspace_root}/${requested_path#./}"
    )

    for candidate in "${candidate_paths[@]}"; do
      if [[ -f "${candidate}" ]]; then
        local abs_candidate
        abs_candidate="$(cd "$(dirname "${candidate}")" && pwd)/$(basename "${candidate}")"
        printf '%s\n' "${abs_candidate}"
        return 0
      fi
    done

    local file_name="$(basename "${requested_path}")"
    local found_file
    found_file="$(find "${workspace_root:-${REPO_ROOT}}" -type f -path "*${file_name}" 2>/dev/null | head -n 1)"

    echo "file_name: ${file_name}"
    echo "found_file: ${found_file}"

    if [[ -n "${found_file}" && -f "${found_file}" ]]; then
      printf '%s\n' "${found_file}"
      return 0
    fi

    echo "Variables file not found: ${requested_path}" >&2
    return 1
  fi

  local env_names=()
  if [[ -n "${TF_ENVIRONMENT:-}" ]]; then
    env_names+=("${TF_ENVIRONMENT}")
  fi
  if [[ -n "${ENVIRONMENT:-}" ]]; then
    env_names+=("${ENVIRONMENT}")
  fi
  if [[ -n "${GITHUB_EVENT_INPUTS_environment:-}" ]]; then
    env_names+=("${GITHUB_EVENT_INPUTS_environment}")
  fi
  if [[ -n "${GITHUB_REF_NAME:-}" ]]; then
    env_names+=("${GITHUB_REF_NAME}")
  fi

  local default_candidates=()
  for env_name in "${env_names[@]}"; do
    if [[ -n "${env_name}" ]]; then
      default_candidates+=(
        "${workspace_root}/${env_name}/config.tfvars"
        "${REPO_ROOT}/${env_name}/config.tfvars"
        "${workspace_root}/terraform/${env_name}/config.tfvars"
        "${REPO_ROOT}/terraform/${env_name}/config.tfvars"
      )
    fi
  done

  local search_roots=(
    "${workspace_root}"
    "${REPO_ROOT}"
    "${TERRAFORM_DIR}"
  )

  for root in "${search_roots[@]}"; do
    if [[ -d "${root}" ]]; then
      while IFS= read -r tfvars_file; do
        if [[ -n "${tfvars_file}" ]]; then
          default_candidates+=("${tfvars_file}")
        fi
      done < <(find "${root}" -type f -name "config.tfvars" -not -path "*/.terraform/*" 2>/dev/null | sort)
    fi
  done

  for candidate in "${default_candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      local abs_candidate
      abs_candidate="$(cd "$(dirname "${candidate}")" && pwd)/$(basename "${candidate}")"
      printf '%s\n' "${abs_candidate}"
      return 0
    fi
  done

  echo "No variables file found under a config folder or any config.tfvars file in the repo." >&2
  return 1
}

VAR_FILE="$(resolve_var_file "${TF_VAR_FILE:-}")"
if [[ -z "${VAR_FILE}" ]]; then
  exit 1
fi

cd "${TERRAFORM_DIR}"

tf_command="${1:-plan}"
shift || true

echo "Terraform directory: ${TERRAFORM_DIR}"
echo "Using variables file: ${VAR_FILE}"

case "${tf_command}" in
  init)
    terraform init
    ;;
  plan)
    terraform init
    if [[ -n "$*" ]]; then
      terraform plan "$@"
    else
      terraform plan -var-file="${VAR_FILE}"
    fi
    ;;
  apply)
    terraform init
    if [[ -n "$*" ]]; then
      terraform apply "$@"
    else
      terraform apply -var-file="${VAR_FILE}"
    fi
    ;;
  destroy)
    terraform init
    if [[ -n "$*" ]]; then
      terraform destroy "$@"
    else
      terraform destroy -var-file="${VAR_FILE}"
    fi
    ;;
  *)
    echo "Unsupported command: ${tf_command}"
    echo "Use: init | plan | apply | destroy"
    exit 1
    ;;
esac
