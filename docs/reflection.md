# Capstone Reflection

## 1. What did you get wrong?
I initially assumed that Kubernetes would automatically pull images from my local `localhost:5000` registry when running inside Minikube. This was incorrect because Minikube runs in an isolated Docker network namespace; `localhost` inside Minikube is not the same as `localhost` on the host machine. This caused an `ImagePullBackOff` error. If I were to do this again, I would have configured the Minikube registry addon or used `minikube image load` from the start, which is a cleaner, more production-aligned approach for local development.

## 2. Most important thing learned
The most important concept I learned was the power of **declarative Infrastructure as Code (Terraform)** combined with **Kubernetes orchestration**. Before Week 7, infrastructure was manual. Terraform showed me how to define state declaratively, and Kubernetes proved that self-healing (replacing a dead pod in 5 seconds) is a reality, not just a buzzword. This changed my thinking from "how do I fix this broken server" to "how do I define the desired state and let the system reconcile it."

## 3. Second pass improvements
If I had another day, I would:
1. **Add real AWS integration:** Instead of the mock serverless chain, I would provision a real S3 bucket and Lambda via the Serverless Framework.
2. **Add Prometheus Alerting:** I would deploy Prometheus and Alertmanager to the cluster and create a rule that fires if the `kk-payments` error rate exceeds 1%.
3. **Add a real GitHub Webhook:** To fully automate the pipeline, I would configure a GitHub webhook so that a push to `main` triggers Jenkins automatically without manual polling.
4. **Use Helm:** Instead of raw Kubernetes YAML, I would package the application as a Helm chart for easier multi-environment deployment.
