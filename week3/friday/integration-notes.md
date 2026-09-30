# Integration Notes

This document records the resolution of the four integration challenges
identified in the Week 3 Friday brief. Each entry states what the conflict
was, what options were considered, what was chosen, and why.

---

## Challenge A: ProtectSystem=strict and the EnvironmentFile

### The conflict

`ProtectSystem=strict` makes `/usr`, `/boot`, `/etc`, and `/lib` read-only
for a service process. If the service's `EnvironmentFile` lives under `/etc`,
the service cannot read it, and it fails to start with a message about being
unable to open the environment file — not a clear permissions error, which
makes this slow to debug.

### Options considered

1. **Move the EnvironmentFile to `/opt/kijanikiosk/config/`** and add
   `ReadOnlyPaths=` or rely on the default read permission. `/opt` is not
   covered by `ProtectSystem=strict`, so files there are readable normally.
2. **Keep the EnvironmentFile under `/etc/kijanikiosk/`** and add
   `ReadOnlyPaths=/etc/kijanikiosk/` to the unit. This explicitly allows the
   read that `ProtectSystem=strict` would otherwise block.
3. **Disable ProtectSystem=strict** to make `/etc` writable again. This was
   rejected immediately — it gives up a large portion of the hardening.

### Chosen

Option 1. The EnvironmentFile path is `/opt/kijanikiosk/config/payments-api.env`.
The `/opt` tree is not under any protection directive from `ProtectSystem=strict`,
so the service can read its environment file without additional directives.

### Why

Option 1 keeps the unit file simpler and places the config in the same
directory tree as the rest of the KijaniKiosk application data. All KijaniKiosk
paths are under `/opt/kijanikiosk/`, which makes the boundary between "system
territory" and "application territory" clear. If we later want to apply
stricter read protections on the config directory (e.g. `ReadOnlyPaths`), we
can add them without changing the overall layout.

Option 2 would also work but adds a directive for no benefit — the config
would live in `/etc` with everything else, and every future config file would
need its own `ReadOnlyPaths=` entry.

---

## Challenge B: The monitoring user and ACL defaults

### The conflict

Requirement 1 asks for a health check that writes JSON to
`/opt/kijanikiosk/health/last-provision.json`. The provisioning script runs
as root, so the file would be owned by root by default. But the monitoring
system and Amina's regular user need to read the file without `sudo`. The
access model from earlier in the week defines who can read what under
`/opt/kijanikiosk/`, but the health directory is new — it was not part of
that model.

### Options considered

1. **Own the file by root, mode `0644`** so anyone can read it.
2. **Own the file by `kk-logs:kijanikiosk`, mode `0640`** so only the
   `kijanikiosk` group can read it.
3. **Own the file by root:kijanikiosk, mode `0640`** and use ACLs on the
   health directory to grant the monitoring group read access.

### Chosen

Option 2. The script writes the file, then runs:

    chown kk-logs:kijanikiosk /opt/kijanikiosk/health/last-provision.json
    chmod 0640 /opt/kijanikiosk/health/last-provision.json

The health directory itself is mode `2750 root:kijanikiosk`, so group
members can traverse it.

### Why

Option 1 is too permissive — a health file containing timestamps and service
statuses is not sensitive, but making it world-readable contradicts the
least-privilege posture we are establishing everywhere else.

Option 3 is the most flexible but adds ACL complexity for a file that will
never be written by more than one process. The `kijanikiosk` group already
has the users who need access. Simple ownership is enough.

Option 2 was chosen because it matches the existing access model: everything
under `/opt/kijanikiosk/` is owned by root or a service account, in group
`kijanikiosk`, with mode restricting access to the group. The `kk-logs`
account is the natural owner because log collection and monitoring are the
same functional area.

---

## Challenge C: logrotate postrotate and PrivateTmp

### The conflict

