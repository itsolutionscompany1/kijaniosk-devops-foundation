#!/bin/bash
#
# pipeline.sh — KijaniKiosk Terraform + Ansible orchestration
#
# Runs Terraform first (to provision/verify the infrastructure), then
# extracts the VM IPs dynamically, writes them to the Ansible inventory,
# and runs the Ansible playbook to configure the servers.
#
# Usage:
#   ./pipeline.sh              # default: read IPs from multipass
#   ./pipeline.sh multipass    # explicit: same as default
#   ./pipeline.sh cloud        # read IPs from terraform output
#
# Exit codes:
#   0 — both Terraform and Ansible succeeded
#   1 — Terraform failed
#   2 — Inventory generation failed
#   3 — Ansible failed
#

set -euo pipefail

# --- Configuration ---
TERRAFORM_DIR="/home/medico/kijanikiosk-infra"
ANSIBLE_DIR="/home/medico/kijanikiosk-ansible"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory.ini"
PLAYBOOK="${ANSIBLE_DIR}/kijanikiosk.yml"

PATH_MODE="${1:-multipass}"

echo "==================================================================="
echo "KijaniKiosk Pipeline — $(date -Is)"
echo "Path mode: ${PATH_MODE}"
echo "==================================================================="

# --- Phase 1: Terraform apply ---
echo
echo ">>> [1/3] Terraform apply"
echo "-------------------------------------------------------------------"
cd "${TERRAFORM_DIR}"

if ! terraform apply -auto-approve; then
  echo
  echo "ERROR: Terraform apply failed." >&2
  exit 1
fi

# --- Phase 2: Extract IPs and write inventory ---
echo
echo ">>> [2/3] Generating Ansible inventory"
echo "-------------------------------------------------------------------"

if [[ "${PATH_MODE}" == "multipass" ]]; then
  API_IP=$(multipass info kijanikiosk-api      | awk '/IPv4/ {print $2}')
  PAYMENTS_IP=$(multipass info kijanikiosk-payments | awk '/IPv4/ {print $2}')
  LOGS_IP=$(multipass info kijanikiosk-logs     | awk '/IPv4/ {print $2}')
else
  API_IP=$(terraform output -raw api_server_ip 2>/dev/null)
  PAYMENTS_IP=$(terraform output -raw payments_server_ip 2>/dev/null)
  LOGS_IP=$(terraform output -raw logs_server_ip 2>/dev/null)
fi

if [[ -z "${API_IP}" ]] || [[ -z "${PAYMENTS_IP}" ]] || [[ -z "${LOGS_IP}" ]]; then
  echo "ERROR: Could not resolve one or more VM IPs." >&2
  echo "  API_IP=${API_IP}" >&2
  echo "  PAYMENTS_IP=${PAYMENTS_IP}" >&2
  echo "  LOGS_IP=${LOGS_IP}" >&2
  exit 2
fi

echo "Resolved IPs:"
echo "  api      = ${API_IP}"
echo "  payments = ${PAYMENTS_IP}"
echo "  logs     = ${LOGS_IP}"

cat > "${INVENTORY_FILE}" << INVENTORY
[kijanikiosk_api]
api ansible_host=${API_IP}

[kijanikiosk_payments]
payments ansible_host=${PAYMENTS_IP}

[kijanikiosk_logs]
logs ansible_host=${LOGS_IP}

[kijanikiosk:children]
kijanikiosk_api
kijanikiosk_payments
kijanikiosk_logs

[kijanikiosk:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=/home/medico/.ssh/id_rsa
ansible_python_interpreter=/usr/bin/python3
INVENTORY

echo "Inventory written to ${INVENTORY_FILE}:"
cat "${INVENTORY_FILE}"

# --- Phase 3: Ansible playbook ---
echo
echo ">>> [3/3] Ansible playbook"
echo "-------------------------------------------------------------------"
cd "${ANSIBLE_DIR}"

if ! ansible-playbook -i "${INVENTORY_FILE}" "${PLAYBOOK}"; then
  echo
  echo "ERROR: Ansible playbook failed." >&2
  exit 3
fi

echo
echo "==================================================================="
echo "Pipeline complete — $(date -Is)"
echo "==================================================================="
exit 0
