# Manual Provisioning Decisions — KijaniKiosk API Server

This document records every decision made when provisioning the KijaniKiosk API server manually. It is the input to the declarative specification in `desired-state-spec.md` and, ultimately, to the Terraform configuration built on Tuesday and Wednesday.

The VM was launched with Multipass on the local host. Each field in the table below is a decision that any provider — AWS, GCP, Azure, Multipass — requires the engineer to make explicitly.

## Decision table

| Decision | Value chosen | Reason |
|---|---|---|
| Provider | Multipass (local VM) | Course primary path. No cloud account required. Multipass uses QEMU on Linux and produces a real Ubuntu VM indistinguishable from a cloud instance at the configuration layer. |
| Region | Local host (Nairobi, Kenya) | Multipass VMs run on the local machine, so "region" maps to the physical location of the host. Conceptually equivalent to choosing a cloud region near the team. |
| Operating system | Ubuntu 22.04 LTS (jammy) | Matches the Week 3 target platform. LTS release for long-term support, security updates, and compatibility with the provisioning script from Week 3. |
| Instance type / size | 1 vCPU, 1 GB RAM | Smallest viable size for a staging API node. Matches AWS `t3.micro` free-tier equivalent. Enough for nginx and the API process without overprovisioning. |
| Disk | 5 GB | Minimum that fits the Ubuntu 22.04 base image plus package installation headroom. Larger than the base image (~2.5 GB) with room for logs and application code. |
| Network | NAT via Multipass bridge (10.32.18.62/24) | Multipass provides a default NAT network. The VM receives a private IP. This is the local equivalent of a VPC-private subnet in a cloud provider. |
| Subnet | 10.32.18.0/24 | Auto-assigned by Multipass. On a cloud provider this would be a subnet in a VPC chosen deliberately based on address-planning. |
| Security group / firewall | Default: SSH from host only | Multipass restricts inbound access to the host by default. On a cloud provider this would be an explicit security group allowing SSH (22) from the admin IP only, HTTP (80) from anywhere, and denying everything else. |
| SSH key pair | Host's default key used via `multipass shell` | Multipass injects the host user's SSH key on launch. On a cloud provider this would be a named key pair registered with the provider and referenced by name in Terraform. |
| Public IP | No — private IP only (10.32.18.62) | Multipass does not assign public IPs. The VM is reachable from the host and from within the NAT network only. On a cloud provider a public IP would be assigned for external SSH and HTTP access. |
| Tags / labels | `name: kijanikiosk-api` (Multipass VM name) | Single tag used as the VM identifier. On a cloud provider this would expand to Name, Environment, Service, and ManagedBy tags for filtering and cost attribution. |
| Purpose / role | Staging API server | This VM hosts the KijaniKiosk API service. It is the first of three servers (api, payments, logs) that Friday's pipeline will provision. |
| Environment | staging | Deployment environment tag. Matches Week 3 decisions and the Terraform variables planned for Tuesday. |

## Baseline state after provisioning

### Operating system

    Distributor ID: Ubuntu
    Description:    Ubuntu 22.04.5 LTS
    Release:        22.04
    Codename:       jammy

### Kernel

    Linux kijanikiosk-api 5.15.0-194-generic #204-Ubuntu SMP Wed Sep 2 13:09:23 UTC 2026 x86_64

### Disk layout

    Filesystem      Size  Used Avail Use% Mounted on
    tmpfs            96M  976K   95M   2% /run
    /dev/sda1       4.7G  1.9G  2.8G  41% /
    tmpfs           476M     0  476M   0% /dev/shm
    tmpfs           5.0M     0  5.0M   0% /run/lock
    /dev/sda15      105M  6.1M   99M   6% /boot/efi
    tmpfs            96M  4.0K   96M   1% /run/user/1000

### Memory

                   total        used        free      shared  buff/cache   available
    Mem:           951Mi       167Mi       128Mi       0.0Ki       655Mi       631Mi
    Swap:             0B          0B          0B

### Network

    2: ens3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP
        link/ether 52:54:00:1f:9a:0c brd ff:ff:ff:ff:ff:ff
        inet 10.32.18.62/24 metric 100 brd 10.32.18.255 scope global ens3

## What was NOT present after provisioning

The freshly provisioned VM has no application configuration. Specifically, it does NOT have:

- No service accounts (kk-api, kk-payments, kk-logs do not exist)
- No /opt/kijanikiosk/ directory
- No systemd unit files for KijaniKiosk services
- No ufw rules beyond the Multipass default (ufw is inactive)
- No nginx or other application packages installed
- No logrotate configuration for KijaniKiosk services
- No persistent journal configuration
- No health check directory

Every one of these becomes a Terraform resource (for infrastructure-level decisions) or an Ansible task (for configuration-level decisions) in the days ahead.

## The manual baseline

This document is the "what a human did" record. Tuesday's Terraform configuration will encode the infrastructure-level decisions from this table. Thursday's Ansible playbook will encode the configuration-level decisions that this VM does not yet satisfy.

The point of doing it by hand first is to know exactly what automation must produce — and what it must not accidentally produce.
