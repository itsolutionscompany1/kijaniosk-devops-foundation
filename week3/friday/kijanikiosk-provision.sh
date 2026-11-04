#!/bin/bash
#
# kijanikiosk-provision.sh
# KijaniKiosk production server foundation — idempotent provisioning script
#
# Expected dirty conditions inherited from prior labs (see pre-provisioning-audit.txt):
#   - kk-api, kk-payments, kk-logs exist with non-canonical UIDs (1501-1503)
#   - kijanikiosk group exists with non-canonical GID (1500)
#   - /opt/kijanikiosk/ owned by root:root
#   - /opt/kijanikiosk/config/ is world-writable (0777)
#   - No default ACLs on /opt/kijanikiosk/shared/logs/
#   - UFW has a stray "deny 3001" rule with no comment
#   - Package hold on curl
#   - No logrotate config
#   - No kk-*.service units
#
set -euo pipefail

# ---------- Canonical values ----------
readonly KK_GROUP="kijanikiosk"
readonly KK_GROUP_GID=2000
readonly KK_API_USER="kk-api"
readonly KK_API_UID=2001
readonly KK_PAYMENTS_USER="kk-payments"
readonly KK_PAYMENTS_UID=2002
readonly KK_LOGS_USER="kk-logs"
readonly KK_LOGS_UID=2003

readonly KK_BASE="/opt/kijanikiosk"
readonly KK_CONFIG="${KK_BASE}/config"
readonly KK_LOGS_DIR="${KK_BASE}/shared/logs"
readonly KK_HEALTH="${KK_BASE}/health"

readonly CURL_PIN="7.81.0-1ubuntu1.29"

readonly MONITORING_CIDR="10.0.1.0/24"

# ---------- Logging ----------
info()    { printf '[INFO]  %s\n' "$*"; }
success() { printf '[ OK ]  %s\n' "$*"; }
warn()    { printf '[WARN]  %s\n' "$*" >&2; }
error()   { printf '[FAIL]  %s\n' "$*" >&2; }

# ---------- Verification accumulator ----------
VERIFY_FAILED=0
verify_pass() { success "PASS: $*"; }
verify_fail() { error  "FAIL: $*"; VERIFY_FAILED=$((VERIFY_FAILED + 1)); }

# ---------- Preflight ----------
if [[ $EUID -ne 0 ]]; then
  error "This script must run as root (use sudo)."
  exit 1
fi

if [[ ! -f /etc/os-release ]] || ! grep -q 'Ubuntu 22.04' /etc/os-release; then
  warn "Expected Ubuntu 22.04; proceeding anyway."
fi

info "kijanikiosk-provision.sh starting at $(date -Is)"
info "Host: $(hostname)"

# ============================================================
# Phase 1: Users and Groups
# ============================================================
info "Phase 1: users and groups"

# --- Group ---
if ! getent group "${KK_GROUP}" >/dev/null; then
  info "Group ${KK_GROUP} missing — creating with GID ${KK_GROUP_GID}"
  groupadd -g "${KK_GROUP_GID}" "${KK_GROUP}"
  success "Created group ${KK_GROUP} (GID ${KK_GROUP_GID})"
else
  current_gid=$(getent group "${KK_GROUP}" | cut -d: -f3)
  if [[ "${current_gid}" == "${KK_GROUP_GID}" ]]; then
    info "Already correct: ${KK_GROUP} GID ${current_gid}"
  else
    warn "Group ${KK_GROUP} has GID ${current_gid}, expected ${KK_GROUP_GID} — correcting"
    groupmod -g "${KK_GROUP_GID}" "${KK_GROUP}"
    success "Corrected ${KK_GROUP} GID ${current_gid} -> ${KK_GROUP_GID}"
  fi
fi

# --- Users ---
ensure_user() {
  local user="$1" uid="$2" comment="$3"
  if ! getent passwd "${user}" >/dev/null; then
    info "User ${user} missing — creating with UID ${uid}"
    useradd -u "${uid}" -g "${KK_GROUP}" -M -s /usr/sbin/nologin -c "${comment}" "${user}"
    success "Created user ${user} (UID ${uid})"
  else
    local current_uid
    current_uid=$(getent passwd "${user}" | cut -d: -f3)
    if [[ "${current_uid}" == "${uid}" ]]; then
      info "Already correct: ${user} UID ${current_uid}"
    else
      warn "User ${user} has UID ${current_uid}, expected ${uid} — correcting"
      usermod -u "${uid}" "${user}"
      success "Corrected ${user} UID ${current_uid} -> ${uid}"
    fi
  fi
}

