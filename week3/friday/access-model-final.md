# KijaniKiosk Access Model

**Final state, Week 3 Friday**

This document defines the directory ownership, permissions, and ACL model for
the KijaniKiosk production foundation. It is the reference the provisioning
script enforces and the model the team should preserve when adding new
components.

---

## Directory tree

    /opt/kijanikiosk/                (2750 root:kijanikiosk)
    config/                          (0750 root:kijanikiosk)
        *.env                        EnvironmentFiles for services
    shared/
        logs/                        (2770 root:kijanikiosk + default ACLs)
            *.log                    Service log files
    health/                          (2750 root:kijanikiosk)
        last-provision.json          Written by provisioning script Phase 7

---

## Ownership and mode

| Path | Mode | Owner | Group | Purpose |
|---|---|---|---|---|
| /opt/kijanikiosk/ | 2750 | root | kijanikiosk | Base. Setgid so new subdirs inherit the group. |
| /opt/kijanikiosk/config/ | 0750 | root | kijanikiosk | EnvironmentFiles. Read-only to group. |
| /opt/kijanikiosk/shared/logs/ | 2770 | root | kijanikiosk | Group-writable so services can write. Setgid + default ACLs. |
| /opt/kijanikiosk/health/ | 2750 | root | kijanikiosk | Health JSON. Read-only to group. |

### What each mode means

- 2750 = rwxr-x--- plus setgid bit. Owner full, group read+execute, others none.
- 0750 = rwxr-x---. Standard.
- 2770 = rwxrwx--- plus setgid bit. Group-writable because service accounts need to write logs.
- Setgid bit (the s in drwxr-s---): files created inside inherit the directory group.

---

## ACLs on shared/logs/

The shared/logs/ directory is the only one with ACLs. These make logrotate
rotated files compatible with the access model.

    # file: /opt/kijanikiosk/shared/logs
    # owner: root
    # group: kijanikiosk
    # flags: -s-
    user::rwx
    group::rwx
    other::---
    default:user::rwx
    default:group::rwx
    default:other::---

The default lines propagate to every new file created inside the directory,
including files created by logrotate.

### Why the default ACLs exist

logrotate create directive sets ownership and mode for new files. It does not
apply ACLs. When logrotate rotates kk-api.log:

1. It renames kk-api.log to kk-api.log.1
2. It creates a new empty kk-api.log with the mode from the create directive
3. The new file inherits the directory default ACLs automatically

Without the default ACLs, the new log file would have mode 0640 root:kijanikiosk
with no group-write. kk-api would not be able to write to it, and the service
would fail silently after the first rotation.

With the default ACLs, the new log file gets group rwx, so kk-api can write
immediately after rotation.

---

## The su directive in logrotate

logrotate refuses to operate on a directory that is group-writable unless the
config declares which user and group to use for rotation. The config includes:

    su root kijanikiosk

This tells logrotate to rotate as root, using group kijanikiosk for the new
files. Without this line, logrotate exits with an error about insecure parent
directory permissions.

---

## The health directory

The health/ directory is new in Week 3. It exists to hold structured JSON
output from the provisioning script Phase 7 health check.

- Written by: the provisioning script, running as root
- Read by: monitoring tools running as any member of group kijanikiosk
- Contents: last-provision.json with a timestamp and per-service status

Mode 2750 and ownership root:kijanikiosk means:

- Root can write it
- Any user in group kijanikiosk can read it
- No one outside the group can access it

The JSON file itself is mode 0640 and owned by kk-logs:kijanikiosk.

---

## Service account membership

The kijanikiosk group contains:

- kk-api
- kk-payments
- kk-logs

None of these accounts have a home directory or a login shell. They exist only
to run their respective services under systemd.

---

## What this model does not protect against

- Compromised root. Anyone with root access bypasses every restriction here.
- Directories outside /opt/kijanikiosk/. Services run with ProtectSystem=strict
  which makes the rest of the filesystem read-only, but data written to private
  service tmp directories is not covered by these ACLs.
- Network-level attacks. Firewall rules (Phase 4) restrict ports, but the
  access model itself only governs filesystem access.

---

*End of access model.*
