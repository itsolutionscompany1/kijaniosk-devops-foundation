# Capstone Test Plan

## Testing Strategy
The capstone will be tested across four layers:

### 1. Unit & Integration Testing
- Run `npm test` in `apps/kk-payments`.
- **Expected:** 6 tests passing.

### 2. Pipeline Smoke Test
- Jenkins triggers the pipeline.
- After staging deploy, the pipeline runs `curl http://staging:3001/health`.
- **Expected:** Returns `{"status":"healthy","version":"1.0.0"}`.

### 3. Fault Injection (Self-Healing)
- Delete a running pod in `kijani-staging`.
- **Expected:** Kubernetes replaces the pod within 10 seconds.

### 4. Approval Gate
- Pipeline reaches the `Deploy to Production` stage.
- **Expected:** Pipeline pauses and waits for manual input.

## Peer Review Checklist
- [ ] Verify no secrets in `.env` or `Jenkinsfile`.
- [ ] Verify README instructions work from a fresh clone.
- [ ] Verify the `configmap` uses different DB_HOSTs for staging vs production.