ensure_user "${KK_API_USER}"      "${KK_API_UID}"      "KijaniKiosk API service"
ensure_user "${KK_PAYMENTS_USER}" "${KK_PAYMENTS_UID}" "KijaniKiosk payments service"
ensure_user "${KK_LOGS_USER}"     "${KK_LOGS_UID}"     "KijaniKiosk logs service"

# --- Verify ---
info "Phase 1 verification:"
[[ "$(getent group "${KK_GROUP}" | cut -d: -f3)" == "${KK_GROUP_GID}" ]] \
  && verify_pass "group ${KK_GROUP} GID is ${KK_GROUP_GID}" \
  || verify_fail "group ${KK_GROUP} GID is not ${KK_GROUP_GID}"

for pair in "${KK_API_USER}:${KK_API_UID}" "${KK_PAYMENTS_USER}:${KK_PAYMENTS_UID}" "${KK_LOGS_USER}:${KK_LOGS_UID}"; do
  u="${pair%%:*}"; id="${pair##*:}"
  [[ "$(getent passwd "${u}" | cut -d: -f3)" == "${id}" ]] \
    && verify_pass "user ${u} UID is ${id}" \
    || verify_fail "user ${u} UID is not ${id}"
done

# ============================================================
# Phase 2: Directory structure, ownership, and ACLs
# ============================================================
info "Phase 2: directories, ownership, ACLs"

# --- Create directory tree (idempotent) ---
for d in "${KK_BASE}" "${KK_CONFIG}" "${KK_BASE}/shared" "${KK_LOGS_DIR}" "${KK_HEALTH}"; do
  if [[ -d "${d}" ]]; then
    info "Already exists: ${d}"
  else
    info "Creating: ${d}"
    mkdir -p "${d}"
  fi
done

# --- Ownership ---
info "Setting ownership root:${KK_GROUP} on ${KK_BASE}"
chown -R "root:${KK_GROUP}" "${KK_BASE}"

# --- Permissions ---
# Detect and correct the 0777 config directory from the dirty state
current_config_mode=$(stat -c '%a' "${KK_CONFIG}")
if [[ "${current_config_mode}" == "750" ]]; then
  info "Already correct: ${KK_CONFIG} mode 0750"
else
  warn "Found: ${KK_CONFIG} mode 0${current_config_mode}, expected 0750 — correcting"
fi
chmod 2750 "${KK_BASE}"
chmod 0750 "${KK_CONFIG}"
chmod 2770 "${KK_LOGS_DIR}"
chmod 2750 "${KK_HEALTH}"
chmod 0755 "${KK_BASE}/shared"
success "Applied canonical permissions (base 2750, config 0750, logs 2770, health 2750)"

# --- ACLs on shared/logs (critical for logrotate interaction) ---
info "Applying default ACLs to ${KK_LOGS_DIR}"
setfacl -m "u::rwx,g::rwx,o::---" "${KK_LOGS_DIR}"
setfacl -d -m "u::rwx,g::rwx,o::---" "${KK_LOGS_DIR}"
success "Default ACLs applied to ${KK_LOGS_DIR}"

# --- Verify ---
info "Phase 2 verification:"
declare -A expected_modes=(
  ["${KK_BASE}"]="2750"
  ["${KK_CONFIG}"]="750"
  ["${KK_LOGS_DIR}"]="2770"
  ["${KK_HEALTH}"]="2750"
)
for path in "${!expected_modes[@]}"; do
  mode=$(stat -c '%a' "${path}")
  [[ "${mode}" == "${expected_modes[$path]}" ]] \
    && verify_pass "${path} mode is ${expected_modes[$path]}" \
    || verify_fail "${path} mode is ${mode}, expected ${expected_modes[$path]}"
done

getfacl -p "${KK_LOGS_DIR}" 2>/dev/null | grep -q '^default:user::rwx' \
  && verify_pass "default ACL present on ${KK_LOGS_DIR}" \
  || verify_fail "default ACL missing on ${KK_LOGS_DIR}"

# ============================================================
# Phase 3: Package management
# ============================================================
info "Phase 3: package management"

# --- Detect and remove stray package hold ---
if apt-mark showhold | grep -qx "curl"; then
  warn "Found: curl is held via apt-mark — removing hold"
  apt-mark unhold curl >/dev/null
  success "Removed hold on curl"
