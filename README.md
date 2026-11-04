# KijaniKiosk DevOps Foundation

## Overview
This repository contains the end-to-end DevOps delivery pipeline for the KijaniKiosk payments application. It implements Infrastructure as Code (Terraform), Containerization (Docker), Orchestration (Kubernetes), and a CI/CD Pipeline (Jenkins).

## Architecture
- **App:** Node.js (`apps/kk-payments`)
- **IaC:** Terraform (`infrastructure/`)
- **K8s Manifests:** (`k8s/`)
- **Serverless:** Mock receipt chain (`serverless/`)
- **CI/CD:** `Jenkinsfile`

## Prerequisites
- Docker
- Minikube (running)
- Jenkins (running)
- Terraform installed

## How to Run the Pipeline
1. Ensure Minikube is running: `minikube start`
2. Build the image: `docker build -t kk-payments:latest apps/kk-payments/`
3. Deploy to Kubernetes: `kubectl apply -f k8s/deployment.yaml`
4. Configure Jenkins to point to this repository and run the `Jenkinsfile`.

## Directory Structure
- `apps/`: Source code for the payments app.
- `docs/`: Scope, Governance, Architecture diagrams.
- `infrastructure/`: Terraform for namespaces.
- `k8s/`: Kubernetes deployment and configmaps.
- `serverless/`: Mock serverless receipt chain.
