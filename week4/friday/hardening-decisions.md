# Security Posture: KijaniKiosk Staging Environment

**Prepared for:** Nia
**Prepared by:** Engineering
**Date:** 5 October 2026

---

Nia,

This document describes the security decisions behind the KijaniKiosk staging environment. It explains, in plain language, what we hardened, why, and what risks remain. You can use it to answer board questions about the platform's security posture without needing the technical detail in the table.

## What we built

The staging environment runs three servers: one for the public API, one for payments, and one for log collection. Every server is provisioned from a specification, not by hand. Every configuration change is stored in version control and reviewed like code. The two tools that do this work are used for different jobs: one creates the servers, the other configures what runs on them. Neither can silently drift from the specification because each run compares the intended state against the actual state and reports any difference.

## What we hardened

The table below lists eleven controls in place across the environment. Technical names appear in the first column, where your engineers expect them. The second column explains what each control does in plain terms. The third column states the specific risk it reduces.

| Control | What it does | Risk mitigated |
|---|---|---|
| Dedicated service accounts | Each service runs as its own unprivileged user with no shell and no home directory | Prevents a compromised service from acting as a shared or administrative user |
| Zero-capability posture | Services hold no operating-system privileges beyond what they explicitly need | Prevents a compromised service from performing administrative operations |
| Filesystem isolation | Services can read the system but cannot modify it | Prevents tampering with binaries, configuration, and system files after compromise |
| Home directory protection | Services cannot see or touch any user's personal directory | Prevents access to credentials and personal data stored on the server |
| Private temporary space | Each service gets its own isolated temporary directory | Prevents cross-service data leakage through shared temporary files |
| Network isolation for payments | The payments service cannot reach or be reached by the network | Reduces the attack surface of the most sensitive service to zero |
| Kernel protection | Services cannot modify kernel parameters, modules, or logs | Prevents a service from compromising the operating system itself |
| System call filtering | Services can only invoke a pre-approved list of operating-system operations | Blocks entire classes of exploits that rely on unusual operations |
| SSH key management | Access is controlled by cryptographic keys tied to individual engineers; password login is disabled | Prevents unauthorized access via stolen or guessed credentials |
| Firewall with documented intent | Only specific network ports are open, and every firewall rule has a stated purpose | Prevents accidental exposure of internal services |
| Remote state with audit trail | Infrastructure state is stored centrally and versioned; every change is recorded | Prevents two engineers from applying conflicting changes; provides a recoverable history |

## Why these decisions matter for the board

Three themes run through every choice above.

**Containment.** If one service is compromised, it should not be able to reach the others, the operating system, or the personal data on the server. Our configuration enforces this at the kernel level.

**Least privilege.** No service runs with more power than it needs. The payments service holds no operating-system privileges, has no network access, and can only invoke a specific set of operations. It cannot do anything that is not part of its job.

**Auditability.** When something goes wrong, we need evidence. All infrastructure changes are stored in version control with a full history. Every firewall rule is documented in the code that creates it. The state of the environment is stored centrally, so two engineers cannot accidentally make conflicting changes. This is what the board can point to when asked how the platform is governed.

## What the current posture does not protect against

Honesty is more credible than overclaiming. There are four things this foundation does not cover, and the board should know them.

**It does not protect against a compromised administrator account.** Anyone with full administrative access to the servers can override every restriction described here. This is true of every system. What we can do is limit how many accounts have that access and log every use of it. Additional work on this front is a natural next step.

**It does not protect against the application itself.** The hardening applies to how the services run, not to what the application code does once it is deployed. If the API or the payments application has its own vulnerabilities, this foundation will contain the blast radius but will not prevent the initial exploit. Application security reviews and testing are the correct place to address that risk.

**It does not yet cover the rest of the platform.** This document describes the staging environment for the three core services. A production deployment would have additional components — a load balancer, a database, a monitoring stack — each with its own security posture. The same standard should be applied to each before they carry real customer traffic.

**It does not protect against regional failure.** The current configuration runs in a single location. If that location fails, the environment fails with it. This is acceptable for staging. Before the production payments service carries live customer volume, a second region for disaster recovery should be built and tested.

If the board asks what the next investment in security should be, the answer is: apply this same standard to the rest of the platform's components, then begin the second-region work. Both are measurable, both are bounded, and both build on what already exists.

---

*End of document.*