else
  info "Already correct: curl is not held"
fi

# --- Confirm curl is installed ---
if ! dpkg -s curl >/dev/null 2>&1; then
  info "curl not installed — installing"
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl
else
  info "Already installed: curl"
fi

# --- Check version against pin ---
installed_curl_version=$(dpkg-query -W -f='${Version}' curl 2>/dev/null || echo "none")
if [[ "${installed_curl_version}" == "${CURL_PIN}" ]]; then
  info "Already correct: curl ${installed_curl_version} matches pin"
else
  warn "curl version ${installed_curl_version} does not match pin ${CURL_PIN}"
  warn "Refusing to downgrade automatically — manual review required"
  error "Package version drift detected. Resolve manually and re-run."
  exit 2
fi

# --- Verify ---
info "Phase 3 verification:"
if apt-mark showhold | grep -qx "curl"; then
  verify_fail "curl still held after unhold"
else
  verify_pass "curl is not held"
fi

if [[ "$(dpkg-query -W -f='${Version}' curl 2>/dev/null)" == "${CURL_PIN}" ]]; then
  verify_pass "curl version is ${CURL_PIN}"
else
  verify_fail "curl version mismatch"
fi

# ============================================================
# Phase 4: Firewall — reset to baseline, then apply intended rules
# ============================================================
info "Phase 4: firewall"

# --- Reset ufw to a clean baseline ---
info "Resetting ufw to a clean baseline (discarding history)"
ufw --force reset >/dev/null

# --- Set default policies ---
ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null

# --- Add rules in order (allow loopback BEFORE deny) ---
# 1) SSH management
ufw allow 22/tcp comment 'SSH management' >/dev/null

# 2) HTTP via nginx
ufw allow 80/tcp comment 'HTTP via nginx' >/dev/null

# 3) Payments health check via loopback (nginx -> payments service)
#    Must appear BEFORE any deny on 3001 so loopback traffic matches here first.
ufw allow in on lo to any port 3001 proto tcp comment 'Payments health check via loopback' >/dev/null

# 4) Payments health check from monitoring subnet only
ufw allow from "${MONITORING_CIDR}" to any port 3001 proto tcp comment 'Payments health check from monitoring' >/dev/null

# 5) Explicit external deny for the payments port
ufw deny 3001/tcp comment 'Block external payments port access' >/dev/null

# --- Enable ---
ufw --force enable >/dev/null
success "Firewall configured and enabled"

# --- Verify (one PASS/FAIL per rule) ---
info "Phase 4 verification:"
ufw_status=$(ufw status)

echo "${ufw_status}" | grep -q "22/tcp.*ALLOW.*SSH management" \
  && verify_pass "SSH (22) allowed with comment" \
  || verify_fail "SSH rule missing or comment absent"

echo "${ufw_status}" | grep -q "80/tcp.*ALLOW.*HTTP via nginx" \
  && verify_pass "HTTP (80) allowed with comment" \
  || verify_fail "HTTP rule missing or comment absent"

echo "${ufw_status}" | grep -q "3001.*ALLOW.*loopback" \
  && verify_pass "Payments loopback allow present" \
  || verify_fail "Payments loopback allow missing"

echo "${ufw_status}" | grep -qE "3001/tcp[[:space:]]+ALLOW[[:space:]]+${MONITORING_CIDR}" \
  && verify_pass "Payments monitoring subnet allow present" \
  || verify_fail "Payments monitoring subnet allow missing"

echo "${ufw_status}" | grep -q "3001.*DENY.*Block external" \
  && verify_pass "Payments external deny present with comment" \
  || verify_fail "Payments external deny missing or comment absent"

# Verify the stray Thursday rule is gone (no un-commented deny)
if ufw status | grep -E "^3001.*DENY" | grep -v "Block external" | grep -q .; then
  verify_fail "stray un-commented deny 3001 rule still present"
else
  verify_pass "no stray un-commented deny 3001 rule"
fi


# ============================================================
# Phase 5: systemd units (written inline)
# ============================================================
info "Phase 5: systemd units"

# --- kk-payments.service ---
info "Writing /etc/systemd/system/kk-payments.service"
tee /etc/systemd/system/kk-payments.service > /dev/null << 'UNITEOF'
[Unit]
Description=KijaniKiosk Payments Service
After=network.target kk-api.service
Wants=kk-api.service

