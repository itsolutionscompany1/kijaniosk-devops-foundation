# Security Posture: KijaniKiosk Payments Node

**Prepared for:** Nia
**Prepared by:** Engineering
**Date:** 30 September 2026

---

Nia,

You asked for a foundation spec you can defend to the board. This document
explains, in plain language, the security decisions behind the dedicated
production node we are preparing for the payments service. It is not a
technical manual. It is the set of choices we made, why we made them, and
what they protect against. The technical identifiers are confined to the
table on the next page, where your engineers expect them.

## Summary

The payments service will run on its own dedicated node, isolated from the
rest of the platform. Every component on that node runs with the minimum
privileges needed to do its job. The server is locked down so that even if a
single component is compromised, the damage is contained rather than
spreading across the system. Audit trails are preserved. Network exposure is
minimal and deliberate. We can explain every open door on that server and why
it is open.

## What we hardened

We made eleven decisions that shape the security posture. Each one addresses
a specific risk. None of them are decorative — every one is enforced by the
operating system itself, not by policy alone.

| Control | What it does | Risk mitigated |
|---|---|---|
| Dedicated service accounts | Each service runs as its own unprivileged user with no shell and no home directory | Prevents a compromised service from acting as a shared or administrative user |
| Zero-capability posture | Services hold no Linux capabilities beyond what they explicitly need | Prevents a compromised service from performing privileged operations |
| Filesystem isolation | Services can read the system but cannot modify it | Prevents tampering with binaries, configs, and OS files after compromise |
| Home directory protection | Services cannot see or touch any user's personal directory | Prevents access to credentials and personal data on the server |
| Private temporary space | Each service gets its own isolated temporary directory | Prevents cross-service data leakage through shared temp files |
| Network isolation for payments | The payments service cannot reach or be reached by the network | Reduces the attack surface of the most sensitive service to zero |
| Kernel protection | Services cannot modify kernel parameters, modules, or logs | Prevents a service from compromising the operating system itself |
| System call filtering | Services can only invoke a pre-approved list of OS operations | Blocks entire classes of exploits that rely on unusual operations |
| Explicit device allowlist | Services can only access two specific virtual devices | Prevents a compromised service from touching hardware |
| Persistent audit logging | System events and service logs survive reboots | Ensures incident investigation is possible after a crash or restart |
| Firewall with documented intent | Only specific ports are open, and every rule has a stated purpose | Prevents accidental exposure of internal services |

## Why these decisions matter for the board

Three themes run through every choice above.

**Containment.** If one component is compromised, it should not be able to
reach the others, the operating system, or the user data on the server. Our
configuration enforces this at the kernel level.

**Least privilege.** No service runs with more power than it needs. The
payments service holds no capabilities, has no network access, and can only
invoke a specific set of operating system operations. It cannot do anything
that is not part of its job.

**Auditability.** When something goes wrong, we need evidence. System logs
persist across reboots. Every firewall rule is documented. The access model
is written down and enforced by the provisioning script — not applied by
memory during an incident.

## What the current posture does not protect against

Honesty is more credible than overclaiming. There are things this foundation
does not cover, and the board should know them.

**It does not protect against a compromised administrator account.** Anyone
with full administrative access to the server can override every restriction
described here. This is true of every system. What we can do is limit how
many accounts have that access and log every use of it.

**It does not protect against the application itself.** The hardening applies
to how the services run, not to what the application code does once it is
deployed. If the payments application has its own vulnerabilities, this
foundation will contain the blast radius but will not prevent the initial
exploit.

**It does not cover the rest of the platform.** This document describes the
payments node specifically. The user-facing API and the log-collection
service run under similar but not identical configurations. Extending the
same standard to every node in the platform is the natural next step.

**It does not yet protect against regional failure.** The current
configuration runs in a single region. We have designed for it, but not yet
built, a second region for disaster recovery. That work should be scheduled
before the payments service handles live customer volume.

If the board asks what our next investment in security should be, the answer
is: apply this same standard to the other nodes, then begin the second-region
work.

---

*End of document.*
