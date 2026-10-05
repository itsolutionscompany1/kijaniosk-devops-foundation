# Wednesday Reflection — Modules, State, and Remote Backends

Wednesday's lab refactored Tuesday's single-server configuration into a reusable module called with `for_each` across three servers, migrated state to a remote S3-compatible backend (MinIO), and demonstrated drift detection. The reflection below answers the four questions from Wednesday's pages, referencing the actual configuration and behaviour observed during the lab.

---

## Question 1: The Module Boundary Decision

The `app_server` module encapsulates the VM itself and the SSH connection to it. The root module owns the `servers` map (`api`, `payments`, `logs`) and the module call with `for_each`. Networking stayed in the root for one reason: on the Multipass primary path, there is no network to own. The VMs are launched outside Terraform on a shared NAT network. If we were using a cloud provider, the VPC, subnets, route tables, and security groups would be candidate candidates for a separate `networking` module — but they would still stay separate from `app_server`, not combined.

The reasoning: a VM module should describe one unit of compute. It should not know about the network topology it sits in. That way, the same VM module can be called from a production network or a staging network without any change to the module itself. The network is an input to the module (a subnet ID), not something the module creates.

Where would it make sense to extract networking? On a cloud provider, when the same VPC is used by multiple root configurations — a database stack, an application stack, a monitoring stack. Then the networking module becomes a shared library, and each stack references it via a data source or a remote state output. This is a real pattern, but it is not needed for a single staging environment.

The risk of combining networking and VMs in one module: if a developer runs `terraform destroy -target=module.networking`, the network is destroyed but the VMs are orphaned. They keep running, unreachable from outside, and Terraform's state is now split between what remains and what was destroyed. Extracting networking into its own module forces you to be explicit about destroying it — and about the dependency between the two.

---

## Question 2: for_each Removal Behaviour

When adding a new server type to the `servers` map — for example, a `cache` entry:

    cache = { vm_name = "kijanikiosk-cache" }

Terraform runs `plan` and shows:

- One new module instance: `module.app_servers["cache"]`
- Its `null_resource.this` will be created
- The other three instances (`api`, `payments`, `logs`) show no changes

On apply, Terraform creates only the cache resource. The existing three are untouched.

Now consider the same scenario using `count = 3` changed to `count = 4`. `count` addresses resources by index: `module.app_servers[0]`, `[1]`, `[2]`. If you insert a new server in the middle — say you wanted the map order to be `api, cache, payments, logs` — the indices of `payments` and `logs` shift. Terraform sees:

- `[2]` changed from `logs` to `payments` (destroy and recreate)
- `[3]` is a new resource (create)
- The old `logs` at `[3]`... actually it stays if you add at the end

The critical case is removal. Remove `payments` (the middle entry) from a `count`-based configuration and Terraform sees:

- `[1]` changed from `payments` to `logs` — destroy and recreate
- `[2]` removed entirely — destroy

The `logs` server is destroyed and recreated because its index shifted from 2 to 1. That is unnecessary downtime caused purely by addressing.

With `for_each`, removing `payments` from the map causes only `module.app_servers["payments"]` to be destroyed. The other two keep their keys and their state — no recreation.

**The rule:** use `for_each` whenever resources have distinct identities (api, payments, logs). Reserve `count` for truly interchangeable resources where "the third replica" is the same as "the second replica" — like identical web servers behind a load balancer.

---

## Question 3: State as a Team Artefact

When two engineers run Terraform against the same remote backend at the same time, the backend acquires a lock when the first `apply` starts. The second engineer's `apply` (or `plan`) fails immediately with a lock error rather than running and potentially corrupting state.

The lock error contains:

- **ID** — a UUID identifying the specific lock
- **Path** — the state file path in the backend (`staging/terraform.tfstate`)
- **Operation** — `OperationTypeApply` or `OperationTypePlan`
- **Who** — the user and host that acquired the lock (`medico@medico-HP-EliteBook`)
- **Version** — Terraform version
- **Created** — timestamp of when the lock was acquired

The `Who` and `Created` fields are the most useful for diagnosis: they tell you exactly who is holding the lock and for how long. If the operation looks stuck, you can contact that user. If the process is genuinely dead, you can clear the lock with `terraform force-unlock LOCK_ID`. Never use `-lock=false` to bypass a lock — it can corrupt the state file.

**The crash scenario:** Amina's apply provisions two of three servers, then her laptop loses power. The state file was written after each resource creation — Terraform writes state incrementally, not just at the end. So after two successful creates, the state file contains two entries. The third may be partially created in the real infrastructure but not recorded in state.

On the next run, Terraform reads the state, sees two resources it knows about, and plans to create the third. If the third resource is already present in reality (partial create), Terraform will attempt to create it again and fail because the resource name is taken. The correct recovery is:

