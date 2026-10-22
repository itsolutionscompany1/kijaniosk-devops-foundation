# Capstone Project Scope: KijaniKiosk Delivery

## Problem Statement
KijaniKiosk currently lacks a unified, automated deployment pipeline that separates staging from production. Deployments are manual, error-prone, and lack an approval gate, meaning bad code can reach production without passing smoke tests.

## Track Chosen
**Track A: Infrastructure-First**

## In-Scope Components (5)
1. A `kijani-staging` Kubernetes namespace provisioned via Terraform.
2. A Jenkins pipeline that automatically deploys to staging on merge.
3. A smoke test stage that validates the staging deployment health endpoint.
4. A manual approval gate before deploying to production.
5. A mock serverless receipt chain (S3 trigger) integrated with the staging app.

## Out-of-Scope Items
- **Real AWS Cloud Deployment:** We are using a mock local serverless environment to simulate the event chain, rather than provisioning real AWS resources, due to budget constraints.
- **Prometheus Alerting:** While requested for the full Track A, implementing a full Prometheus stack is out of scope for this iteration to focus on CI/CD reliability.

## Success Criteria (Measurable)
1. `kubectl get ns kijani-staging` returns `Active`.
2. The Jenkins pipeline successfully passes the Smoke Test stage against staging.
3. The pipeline pauses and requires manual approval before executing the Production deployment.
4. The application responds to a `/health` check in both environments.
