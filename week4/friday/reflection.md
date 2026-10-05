# Friday Reflection — Full IaC Pipeline

This reflection answers the three questions from the Friday brief and provides the paragraph written for Tendo's review of the pull request.

---

## Question 1: The Conflict Between Requirements

The conflict was between **Requirement 1's "no hardcoded values in resource blocks"** and the **Multipass primary path's reality that VM IPs come from `multipass list`, not from a Terraform provider**.

On the cloud path, Requirement 1 is clean: the Terraform provider knows the VM's public IP the moment it is created, and `terraform output` exposes it as a proper output value. The output feeds the Ansible inventory directly. Every value is dynamic — nothing is hardcoded.

On the Multipass path, Terraform does not create the VM. The VM is launched by `multipass launch` outside Terraform's control. Terraform's job is to *read* the IP and *connect* to the VM — not to provision it. So the IP is not an output of a Terraform resource; it is input that comes from outside Terraform's domain.

The tension: if we hardcode the IP in the inventory (to satisfy the brief's "Terraform provisions, Ansible configures" model), we violate the "no hardcoded values" rule. If we let Ansible read the IPs from `multipass list` directly, we lose the Terraform-→-inventory handoff that Requirement 3 demands.

**How we resolved it:** the `pipeline.sh` script handles the translation. It runs `terraform apply` (which reads the IPs via an `external` data source and stores them as outputs in Terraform's state file), then — separately — calls `multipass list` to extract the same IPs and writes them to `inventory.ini`. The inventory is a **generated artefact**, not a committed file with hardcoded values.

This is documented as a known deviation from the cloud path. On AWS, GCP, or any proper cloud provider, `terraform output -raw api_server_ip` would supply the IPs directly and `multipass list` would not be involved. The Multipass path is a learning substitute; the pipeline is written so the switch between paths is a one-line change (`PATH_MODE=multipass` vs `PATH_MODE=cloud`).

**What we learned:** the "no hardcoded values" principle is not about the *source* of values — it is about whether they are *declared in code* or *discovered at runtime*. A value read from `multipass list` at pipeline execution time is not hardcoded, even though it comes from outside Terraform. The principle survives the path substitution because the value is never committed to the repository.

---

## Question 2: Rewriting a Sentence for Tendo

The Nia document contains this sentence in the "Why these decisions matter" section:

> **"Containment.** If one service is compromised, it should not be able to reach the others, the operating system, or the personal data on the server. Our configuration enforces this at the kernel level."

Rewritten for Tendo:

> **"Containment via kernel-enforced isolation.** Each systemd unit runs with `PrivateNetwork=true` (or `RestrictAddressFamilies` limiting socket families), `ProtectSystem=strict`, and an empty `CapabilityBoundingSet`. A compromised `kk-api` process cannot open outbound sockets beyond its declared `RestrictAddressFamilies`, cannot write to `/etc` or `/usr` (read-only via `ProtectSystem=strict`), and cannot acquire any Linux capability. The kernel's namespace and capability checks enforce these boundaries regardless of what the process attempts. The blast radius of a compromise is confined to the process's own `/proc` view, its private `/tmp`, and the write paths declared in `ReadWritePaths`."

**What is lost in the translation:**

The Nia version is *decision-oriented* — it tells a board member "we thought about this and chose to enforce it." The Tendo version is *mechanism-oriented* — it tells an engineer exactly which directives produce the isolation and how they interact. The Nia version loses the specifics; the Tendo version loses the "why this matters to the business" framing that makes the decision defensible to non-engineers.

**What is gained in the translation:**

Precision and falsifiability. The Tendo version names specific directives. An engineer reading it can verify the claim by running `systemd-analyze security` on any of the units and confirming the score matches the description. The Nia version cannot be verified — a reader has to trust that "kernel-level enforcement" means what it says. The Tendo version is a testable assertion.

This is the fundamental tradeoff in technical communication: **the audience determines whether the value of a statement is its strategic justification or its operational specificity.** Nia needs the first; Tendo needs the second. Writing for one audience loses the other's value. Writing for both means writing two versions of every sentence — which is what this reflection is doing.

---

## Question 3: The Most Fragile Handoff

The most fragile handoff in the full pipeline is **the moment `pipeline.sh` reads IPs from `multipass list` and writes them to `inventory.ini`**.

Three things can go wrong at this single step:

**1. The VM exists but has no IPv4 address yet.** Immediately after `multipass launch`, a VM is `Running` but may not have an IPv4 assigned for several seconds. If `pipeline.sh` runs too quickly, `multipass info <vm> | awk '/IPv4/ {print $2}'` returns an empty string. The script detects this (it checks for empty `API_IP`, `PAYMENTS_IP`, `LOGS_IP`) and exits with code 2 — but the failure is a race condition, not a deterministic error.

**2. The IP changes between the `multipass list` call and the Ansible connection.** This is unlikely in a stable local environment, but on a cloud provider with dynamic IPs and floating IPs it is a real risk. If the IP changes, Ansible's `ping` fails with `No route to host`, and the entire playbook fails at the gathering facts stage.

**3. The inventory file is written but Ansible reads a cached copy.** Ansible caches inventory facts in `/tmp/ansible_facts` and in the `ansible-playbook` process memory. If two runs of `pipeline.sh` interleave (someone runs it twice in quick succession), the second run can read a stale inventory. This is documented as the reason for the "one pipeline at a time" assumption.

**What would make it robust in production:**

The handoff needs four properties that this pipeline does not have:

- **A readiness check.** Before reading the IP, `pipeline.sh` should poll `multipass info <vm>` until the VM reports `State: Running` *and* has a non-empty IPv4 address, with a timeout. This eliminates the race condition.
- **An identity verification.** After Ansible connects, a `assert` task should verify `ansible_hostname == expected_hostname`. This catches the case where the IP changed between the read and the connection — Ansible would land on the wrong machine and start configuring it.
- **A lock file.** `pipeline.sh` should create a lock (`flock`) at the start and release it at the end, refusing to run if a lock already exists. This prevents two runs from interleaving.
- **A retry loop.** Ansible's first `ping` should be inside a `retries: 5` block with `delay: 5`, so transient network failures are absorbed. The current playbook fails on the first failure with no retry.

**What I would need to know about the target environment:**

To make this handoff robust, I would need to know:

- **How long does the target hypervisor take to assign an IP?** On Multipass it is 5–30 seconds. On AWS EC2, a `public_ip` is available as soon as the instance reports `running`. On a network with DHCP, it can be longer.
- **Is the IP stable for the lifetime of the VM?** On Multipass, yes (until the VM is recreated). On AWS with an Elastic IP, yes. On AWS without an Elastic IP, no — the public IP changes on stop/start.
- **What is the expected concurrency?** A single-engineer workflow needs no locking. A team workflow needs `flock` or a proper coordination service (Consul, etcd).
- **What is the failure mode of the hypervisor's info command?** Does `multipass info` block when the daemon is busy, or return immediately with stale data? This determines whether the polling loop needs a timeout.

Without knowing those four things, the handoff is correct for this environment but not portable. That is the real fragility — not that the handoff breaks here, but that it breaks **quietly** in an environment where the assumptions do not hold.

---

## Tendo-Facing PR Description

This branch delivers the Week 4 Friday full IaC pipeline for KijaniKiosk's staging environment. The pipeline is orchestrated end-to-end by `pipeline.sh`, which runs `terraform apply` against the MinIO remote backend, extracts the three VM IPs from `multipass list`, writes them to a dynamically-generated `inventory.ini`, then runs the Ansible playbook that configures all three servers to Week 3 standards across seven phases (packages, service accounts, directory structure, systemd units, firewall, journal persistence, logrotate). The Terraform configuration uses an `app_server` module called with `for_each` over three server definitions, with no hardcoded values in resource blocks and all IPs resolved through an `external` data source at plan time. The second run of `pipeline.sh` demonstrates the pipeline is idempotent: Terraform reports `0 added, 0 changed, 0 destroyed`, and Ansible reports `changed=0` on all three hosts. The three servers score below their targets on `systemd-analyze security` (payments 0.2, api 1.3, logs 1.0), and the access model survives logrotate rotation. The Nia-facing `hardening-decisions.md` explains every security decision in plain language with an 11-row control table and an honest section on what the posture does not protect against. **The decision I am most confident about is keeping Terraform and Ansible in separate, non-overlapping domains** — Terraform owns infrastructure-level state, Ansible owns OS-level state, and the boundary between them is a hard line. This is what allowed the MinIO community-edition discontinuation (which forced a container substitution mid-week) to have zero impact on the Ansible work. **With more time, I would add a readiness gate to the pipeline's inventory-generation step**: a polling loop that waits for each VM to report a stable IPv4 address before writing the inventory, plus an Ansible `assert` task verifying the connected hostname matches the expected one. That single change would eliminate the pipeline's most fragile handoff — the assumption that a VM has a usable IP at the moment `multipass list` reports it as running.

---

*End of Friday reflection.*