[Service]
Type=simple
User=kk-payments
Group=kijanikiosk
ExecStart=/usr/bin/sleep infinity
Restart=on-failure

ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
PrivateMounts=true

ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectProc=invisible
ProcSubset=pid

NoNewPrivileges=true
RestrictSUIDSGID=true
RestrictRealtime=true
LockPersonality=true
RemoveIPC=true
UMask=0027

CapabilityBoundingSet=
AmbientCapabilities=

PrivateNetwork=true
RestrictAddressFamilies=AF_UNIX
IPAddressDeny=any

RestrictNamespaces=true
PrivateUsers=true

SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources @obsolete @debug @mount @cpu-emulation @swap @module @raw-io @reboot @clock
SystemCallErrorNumber=EPERM

MemoryDenyWriteExecute=true
DeviceAllow=/dev/null rw
DeviceAllow=/dev/urandom r

[Install]
WantedBy=multi-user.target
UNITEOF

# --- kk-api.service ---
info "Writing /etc/systemd/system/kk-api.service"
tee /etc/systemd/system/kk-api.service > /dev/null << 'UNITEOF'
[Unit]
Description=KijaniKiosk API Service
After=network.target

[Service]
Type=simple
User=kk-api
Group=kijanikiosk
ExecStart=/usr/bin/sleep infinity
Restart=on-failure

ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
PrivateMounts=true

ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectProc=invisible
ProcSubset=pid

NoNewPrivileges=true
RestrictSUIDSGID=true
RestrictRealtime=true
LockPersonality=true
RemoveIPC=true
UMask=0027

CapabilityBoundingSet=
AmbientCapabilities=

PrivateNetwork=false
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

RestrictNamespaces=true
PrivateUsers=true

SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

MemoryDenyWriteExecute=true
DeviceAllow=/dev/null rw
DeviceAllow=/dev/urandom r

[Install]
WantedBy=multi-user.target
UNITEOF

# --- kk-logs.service ---
info "Writing /etc/systemd/system/kk-logs.service"
tee /etc/systemd/system/kk-logs.service > /dev/null << 'UNITEOF'
[Unit]
Description=KijaniKiosk Logs Service
After=network.target

[Service]
Type=simple
User=kk-logs
Group=kijanikiosk
ExecStart=/usr/bin/sleep infinity
Restart=on-failure

ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/opt/kijanikiosk/shared/logs
PrivateTmp=true
PrivateDevices=true
PrivateMounts=true

ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectProc=invisible
ProcSubset=pid

NoNewPrivileges=true
RestrictSUIDSGID=true
RestrictRealtime=true
LockPersonality=true
RemoveIPC=true
UMask=0027

CapabilityBoundingSet=
AmbientCapabilities=

PrivateNetwork=false
RestrictAddressFamilies=AF_UNIX

RestrictNamespaces=true
PrivateUsers=true

SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM

MemoryDenyWriteExecute=true
DeviceAllow=/dev/null rw
DeviceAllow=/dev/urandom r

[Install]
WantedBy=multi-user.target
UNITEOF

# --- Reload, enable, restart ---
info "Reloading systemd and (re)starting units"
systemctl daemon-reload
systemctl enable kk-api.service >/dev/null 2>&1 || true
systemctl enable kk-payments.service >/dev/null 2>&1 || true
systemctl enable kk-logs.service >/dev/null 2>&1 || true
systemctl restart kk-api.service
systemctl restart kk-payments.service
systemctl restart kk-logs.service
success "systemd units written and started"

# --- Verify ---
info "Phase 5 verification:"
for svc in kk-api kk-payments kk-logs; do
  if systemctl is-active "${svc}.service" >/dev/null 2>&1; then
    verify_pass "${svc}.service is active"
  else
    verify_fail "${svc}.service is not active"
  fi
done