The logrotate config needs a `postrotate` script that signals the log-writing
service to reopen its log file handles after rotation. The standard pattern is:

    postrotate
        systemctl reload kk-logs.service
    endscript

But `systemctl reload` only works if the service unit has an `ExecReload=`
directive. Our `kk-logs.service` does not, because the current service runs
`sleep infinity` — it has nothing to reload. Running `systemctl reload` on
a unit without `ExecReload` fails, which would make the postrotate command
fail on every rotation.

Additionally, `kk-logs.service` has `PrivateTmp=true`. The concern was whether
a signal sent from outside the service (by logrotate, running as root via cron)
could reach the process inside the service's private namespace.

### Options considered

1. **`systemctl kill -s HUP kk-logs.service`** — sends SIGHUP directly to the
   service's main process. Works even without `ExecReload`.
2. **`systemctl reload kk-logs.service`** — only works if `ExecReload=` is
   defined. Would require adding `ExecReload=/bin/kill -HUP $MAINPID` to the
   unit.
3. **`systemctl restart kk-logs.service`** — heavy-handed. Restarting a
   log-collection service on every rotation could drop log entries.

### Chosen

Option 1, with a `|| true` fallback:

    postrotate
        systemctl kill -s HUP kk-logs.service 2>/dev/null || true
    endscript

### Why

Option 1 works regardless of whether the service implements `ExecReload`. It
sends SIGHUP to the service's main process, which is the standard signal for
"reopen your log files." The signal is sent from the logrotate process running
as root outside the service's namespace, so `PrivateTmp=true` does not
interfere — the signal goes to the process, not to the filesystem.

The `|| true` at the end means the postrotate script will not fail the overall
rotation if the signal delivery has an issue. That is intentional: the log
rotation itself is more important than the signal, and a future version of
`kk-logs.service` with a real application will define `ExecReload=` properly.

Option 2 would also work but requires anticipating the future shape of the
service. Option 3 risks dropping logs.

---

## Challenge D: The dirty VM and package holds

### The conflict

When the provisioning script runs on Friday's dirty VM, packages are already
installed — possibly at versions different from the pinned version, and
possibly with `apt-mark hold` set from earlier in the week. The naive script
would either:

- Fail silently when `apt-get install` encounters a held package, or
- Attempt a downgrade when the installed version is newer than the pin, and
  succeed — silently breaking the assumption that the script produces the
  same state on every run.

### Options considered

1. **Detect the hold, remove it, and fail loudly if the version does not
   match the pin.** Manual intervention required.
2. **Detect the hold, remove it, and force-downgrade to the pin.** Automatic
   convergence, but potentially disruptive to a running system.
3. **Detect the hold and refuse to proceed** until a human removes it.

### Chosen

Option 1. The script:

    if apt-mark showhold | grep -qx "curl"; then
      apt-mark unhold curl
    fi

    installed_curl_version=$(dpkg-query -W -f='${Version}' curl)
    if [[ "${installed_curl_version}" != "${CURL_PIN}" ]]; then
      warn "curl version ${installed_curl_version} does not match pin ${CURL_PIN}"
      error "Package version drift detected. Resolve manually and re-run."
      exit 2
    fi

### Why

Option 2 (auto-downgrade) is dangerous in production. A running service may
depend on a specific version of a library; silently downgrading the package
could crash it. The choice between "keep the current version" and "downgrade
to the pin" is a human decision that depends on why the version changed.

Option 3 (refuse to proceed) is close to Option 1 but less useful — the hold
is often a legitimate leftover that the script can cleanly remove; refusing to
touch it is unhelpful.

Option 1 was chosen because it distinguishes between two different situations:

- A **hold** is a configuration the script owns and can remove.
- A **version mismatch** is a state change the script did not cause and
  cannot safely undo.

The script's job is to converge the system to the intended state. If
convergence requires a decision the script cannot make safely, it should
escalate — and `exit 2` with a clear error message does that.

---

*End of integration notes.*
