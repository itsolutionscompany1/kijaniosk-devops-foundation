# Environment Setup

This document records the exact tool stack used to build and run the KijaniKiosk IaC pipeline. It exists so the environment can be reproduced on another machine without verbal briefing, and so any deviation from the course reference environment is documented as a deliberate decision.

## Host

| Property | Value |
|---|---|
| Operating system | Ubuntu 22.04.5 LTS (jammy) |
| Kernel | 5.15.x |
| Hostname | medico-HP-EliteBook-840-G4 |

## Tool stack

| Tool | Version | Purpose |
|---|---|---|
| Terraform | 1.16.4 | Infrastructure provisioning and remote state management |
| Multipass | 1.16.4 | Local Ubuntu VM hypervisor (primary path) |
| Ansible | core 2.17.14 | Configuration management for the three servers |
| Docker | 29.8.1 | Container runtime for MinIO |
| MinIO (pgsty fork) | `pgsty/minio:latest` | S3-compatible remote state backend |
| Git | 2.34.1 | Version control |
| jq | 1.6 | JSON parsing for the Terraform external data source |
| Python | 3.10.x | Ansible runtime on target VMs; helper scripts on host |

## Ansible collections

| Collection | Version |
|---|---|
| community.general | 9.5.2 |
| ansible.posix | (built-in with ansible-core) |

The `community.general` collection provides the `ufw` module used in Phase 5 of the playbook.

## Terraform providers

| Provider | Version | Purpose |
|---|---|---|
| hashicorp/external | ~> 2.3 | Reads Multipass VM IPs dynamically |
| hashicorp/null | ~> 3.2 | Represents the SSH connection to each VM |

Pinned in `.terraform.lock.hcl`, committed to the repository for reproducible installs.

## Multipass VMs

| VM | Purpose | vCPUs | RAM | Disk |
|---|---|---|---|---|
| kijanikiosk-api | Public API server | 1 | 1 GB | 5 GB |
| kijanikiosk-payments | Payments service | 1 | 1 GB | 5 GB |
| kijanikiosk-logs | Log collector | 1 | 1 GB | 5 GB |

Each VM runs Ubuntu 22.04 LTS from the standard Multipass image.

## Known limitations and deviations from the course reference

### 1. MinIO community edition discontinued

The course materials reference `minio/minio` on Docker Hub and a binary from `dl.min.io`. Both were removed by MinIO in 2026 — Docker Hub images deleted, `dl.min.io` returns HTTP 410 Gone, and the GitHub repository was archived in February 2026. MinIO's official redirect is to their commercial AIStor product.

**Substitution:** This pipeline uses the community fork `pgsty/minio:latest`, which preserves the S3 API and CLI interface. The startup syntax required an adjustment: the fork's entrypoint wrapper did not accept `server /data --console-address :9001` directly, so the container is started with `--entrypoint /usr/bin/minio` to bypass the wrapper.

**Production recommendation:** Do not rely on a public Docker registry for a critical state backend. Pin a specific image digest and mirror it to a private registry under the organisation's control.

### 2. Multipass SSH key injection

The course materials state that Multipass VMs "accept SSH from the host machine without additional configuration." In this environment, that was not true — the host's `~/.ssh/id_rsa.pub` was not present in the VMs' `authorized_keys` after `multipass launch`. Every VM required an explicit injection step:

    cat ~/.ssh/id_rsa.pub | multipass exec <vm> -- bash -c "cat >> /home/ubuntu/.ssh/authorized_keys"

This is documented because it is exactly the kind of environmental difference that would break the pipeline on a fresh machine. The fix is one command per VM and is documented in the pipeline notes.

### 3. MinIO does not auto-start on boot

The MinIO container runs without systemd integration. After a host restart, the container must be restarted manually:

    sudo docker start minio

If MinIO is down when Terraform runs, the S3 backend is unreachable and `terraform plan` fails with a connection error. This is a **single point of failure for the pipeline** and is documented in the reflection as the most fragile handoff.

**Production recommendation:** Run the state backend under systemd or a container orchestrator, with health checks and restart policies. MinIO's documentation provides a systemd unit for this purpose.

### 4. Docker permissions

Docker requires `sudo` on this host because the `medico` user is not in the `docker` group. To remove this requirement:

    sudo usermod -aG docker $USER
    newgrp docker

The permanent fix is not applied because it requires a logout and login cycle. This is a cosmetic limitation — `sudo docker` works fine.

### 5. State locking

MinIO's S3-compatible API does not provide state locking natively. Terraform's S3 backend uses a lock file by default, but without a coordination service (DynamoDB on AWS, or Consul as a vendor-agnostic option) two engineers running `terraform apply` simultaneously could still conflict.

For a single-engineer staging environment this is acceptable. Production deployments should use one of:

- **AWS S3 + DynamoDB** — DynamoDB provides the lock table
- **Google Cloud Storage** — built-in locking, no separate resource needed
- **HashiCorp Consul** — vendor-agnostic locking for any backend

This limitation is documented in `hardening-decisions.md` as required by the Friday brief.

### 6. Terraform backend deprecation warnings

Terraform 1.16 prints warnings for two backend parameters that are deprecated but still functional:

- `endpoint` → use `endpoints.s3` instead
- `force_path_style` → use `use_path_style` instead

Both have been updated in `main.tf` to the modern form, so the warnings no longer appear.

## Reproducing this environment

To rebuild from scratch on a fresh Ubuntu 22.04 host:

1. Install Terraform 1.16+, Multipass, Ansible 2.17+, Docker, jq, git
2. Install the `community.general` Ansible collection
3. Launch three Multipass VMs (api, payments, logs) with 1 vCPU, 1 GB RAM, 5 GB disk
4. Inject the host's SSH public key into each VM's `authorized_keys`
5. Start MinIO (via the `pgsty/minio` fork or a locally hosted equivalent) with a persistent volume
6. Create the `kijanikiosk-tfstate` bucket through the MinIO console or the S3 API
7. Clone the repository and run `pipeline.sh` from `week4/friday/ansible/`

Every step above is captured in the repository. No step requires knowledge that lives only in an engineer's memory.

---

*End of environment setup.*