payments_score=$(systemd-analyze security kk-payments.service 2>/dev/null | tail -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
if [[ -n "${payments_score}" ]] && awk "BEGIN{exit !(${payments_score} < 2.5)}"; then
  verify_pass "kk-payments hardening score ${payments_score} < 2.5"
else
  verify_fail "kk-payments hardening score ${payments_score:-unknown} >= 2.5"
fi

for svc in kk-api kk-logs; do
  s=$(systemd-analyze security "${svc}.service" 2>/dev/null | tail -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
  if [[ -n "${s}" ]] && awk "BEGIN{exit !(${s} < 3.5)}"; then
    verify_pass "${svc} hardening score ${s} < 3.5"
  else
    verify_fail "${svc} hardening score ${s:-unknown} >= 3.5"
  fi
done

# ============================================================
# Phase 6: journal persistence + logrotate
# ============================================================
info "Phase 6: journal persistence and logrotate"

# --- Journal persistence ---
info "Configuring persistent journald storage"
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal >/dev/null 2>&1 || true
systemctl restart systemd-journald
journalctl --flush >/dev/null 2>&1 || true

mkdir -p /etc/systemd/journald.conf.d
tee /etc/systemd/journald.conf.d/99-kijanikiosk.conf > /dev/null << 'JEOF'
[Journal]
Storage=persistent
SystemMaxUse=500M
JEOF
systemctl restart systemd-journald
success "Journal persistence configured (Storage=persistent, SystemMaxUse=500M)"

# --- Seed a placeholder log so logrotate has a real file to validate ---
if ! ls /opt/kijanikiosk/shared/logs/*.log >/dev/null 2>&1; then
  info "Seeding placeholder log file for logrotate validation"
  touch /opt/kijanikiosk/shared/logs/kk-api.log
  chown root:kijanikiosk /opt/kijanikiosk/shared/logs/kk-api.log
  chmod 0640 /opt/kijanikiosk/shared/logs/kk-api.log
fi

# --- Logrotate config ---
info "Writing /etc/logrotate.d/kijanikiosk"
tee /etc/logrotate.d/kijanikiosk > /dev/null << 'LREOF'
/opt/kijanikiosk/shared/logs/*.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    create 0640 root kijanikiosk
    su root kijanikiosk
    sharedscripts
    postrotate
        systemctl kill -s HUP kk-logs.service 2>/dev/null || true
    endscript
}
LREOF
success "logrotate config written for kijanikiosk logs"

# --- Verification ---
info "Phase 6 verification:"

if [[ -d /var/log/journal ]]; then
  verify_pass "persistent journal directory exists"
else
  verify_fail "persistent journal directory missing"
fi

if grep -q "SystemMaxUse=500M" /etc/systemd/journald.conf.d/99-kijanikiosk.conf 2>/dev/null; then
  verify_pass "journal SystemMaxUse=500M configured"
else
  verify_fail "journal size cap not configured"
fi

if [[ -f /etc/logrotate.d/kijanikiosk ]]; then
  verify_pass "logrotate config exists"
else
  verify_fail "logrotate config missing"
fi

if grep -q "^    su root kijanikiosk$" /etc/logrotate.d/kijanikiosk 2>/dev/null; then
  verify_pass "logrotate su directive present (group-writable dir accepted)"
else
  verify_fail "logrotate su directive missing"
fi

if logrotate --debug /etc/logrotate.d/kijanikiosk >/tmp/lr-debug.log 2>&1; then
  verify_pass "logrotate --debug passes"
else
  warn "logrotate --debug reported issues (see /tmp/lr-debug.log)"
  verify_fail "logrotate --debug failed"
fi

# ============================================================
# Phase 7: Health checks
# ============================================================
info "Phase 7: health checks"

# --- Probe ports ---
info "Probing service ports (3000, 3001, 3002)"
api_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3000" 2>/dev/null && echo '"ok"' || echo '"down"')
payments_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3001" 2>/dev/null && echo '"ok"' || echo '"down"')
logs_status=$(timeout 2 bash -c "echo >/dev/tcp/localhost/3002" 2>/dev/null && echo '"ok"' || echo '"down"')
info "Port 3000 (kk-api):      ${api_status}"
info "Port 3001 (kk-payments): ${payments_status}"
info "Port 3002 (kk-logs):     ${logs_status}"

# --- Write health JSON ---
mkdir -p "${KK_HEALTH}"
printf '{"timestamp":"%s","kk-api":%s,"kk-payments":%s,"kk-logs":%s}\n' \
  "$(date -Is)" "${api_status}" "${payments_status}" "${logs_status}" \
  > "${KK_HEALTH}/last-provision.json"

chown "${KK_LOGS_USER}:${KK_GROUP}" "${KK_HEALTH}/last-provision.json"
chmod 0640 "${KK_HEALTH}/last-provision.json"
success "Health check JSON written to ${KK_HEALTH}/last-provision.json"

# --- Verify ---
info "Phase 7 verification:"
if [[ -f "${KK_HEALTH}/last-provision.json" ]]; then
  verify_pass "health JSON file exists"
else
  verify_fail "health JSON file missing"
fi

if sudo -u "${KK_LOGS_USER}" cat "${KK_HEALTH}/last-provision.json" >/dev/null 2>&1; then
  verify_pass "health JSON readable by ${KK_LOGS_USER}"
else
  verify_fail "health JSON not readable by ${KK_LOGS_USER}"
fi

if grep -q '"timestamp"' "${KK_HEALTH}/last-provision.json"; then
  verify_pass "health JSON contains timestamp"
else
  verify_fail "health JSON missing timestamp"
fi

if grep -q '"kk-api"' "${KK_HEALTH}/last-provision.json"; then
  verify_pass "health JSON reports kk-api status"
else
  verify_fail "health JSON missing kk-api status"
fi

# ============================================================
# Phase 8: Final verification
# ============================================================
info "Phase 8: final verification (checking all phases)"

# Phase 1 artifacts
getent group "${KK_GROUP}" >/dev/null 2>&1 \
  && verify_pass "final: group ${KK_GROUP} exists" \
  || verify_fail "final: group ${KK_GROUP} missing"
for u in "${KK_API_USER}" "${KK_PAYMENTS_USER}" "${KK_LOGS_USER}"; do
  getent passwd "${u}" >/dev/null 2>&1 \
    && verify_pass "final: user ${u} exists" \
    || verify_fail "final: user ${u} missing"
done

# Phase 2 artifacts
[[ -d "${KK_BASE}" ]] \
  && verify_pass "final: base directory exists" \
  || verify_fail "final: base directory missing"
[[ "$(stat -c '%a' "${KK_CONFIG}")" == "750" ]] \
  && verify_pass "final: config mode 0750" \
  || verify_fail "final: config mode wrong"
getfacl -p "${KK_LOGS_DIR}" 2>/dev/null | grep -q '^default:group::rwx' \
  && verify_pass "final: default ACL on logs dir" \
  || verify_fail "final: default ACL missing"

# Phase 3 artifacts
! apt-mark showhold 2>/dev/null | grep -qx "curl" \
  && verify_pass "final: curl not held" \
  || verify_fail "final: curl is held"

# Phase 4 artifacts
ufw status 2>/dev/null | grep -q "22/tcp.*ALLOW" \
  && verify_pass "final: SSH allowed" \
  || verify_fail "final: SSH rule missing"
ufw status 2>/dev/null | grep -q "3001/tcp.*DENY.*Block external" \
  && verify_pass "final: payments port denied externally" \
  || verify_fail "final: external deny rule missing"

# Phase 5 artifacts
for svc in kk-api kk-payments kk-logs; do
  systemctl is-active "${svc}.service" >/dev/null 2>&1 \
    && verify_pass "final: ${svc}.service active" \
    || verify_fail "final: ${svc}.service not active"
done

p_score=$(systemd-analyze security kk-payments.service 2>/dev/null | tail -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
awk "BEGIN{exit !(${p_score} < 2.5)}" 2>/dev/null \
  && verify_pass "final: kk-payments score ${p_score} < 2.5" \
  || verify_fail "final: kk-payments score ${p_score} >= 2.5"

for svc in kk-api kk-logs; do
  s=$(systemd-analyze security "${svc}.service" 2>/dev/null | tail -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
  awk "BEGIN{exit !(${s} < 3.5)}" 2>/dev/null \
    && verify_pass "final: ${svc} score ${s} < 3.5" \
    || verify_fail "final: ${svc} score ${s} >= 3.5"
done

# Phase 6 artifacts
[[ -f /etc/logrotate.d/kijanikiosk ]] \
  && verify_pass "final: logrotate config present" \
  || verify_fail "final: logrotate config missing"
logrotate --debug /etc/logrotate.d/kijanikiosk >/dev/null 2>&1 \
  && verify_pass "final: logrotate --debug passes" \
  || verify_fail "final: logrotate --debug fails"

# Phase 7 artifacts
[[ -f "${KK_HEALTH}/last-provision.json" ]] \
  && verify_pass "final: health JSON exists" \
  || verify_fail "final: health JSON missing"

# --- Summary ---
echo
if [[ "${VERIFY_FAILED}" -eq 0 ]]; then
  success "==========================================================="
  success "ALL CHECKS PASSED — provisioning complete"
  success "==========================================================="
  exit 0
else
  error "==========================================================="
  error "${VERIFY_FAILED} CHECK(S) FAILED — provisioning incomplete"
  error "==========================================================="
  exit 1
fi
