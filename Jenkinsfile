pipeline {
    agent {
        docker {
            image 'node:20-alpine'
            args '-u root:root'
        }
    }

    environment {
        NEXUS_URL    = 'http://172.17.0.1:8081'
        NEXUS_REPO   = 'npm-hosted'
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
                        def pkgJson = readFile(file: 'package.json')
                        def pkg = new groovy.json.JsonSlurper().parseText(pkgJson)
                        def shortSha = sh(script: 'git -C ../.. rev-parse --short HEAD', returnStdout: true).trim()
                        env.VERSION = "${pkg.version}-${shortSha}"
                        echo "Calculated version: ${env.VERSION}"
                    }
                }
            }
        }

        stage('Publish') {
            steps {
                dir('week5/friday') {
                    withCredentials([usernamePassword(
                        credentialsId: 'nexus-credentials',
                        usernameVariable: 'NEXUS_USER',
                        passwordVariable: 'NEXUS_PASS'
                    )]) {
                        sh '''
                            npm version ${VERSION} --no-git-tag-version
                            
                            cat > .npmrc <<NPMRC
registry=${NEXUS_URL}/repository/${NEXUS_REPO}/
_auth=${NEXUS_USER}:${NEXUS_PASS}
email=ci@kijanikiosk.com
always-auth=true
NPMRC
                            
                            npm publish
                            rm -f .npmrc
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
            echo "Pipeline succeeded. Artifact published to ${NEXUS_URL}/repository/${NEXUS_REPO}/${PACKAGE_NAME}/"
        }
        failure {
            echo "Pipeline failed. Please check the logs."
        }
        changed {
            echo "Pipeline status changed to ${currentBuild.currentResult}"
        }
    }
}
