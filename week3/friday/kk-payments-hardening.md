# kk-payments Hardening Log

Iterative hardening of `kk-payments.service` from a minimal unit to a score
below the Requirement 6 threshold of 2.5.

**Target:** `systemd-analyze security kk-payments.service` < 2.5

**Final achieved:** 0.2 SAFE

---

## Starting point

The minimal unit, before any hardening directives:

    [Unit]
    Description=KijaniKiosk Payments Service
    After=network.target

    [Service]
    Type=simple
    User=kk-payments
    Group=kijanikiosk
    ExecStart=/usr/bin/sleep infinity
    Restart=on-failure

    [Install]
    WantedBy=multi-user.target

**Score:** `9.2 UNSAFE`

At this point the service runs as the correct user but inherits every default
capability, has full filesystem access, can allocate any socket, and does not
filter system calls. systemd flags 78 separate exposure items.

---

## Iteration 1: Filesystem, kernel, privilege restrictions

Directives added:

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

### What this batch does

- **ProtectSystem=strict** makes `/usr`, `/boot`, `/etc` read-only for the
  service. The service cannot write to system directories.
- **ProtectHome=true** hides `/home`, `/root`, `/run/user`. The service cannot
  read or write any user home directory.
- **PrivateTmp=true** gives the service its own isolated `/tmp` and `/var/tmp`.
- **PrivateDevices=true** removes access to hardware devices except the
  pseudo-devices it genuinely needs.
- **ProtectKernelTunables / ProtectKernelModules / ProtectKernelLogs** block
  writes to `/proc/sys`, `/sys`, kernel modules, and the kernel log buffer.
- **ProtectClock** prevents the service from setting the system clock.
- **ProtectProc=invisible / ProcSubset=pid** hide other processes from the
  service's `/proc` view.
- **NoNewPrivileges=true** prevents any privilege escalation via setuid.
- **RestrictSUIDSGID=true** prevents the service from creating SUID/SGID files.
- **UMask=0027** means files the service creates are not world-readable.

### Why this is safe for the payment stub

The current `ExecStart` is `/usr/bin/sleep infinity`. `sleep` writes nothing,
reads nothing except its own arguments, and needs no capabilities. Every
directive in this batch is compatible with it.

### Score after iteration 1

**6.0 MEDIUM** (down from 9.2)

---

## Iteration 2: Capabilities, network, namespaces, syscalls

Directives added:

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

### What this batch does

- **CapabilityBoundingSet=** (empty) removes every Linux capability from the
  service. It starts with none and cannot acquire any.
- **PrivateNetwork=true** gives the service its own empty network namespace.
  It cannot reach the network or be reached from it.
- **RestrictAddressFamilies=AF_UNIX** limits the service to Unix domain sockets.
  It cannot allocate internet sockets, netlink sockets, or packet sockets.
- **IPAddressDeny=any** blocks all IP traffic to or from the service. Belt and
  braces with PrivateNetwork.
- **RestrictNamespaces=true** blocks the service from creating any new namespace.
- **PrivateUsers=true** gives the service a private user namespace.
- **SystemCallArchitectures=native** prevents the service from making 32-bit
  compatibility syscalls on a 64-bit system.
- **SystemCallFilter=@system-service** allows only the standard set of syscalls
  a service needs.
- **SystemCallFilter=~@privileged @resources ...** additionally denies whole
  groups of risky syscall families.
- **SystemCallErrorNumber=EPERM** means blocked syscalls return a permission
  error rather than killing the process with SIGSYS.
- **MemoryDenyWriteExecute=true** blocks W+X memory mappings. This stops a
  whole class of exploits that write shellcode then jump to it.
- **DeviceAllow=/dev/null rw** and **DeviceAllow=/dev/urandom r** declare an
  explicit device allowlist. Since `PrivateDevices=true` hides most devices,
  this gives the service exactly what it needs and nothing else.

### Score after iteration 2

**0.2 SAFE** (down from 6.0)

---

## Directives investigated but rejected

Two directives were considered and deliberately not applied.

### Rejected: RootDirectory= / RootImage=

`RootDirectory=` chroots the service into a specified directory.
`RootImage=` uses a disk image as the root filesystem. Both would tighten
filesystem isolation further, and systemd flags them as 0.1 exposure.

**Why rejected:** We have no application root filesystem to point at. The
service runs a stub with no dependencies. Creating a minimal chroot just to
satisfy the metric would add operational complexity — the chroot would need
to contain a full libc, the sleep binary, and every library it links against,
and it would need to be rebuilt whenever the base system updates. The other
filesystem restrictions in Iteration 1 (ProtectSystem=strict, ProtectHome=true,
PrivateMounts=true) already provide strong isolation at a fraction of the
operational cost. This is a case where the directive would improve the number
without improving real security for this service.

### Rejected: ProtectHostname=true

`ProtectHostname=true` prevents the service from changing the system hostname.
systemd flags it as 0.1 exposure.

**Why rejected:** A service running as an unprivileged user with no
capabilities cannot change the hostname anyway. The capability required for
this (CAP_SYS_ADMIN) has already been removed by `CapabilityBoundingSet=`.
Adding `ProtectHostname=true` would be redundant — it would lower the score
slightly without changing the actual attack surface. Documenting this
rejection is more useful than the two-tenths of a point it would save.

### Note: PrivateNetwork=true is a stub-specific decision

`PrivateNetwork=true` is safe for the current `sleep infinity` stub. When the
real payments service is deployed, this directive must be relaxed to
`PrivateNetwork=false` (as we did for `kk-api.service`), because the service
needs to listen on port 3001 for the health check and for nginx proxying.
This is documented here so the next engineer does not treat the hardened score
as a permanent property of the service — it is a property of the current
implementation.

---

## Final unit file

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

---

## Final score

    → Overall exposure level for kk-payments.service: 0.2 SAFE

Service state: `active (running)`.

Requirement 6 (< 2.5) is met with a wide margin.

---

## Screenshot evidence

The checklist requires a screenshot of
`systemd-analyze security kk-payments.service` showing the final score below
2.5. Take this screenshot from the VM terminal after running:

    sudo systemd-analyze security kk-payments.service | tail -1

Expected output:

    → Overall exposure level for kk-payments.service: 0.2 SAFE

---

*End of kk-payments hardening log.*
