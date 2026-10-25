pipeline {
    agent any

    environment {
        REGISTRY = "localhost:5000"
        IMAGE_NAME = "kk-payments"
        STAGING_NS = "kijani-staging"
        PROD_NS = "kijani-production"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build & Push Image') {
            steps {
                dir('apps/kk-payments') {
                    script {
                        env.VERSION = sh(script: 'node -p "require(\'./package.json\').version"', returnStdout: true).trim()
                        env.GIT_SHA = env.GIT_COMMIT.take(7)
                        env.TAG = "${env.VERSION}-${env.GIT_SHA}"
                    }
                    sh "docker build --no-cache -f Dockerfile.production -t ${REGISTRY}/${IMAGE_NAME}:${TAG} ."
                    sh "docker push ${REGISTRY}/${IMAGE_NAME}:${TAG}"
                }
            }
        }

        stage('Deploy to Staging') {
            steps {
                script {
                    sh "kubectl apply -f infrastructure/terraform/main.tf" // Just to ensure namespaces exist
                    sh "kubectl apply -f k8s/configmap-staging.yaml"
                    sh "kubectl apply -f k8s/deployment.yaml -n ${STAGING_NS}"
                    sh "kubectl apply -f k8s/service.yaml -n ${STAGING_NS}"
                }
            }
        }

        stage('Smoke Test Staging') {
            steps {
                script {
                    // Wait for rollout
                    sh "kubectl rollout status deployment/kk-payments -n ${STAGING_NS} --timeout=90s"
                    // Curl the health endpoint (using NodePort or port-forward)
                    sh "kubectl port-forward svc/kk-payments-service 3001:3001 -n ${STAGING_NS} &"
                    sleep 5
                    def response = sh(script: "curl -s http://localhost:3001/health", returnStdout: true).trim()
                    echo "Smoke Test Response: ${response}"
                    if (!response.contains("healthy")) {
                        error("Smoke test failed: Invalid response")
                    }
                    sh "kill %1 || true"
                }
            }
        }

        stage('Deploy to Production (Approval)') {
            steps {
                // This requires the 'input' step which pauses the pipeline
                input message: "Smoke test passed. Approve deployment to production?", ok: "Deploy"
                script {
                    sh "kubectl apply -f k8s/configmap-production.yaml"
                    sh "kubectl apply -f k8s/deployment.yaml -n ${PROD_NS}"
                    sh "kubectl apply -f k8s/service.yaml -n ${PROD_NS}"
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "Pipeline completed successfully."
        }
        failure {
            echo "Pipeline failed."
        }
    }
}