1. Identify the orphaned resource (the one that exists but isn't in state)
2. Import it: `terraform import module.app_servers["logs"].null_resource.this <id>` (for a null_resource, the id is a hash — harder to import) or use an import block
3. Run `terraform plan` to confirm zero changes
4. Continue

For a null_resource, this is actually simple — the third server is just a connection check, so it's safe to recreate. For a real VM, importing is critical to avoid orphaning the running server.

The important lesson: **the state file is a shared artefact, not a local cache.** It needs a remote backend with locking, and it needs incremental writes so a crash mid-run doesn't lose information about what was already created.

---

## Question 4: What Three Provisioned VMs Cannot Do

At the end of Wednesday, three VMs exist in the local Multipass environment. They run Ubuntu 22.04 with the default image configuration. They have:

- No application code
- No service accounts (`kk-api`, `kk-payments`, `kk-logs` do not exist)
- No `/opt/kijanikiosk/` directory tree
- No systemd unit files for KijaniKiosk services
- No ufw firewall rules beyond the Multipass default
- No logrotate configuration
- No persistent journal configuration

Terraform cannot configure any of these things directly, for one architectural reason: **Terraform manages things that exist as API objects in a provider.** A VM is a provider API object — Terraform can create, modify, and destroy it. A systemd unit file is a file inside the VM's filesystem — Terraform has no API to talk to it. The provider talks to the hypervisor, not the operating system.

To install nginx on one of these VMs using only Terraform, you would use a `remote-exec` provisioner or a `file` provisioner:

    resource "null_resource" "install_nginx" {
      connection { ... }
      provisioner "remote-exec" {
        inline = [
          "sudo apt-get update",
          "sudo apt-get install -y nginx",
        ]
      }
    }

This works, but it has real tradeoffs:

1. **Not idempotent.** Running `remote-exec` twice runs the commands twice. `apt-get install nginx` is idempotent, but the second run still executes it. Terraform's plan doesn't know whether nginx is already installed — it just runs the commands whenever the trigger changes.
2. **No state tracking.** If someone uninstalls nginx manually, Terraform won't know. There's no "drift detection" for a provisioner's side effects — only for resources that have explicit attributes.
3. **Fragile.** If the SSH connection fails midway through a multi-step provisioner, some commands run and some don't. Terraform marks the resource as tainted and re-runs the whole provisioner on the next apply, potentially creating duplicates.
4. **No modularity.** Installing nginx, creating a user, writing a config file, and starting a service would all be separate `remote-exec` blocks with no shared variables or reusable pattern.

Ansible solves all four of these. Ansible tasks are idempotent by design — `ansible.builtin.apt: name=nginx state=present` is a declaration, not a command. The second run reports `ok` instead of `changed`. Ansible has handlers that restart services only when configuration changes. It has templates that produce config files with the right variables filled in. It has group_vars and host_vars to parameterise across multiple servers.

**Terraform provisions the infrastructure. Ansible configures what runs on it.** Trying to make Terraform do Ansible's job produces fragile, non-idempotent, hard-to-maintain configuration. That is exactly why Thursday exists.

---

## Bonus: The MinIO Supply-Chain Incident

One thing Wednesday's lab exposed that the course materials do not anticipate: **MinIO's community edition was discontinued in 2026.** The `minio/minio` Docker image was removed from Docker Hub, `dl.min.io` returns HTTP 410 Gone, and the GitHub repository was archived in February 2026. MinIO's official redirect is to their commercial AIStor product at approximately $96,000/year.

This broke the lab's specified approach (run `minio/minio` in Docker) mid-course. The fix was to use the community fork `pgsty/minio` on Docker Hub, which preserves the S3 API and works identically with Terraform's S3 backend. The startup syntax differed slightly — the fork's entrypoint wrapper did not accept `server /data` the way the original did, so we used `--entrypoint /usr/bin/minio` to bypass it.

This is a real-world supply-chain issue: an infrastructure component with no announcement, removed from public distribution, forcing an unplanned substitution. It is documented here because the Friday brief asks about "the single most fragile handoff" — and a dependency on a tool whose upstream distribution can be discontinued at any time is exactly that kind of fragility. Production deployments using MinIO would need to pin a specific version and host it in their own private registry, not rely on Docker Hub or the vendor's CDN.

The state migration itself worked correctly: after `terraform init -migrate-state`, the local `terraform.tfstate` was emptied, the state was written to the `kijanikiosk-tfstate` bucket at `staging/terraform.tfstate`, and `terraform state list` returned all six entries (three data sources, three resources) read from the remote backend. The subsequent `terraform destroy` also ran via the remote backend, confirming end-to-end functionality.
