# Feedback & Peer Review Log

## Review Session: 2026-11-04 (Self-Review)

### Issue 1: Secrets in Repo
- **Severity:** High
- **Description:** The `Jenkinsfile` had hardcoded credentials for the Docker registry.
- **Resolution:** Removed the hardcoded credentials and replaced them with Jenkins `withCredentials` bindings.
- **Evidence:** Commit `feat(infra): add terraform config and move app to apps directory` (no secrets in diff).

### Issue 2: No Resource Limits in Deployment
- **Severity:** Medium
- **Description:** The `kk-payments-deployment.yaml` lacked CPU and memory limits, which could crash the cluster.
- **Resolution:** Added `requests: { cpu: "50m", memory: "64Mi" }` and `limits: { cpu: "100m", memory: "128Mi" }`.
- **Evidence:** See `k8s/deployment.yaml`.

### Issue 3: README Missing Setup Steps
- **Severity:** Medium
- **Description:** A new engineer would not know how to run the Terraform script or start Minikube.
- **Resolution:** Added a "How to Run" section to the `README.md`.
- **Evidence:** Commit `docs: rewrite README with architecture overview and run instructions`.
