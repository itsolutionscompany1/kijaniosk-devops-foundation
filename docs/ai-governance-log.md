# AI Governance Log

## Entry 1: Terraform Namespace Configuration
- **Date:** 2026-10-20
- **Tool Used:** ChatGPT
- **Prompt:** "Write a Terraform configuration to create a Kubernetes namespace named kijani-staging."
- **What the AI Produced:** A basic `kubernetes_namespace` resource block.
- **What it Got Wrong:** The AI forgot to include the provider configuration block (`required_providers`), which caused the Terraform init to fail initially.
- **Specific Change Made:** I manually added the `terraform { required_providers { kubernetes = { source = "hashicorp/kubernetes" } } }` block to ensure it could authenticate with Minikube.
- **Governance Checklist Item:** Reviewed generated code for security misconfigurations (none found, but provider missing).

## Entry 2: Jenkinsfile Approval Gate
- **Date:** 2026-11-04
- **Tool Used:** ChatGPT
- **Prompt:** "How do I add a manual approval step before a production deployment in a Declarative Jenkinsfile?"
- **What the AI Produced:** `input message: 'Deploy to prod?'`
- **What it Got Wrong:** The AI placed the `input` step inside a `script` block, which caused a syntax error in the Declarative Pipeline context.
- **Specific Change Made:** I moved the `input` step outside the `script` block, directly into the `steps` of the stage, which is the correct syntax for Declarative Pipelines.
- **Governance Checklist Item:** Verified syntax against official Jenkins documentation.
