pipeline {
    agent {
        docker {
            image 'node:20-alpine'
            args '-u root:root'
        }
    }

    environment {
        MINIO_URL    = 'http://172.17.0.1:9000'
        MINIO_BUCKET = 'kijanikiosk-artifacts'
        PACKAGE_NAME = 'kijanikiosk-payments'
    }

    options {
        timestamps()
        timeout(time: 10, unit: 'MINUTES')
    }

    stages {
        stage('Lint') {
            steps {
                dir('week5/friday') {
                    sh 'npm ci'
                    sh 'npm run lint'
                }
            }
        }

        stage('Build') {
            steps {
                dir('week5/friday') {
                    sh 'npm run build'
                }
            }
        }

        stage('Verify') {
            parallel {
                stage('Test') {
                    steps {
                        dir('week5/friday') {
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
                        dir('week5/friday') {
                            sh 'npm run audit:security'
                        }
                    }
                }
            }
        }

        stage('Archive') {
            steps {
                dir('week5/friday') {
                    archiveArtifacts artifacts: 'dist/**', fingerprint: true
                    script {
                        def pkgVersion = sh(script: 'grep -o \'"version": "[^"]*"\' package.json | cut -d\'"\' -f4', returnStdout: true).trim()
                        def shortSha = env.GIT_COMMIT ? env.GIT_COMMIT.take(7) : 'unknown'
                        env.VERSION = "${pkgVersion}-g${shortSha}"
                        echo "Calculated version: ${env.VERSION}"
                    }
                }
            }
        }

        stage('Publish') {
            steps {
                dir('week5/friday') {
                    withCredentials([usernamePassword(
                        credentialsId: 'minio-credentials',
                        usernameVariable: 'MINIO_USER',
                        passwordVariable: 'MINIO_PASS'
                    )]) {
                        sh '''
                            # Install wget and download the MinIO Client
                            apk add --no-cache wget ca-certificates
                            wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
                            chmod +x /usr/local/bin/mc
                            
                            # Set the version and pack the artifact
                            npm pkg set version="${VERSION}"
                            npm pack
                            
                            # Configure mc to connect to your MinIO instance
                            mc alias set myminio ${MINIO_URL} ${MINIO_USER} ${MINIO_PASS}
                            
                            # Upload the tarball to the bucket
                            mc cp "${PACKAGE_NAME}-${VERSION}.tgz" myminio/${MINIO_BUCKET}/
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
            echo "Pipeline succeeded. Artifact published to MinIO bucket: ${MINIO_BUCKET}"
        }
        failure {
            echo "Pipeline failed. Please check the logs."
        }
        changed {
            echo "Pipeline status changed to ${currentBuild.currentResult}"
        }
    }
}
