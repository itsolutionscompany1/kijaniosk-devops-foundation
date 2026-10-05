# Thursday Reflection — Ansible Configuration Management

Thursday's lab converted the Week 3 bash provisioning script into an Ansible playbook that configures all three KijaniKiosk servers. The playbook covers seven phases — packages, service accounts, directory structure, systemd units, firewall, journal persistence, and logrotate — and is idempotent: the second run reports `changed=0` on all three hosts. The reflection below answers the four questions from Thursday's pages.

---

## Question 1: Ansible's Idempotency Model

Ansible decides whether a task is a change by asking the target system a question, not by trusting the playbook author. Every module has a "desired state" that it compares against the current state and reports one of three outcomes: `ok` (no change needed), `changed` (state was modified), or `failed` (state could not be reached).

For example, the `ansible.builtin.apt` module with `state: present` does the following:

1. Queries the package database for the named package
2. If the package is installed at any version, reports `ok`
3. If the package is absent, installs it and reports `changed`

The playbook does not need a guard condition like `dpkg -l nginx || apt-get install -y nginx` — the module itself performs the equivalent check and only acts when necessary. This is what the second run demonstrated: every task reported `ok` because the desired state was already present.

Compare this to Week 3's bash script. Every phase needed an explicit guard: `if ! getent group kijanikiosk; then groupadd ...; fi`, `if apt-mark showhold | grep -qx "curl"; then apt-mark unhold curl; fi`, and so on. The guard conditions were written by hand, and every new command required a new guard. The script was idempotent, but only because we wrote the guards explicitly.

Ansible moves the idempotency from the playbook author into the module. The `user`, `group`, `file`, `template`, `systemd`, and `ufw` modules all follow the same pattern: query, compare, act only if needed. That is why the playbook is 259 lines versus the ~700 lines of the bash script — a substantial portion of the bash script was guard logic that Ansible handles natively.

The tradeoff: Ansible's idempotency is only as good as the module's check. If a module has a bug, or if the desired state is expressed ambiguously (e.g. `state: latest` for a package, which upgrades if a newer version exists), the idempotency guarantee is weaker. This is why the playbook uses `state: present` everywhere instead of `state: latest` — `present` is idempotent, `latest` is a deliberate rolling-upgrade directive.

---

## Question 2: The Terraform-Ansible Boundary

The boundary is between what exists at the provider API level and what exists inside the operating system.

Terraform manages API objects — resources a provider knows how to create, read, update, and delete through its API. On the Multipass path this is minimal (a `null_resource` that tracks the connection), but on the cloud path it includes VMs, networks, security groups, and volumes. Terraform's domain is "what infrastructure exists."

Ansible manages OS-level state — files, users, packages, services, and firewall rules. Its domain is "what runs on that infrastructure." A systemd unit file is not an API object; it is a file on disk. Terraform has no direct way to talk to a systemd unit. Ansible does, through the `systemd` module.

Terraform's `remote-exec` provisioner can technically install packages and write files. But it does so by running shell commands, and the resulting state is invisible to Terraform. If you change a systemd unit with `remote-exec`, the next `terraform plan` shows no change (because Terraform doesn't track the unit's content — only whether the provisioner's trigger changed). And the provisioner does not have a natural idempotent model — it runs whenever the trigger changes, not when the desired state differs from reality.

Ansible's `template` module does the opposite. It renders the file, computes a checksum, compares to the target's current checksum, and only writes the file if they differ. This is genuinely idempotent — running the playbook twice writes the file zero times on the second run.

The correct division: Terraform provisions the infrastructure, Ansible configures what runs on it. Trying to make Terraform do Ansible's job produces non-idempotent, hard-to-maintain configuration.

---

## Question 3: Handlers

Handlers are tasks that fire only when they are notified by another task's `changed` outcome. The playbook has three:

- `Reload systemd` — notified by the "systemd unit file is present" task
- `Restart kk service` — notified by the "systemd unit file is present" and "environment file is present" tasks
- `Restart journald` — notified by the "configure persistent journal" task

The behaviour: when a task that notifies a handler reports `changed`, the handler is queued. When a task that notifies a handler reports `ok`, the handler is not queued. Handlers run once at the end of the play (unless `meta: flush_handlers` is used), and each handler runs only once even if notified by multiple tasks.

On the first run, the unit file task reported `changed`, so `Restart kk service` fired. On the second run, the unit file task reported `ok` (the file was already present with the correct content), so the handler did not fire. This is why the second run showed no restarts — which is the whole point. Handlers exist so that services restart only when their configuration actually changes, not every time the playbook runs.

If the handler fired unconditionally, running the playbook twice would restart every service on every host — unnecessary downtime. Handlers are the mechanism that turns "the playbook ran" into "the playbook made a change, and the service noticed."

---

## Question 4: Drift in Configuration Management

If someone manually edits a systemd unit file on one of the servers — say they change `PrivateNetwork=true` to `false` on the payments server, or add an `Environment=` directive — Ansible will detect the change on the next playbook run and correct it.

The mechanism: the `ansible.builtin.template` task renders the file, computes the SHA-256 checksum of the rendered content, and compares it to the checksum of the file on disk. If the checksums differ, the task reports `changed` and writes the correct content, overwriting the manual edit. The handler then fires, restarting the service.

This is Ansible's equivalent of Terraform's drift detection. The differences are important:

Terraform detects drift by comparing the current infrastructure state (fetched from the provider) against the state file and the configuration. It reports the difference in `terraform plan` and lets you decide whether to remediate (apply) or accept (update config). Detection happens at plan time, before any change.

Ansible detects drift implicitly — the template module notices that the file's checksum doesn't match the expected checksum. It doesn't produce a "plan" showing the difference in advance; it just corrects it (unless you run with `--check`, which shows what would change without changing it).

The `--check` mode is Ansible's version of `terraform plan`. Running `ansible-playbook --check` shows what each task would change without actually changing anything. On a drifted server, the template task would report `changed` in check mode, showing that the file differs from the expected content.

One gap: Ansible only detects drift in the tasks it manages. If someone installs an unauthorized package, adds a user not in the playbook, or opens a firewall port the playbook doesn't mention, Ansible will not notice. It checks what it manages, not what it doesn't.

---

## Bonus: The MinIO Substitution and its Impact on Thursday

Thursday's playbook does not depend on MinIO. It runs entirely against the VMs, not against the Terraform state backend. This is a deliberate architectural property: the Terraform-Ansible boundary means Ansible is unaware of how Terraform stores its state. If the state backend changes (from local to MinIO, or from MinIO to a cloud bucket), Ansible is unaffected.

This is one of the strongest arguments for keeping the two tools in separate domains. The MinIO community-edition discontinuation that disrupted Wednesday's lab had zero impact on Thursday's work. If we had tried to make one tool do both jobs, the supply-chain incident would have rippled through the entire pipeline.

The tradeoff is coordination overhead. The pipeline script on Friday must run Terraform, extract IPs, write the inventory, and then run Ansible — all in sequence. This is a real cost, but it is a cost paid once, in the orchestration layer, rather than paid continuously in the form of a fragile combined tool. That is the lesson of the Terraform-Ansible boundary.
