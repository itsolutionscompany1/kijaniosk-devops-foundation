pipeline {
    agent {
        docker {
            image 'node:20-alpine'
            args '-u root:root'
        }
    }

    options {
        timestamps()
        timeout(time: 15, unit: 'MINUTES')
    }

    environment {
        MINIO_URL = 'http://172.17.0.1:9000'
        MINIO_BUCKET = 'kijanikiosk-artifacts'
        APP_DIR = 'week5/friday'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Lint') {
            steps {
                dir("${APP_DIR}") {
                    sh 'npm ci --no-audit --no-fund && npm run lint'
                }
            }
        }

        stage('Build') {
            steps {
                dir("${APP_DIR}") {
                    sh 'npm run build'
                }
            }
        }

        stage('Verify') {
            parallel {
                stage('Test') {
                    steps {
                        dir("${APP_DIR}") {
                            sh 'npm test'
                        }
                    }
                    post {
                        always {
                            junit allowEmptyResults: true, testResults: 'week5/friday/test-results/junit.xml'
                        }
                    }
                }
                stage('Security Audit') {
                    steps {
                        dir("${APP_DIR}") {
                            sh 'npm run audit:security'
                        }
                    }
                }
            }
        }

        stage('Archive & Publish') {
            steps {
                dir("${APP_DIR}") {
                    archiveArtifacts artifacts: 'dist/**', fingerprint: true
                    
                    script {
                        env.PKG_VERSION = sh(script: 'node -p "require(\'./package.json\').version"', returnStdout: true).trim()
                        env.GIT_SHA = env.GIT_COMMIT.take(7)
                        env.FULL_VERSION = "${env.PKG_VERSION}-${env.GIT_SHA}"
                    }
                    
                    sh "tar -czf /tmp/kijanikiosk-payments-${env.FULL_VERSION}.tar.gz -C dist ."
                    
                    withCredentials([usernamePassword(credentialsId: 'minio-credentials', usernameVariable: 'MINIO_USER', passwordVariable: 'MINIO_PASS')]) {
                        sh '''
                            # Install MinIO client if not already there
                            if ! command -v mc &> /dev/null; then
                                wget -qO /usr/local/bin/mc https://dl.min.io/aistor/mc/release/linux-amd64/mc
                                chmod +x /usr/local/bin/mc
                            fi
                            
                            # Configure client
                            mc alias set myminio ${MINIO_URL} ${MINIO_USER} ${MINIO_PASS}
                            
                            # Ensure bucket exists, then upload
                            mc mb myminio/${MINIO_BUCKET} --ignore-existing
                            mc cp /tmp/kijanikiosk-payments-${FULL_VERSION}.tar.gz myminio/${MINIO_BUCKET}/
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "Successfully published version ${env.FULL_VERSION} to MinIO bucket ${MINIO_BUCKET}"
        }
        failure {
            echo "Pipeline failed. Check logs."
        }
        changed {
            echo "Pipeline status changed to ${currentBuild.currentResult}"
        }
    }
}
