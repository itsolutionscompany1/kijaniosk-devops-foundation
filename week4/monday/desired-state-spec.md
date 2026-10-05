# KijaniKiosk API Server — Desired State Specification

This is the declarative specification for the KijaniKiosk API server. It is written in provider-agnostic terms. Tuesday's Terraform configuration will translate each section into HCL. Thursday's Ansible playbook will satisfy the configuration-level requirements.

The companion document `manual-provisioning-decisions.md` records the choices made when provisioning this VM by hand. This document states the same requirements as a specification — what should exist, independent of how it was created.

## Identity

- **Name:** kijanikiosk-api-staging
- **Environment tag:** staging
- **Owner tag:** amina
- **Service tag:** api
- **Managed by:** terraform (once provisioned via IaC)

## Compute

- **Provider:** Multipass (primary path); equivalent cloud providers: AWS, GCP, DigitalOcean, Hetzner
- **Region:** Local host; cloud equivalent: closest region to Nairobi, Kenya
- **Instance type:** 1 vCPU, 1 GB RAM
- **Operating system:** Ubuntu 22.04 LTS (jammy)
- **Image ID:** Resolved dynamically via data source (Multipass image or cloud provider's image lookup). NOT hardcoded.

## Networking

- **Network:** Multipass default NAT; cloud equivalent: a VPC and a public subnet within it
- **Address:** Assigned by Multipass at launch (currently 10.32.18.62/24); cloud equivalent: dynamic public IP assigned by the provider
- **Assign public IP:** No (Multipass provides private IP only); cloud equivalent: yes for staging API nodes
- **DNS hostname:** kijanikiosk-api (internal)
- **Dynamic IP resolution:** The IP must be read from `multipass list` (or `terraform output` on the cloud path) at runtime, never hardcoded.

## Access Control

- **SSH access:** port 22, source = the machine running Ansible only (the operator's IP). Not 0.0.0.0/0.
- **HTTP access:** port 80, source = 0.0.0.0/0 (public web traffic)
- **All other inbound:** deny
- **All outbound:** allow

## Storage

- **Root volume:** 5 GB, default Multipass storage
- **Additional volumes:** none required for staging

## Authentication

- **SSH key pair name:** the host's default key, injected by Multipass at launch
- **Cloud equivalent:** a named key pair registered with the provider (e.g. `kijanikiosk-staging-key`), referenced by name in the Terraform configuration
- **Password authentication:** disabled (Multipass default; cloud providers disable by default)

## Tags / labels

| Tag | Value | Purpose |
|---|---|---|
| Name | kijanikiosk-api-staging | Human-readable identifier |
| Environment | staging | Environment filtering and cost attribution |
| Service | api | Service role identification |
| ManagedBy | terraform | Indicates IaC management (once Tuesday's configuration runs) |
| Owner | amina | Owner identification for escalations |

## What must NOT exist on this server after provisioning

This section is as important as the positive requirements above. A complete desired-state specification records what should be absent.

- **No default password authentication.** SSH must be key-based only. Password authentication must be disabled in the SSH daemon configuration.
- **No services listening other than sshd** at the infrastructure level. Application services (nginx, kk-api) are added on Thursday by Ansible, but Terraform must not open any additional ports beyond SSH and HTTP.
- **No world-writable directories** outside `/tmp` and other standard system locations.
- **No root login over SSH.** Direct root SSH access must be disabled.
- **No unmanaged changes.** Every resource on this server should be traceable to Terraform (infrastructure) or Ansible (configuration) — not applied by hand.
- **No hardcoded IPs or credentials** in any committed configuration file.
- **No state file committed** to the repository.

## Open questions (things that will need decisions before Terraform can encode this)

These are the places where the manual decisions were not fully confident and where Terraform will force an explicit choice:

1. **SSH source IP.** The manual decision was "from the operator's machine only." On Tuesday, this becomes a variable with the operator's IP as a value, but the value will change if the operator moves networks. Should the variable accept a list of CIDR blocks, or a single IP? A list is more flexible but more verbose in HCL.

2. **Instance type for the payments and logs servers.** The api server is 1 vCPU / 1 GB. The brief for Week 4 allows the logs server to be a smaller size (the `t2.nano` example in the content pages). The final choice for each of the three servers will be made when the `for_each` map is written on Wednesday.

3. **Image resolution strategy.** Multipass resolves the OS image from the version string "22.04" at launch. On the cloud path, an image data source is needed. The Multipass path does not have a first-class data source in the same way — it uses the `external` data source or a shell provisioner. The exact mechanism will be decided Tuesday.

4. **Public IP vs. private IP for Multipass.** Multipass assigns a private IP on the host's NAT network. Other machines on the same LAN cannot reach it. This is fine for a local development environment but does not model a real staging environment. Documenting the limitation is part of the spec; the cloud path is the fix.

5. **State locking mechanism.** Multipass has no equivalent to the DynamoDB table for S3 state locking on AWS. On Wednesday, when the state moves to MinIO, the locking limitation will be documented. The team needs to decide whether to accept the limitation for staging (single-writer assumption) or add Consul for vendor-agnostic locking.

## Cross-reference check

Every value in this spec was verified against the actual running Multipass VM on 2026-10-04:

| Field | Spec value | Actual VM value | Match |
|---|---|---|---|
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04.5 LTS | Yes |
| Kernel | (not specified) | 5.15.0-194-generic | N/A |
| CPU | 1 vCPU | 1 vCPU (launch flag) | Yes |
| Memory | 1 GB | 951 MiB | Yes |
| Disk | 5 GB | 4.7 GB usable (5 GB allocated) | Yes |
| IP | Dynamic | 10.32.18.62 | Yes (currently) |
| User | ubuntu | ubuntu | Yes |

## Hardest Decision and Why

The hardest decision was **where to draw the line between "infrastructure" and "configuration"** in this specification.

Both words feel interchangeable until you start classifying individual items. Is installing a package infrastructure or configuration? Is creating a service user infrastructure or configuration? The answers matter because they determine whether the item becomes a Terraform resource (Tuesday-Wednesday) or an Ansible task (Thursday) — and getting it wrong means either fighting Terraform to do something it is bad at, or duplicating work across both tools.

The clearest boundary I found is the one the course teaches: **Terraform manages things that exist as API objects in a provider** — VMs, networks, security groups, storage volumes. **Ansible manages things that exist inside the operating system** — users, files, packages, services, firewall rules inside the VM. By that rule, the VM itself is Terraform's concern, but every KijaniKiosk service account, directory, unit file, and firewall rule is Ansible's concern.

The uncertainty came when I considered the security group. In a cloud environment, a security group is a provider API object — Terraform. But inside a Multipass VM, the equivalent is ufw, which is an operating system feature — Ansible. Same conceptual role, different layer, different tool. This is why the spec needs both a "security group" entry (Terraform, cloud path) and a "ufw rules" entry (Ansible, all paths). Documenting the split explicitly is what prevents the wrong tool from being used for the wrong job.
