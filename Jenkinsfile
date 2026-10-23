pipeline {
    agent any

    options {
        disableConcurrentBuilds()
    }

    parameters {
        string(
            name: 'DOCKER_USER',
            defaultValue: 'your-dockerhub-username',
            description: 'Docker Hub username or organization'
        )
        string(
            name: 'DOCKER_IMAGE_NAME',
            defaultValue: 'shoppingcart',
            description: 'Docker Hub repository name for the application image'
        )
        booleanParam(
            name: 'DEPLOY',
            defaultValue: false,
            description: 'Request deployment after scans pass (main branch only)'
        )
    }

    environment {
        AWS_DEFAULT_REGION = 'us-east-1'
        DOCKER_IMAGE_TAG = "${BUILD_NUMBER}"
        CHECKOV_STATUS = 'NOT_RUN'
        TRIVY_CONFIG_STATUS = 'NOT_RUN'
        TRIVY_IMAGE_STATUS = 'NOT_RUN'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Format and Validate') {
            steps {
                sh 'terraform fmt -check -recursive'
                sh 'terraform init -backend=false -input=false'
                sh 'terraform validate'
            }
        }

        stage('Scan Terraform') {
            steps {
                script {
                    env.CHECKOV_STATUS = sh(
                        returnStatus: true,
                        script: 'checkov -f main.tf -o json > checkov-results.json'
                    ).toString()
                    env.TRIVY_CONFIG_STATUS = sh(
                        returnStatus: true,
                        script: 'trivy config --exit-code 1 --format json --output trivy-config-results.json main.tf'
                    ).toString()
                }
            }
        }

        stage('Build Docker Image') {
            when {
                expression { fileExists('Dockerfile') }
            }
            steps {
                script {
                    docker.build("${params.DOCKER_USER}/${params.DOCKER_IMAGE_NAME}:${env.DOCKER_IMAGE_TAG}")
                }
            }
        }

        stage('Scan Docker Image') {
            when {
                expression { fileExists('Dockerfile') }
            }
            steps {
                script {
                    withEnv([
                        "IMAGE_REF=${params.DOCKER_USER}/${params.DOCKER_IMAGE_NAME}:${env.DOCKER_IMAGE_TAG}"
                    ]) {
                        env.TRIVY_IMAGE_STATUS = sh(
                            returnStatus: true,
                            script: 'trivy image --exit-code 1 --format json --output trivy-image-results.json "$IMAGE_REF"'
                        ).toString()
                    }
                }
            }
        }

        stage('Enforce Security Scan Results') {
            steps {
                script {
                    def failedScans = []
                    if (env.CHECKOV_STATUS != '0') {
                        failedScans.add("Checkov (exit ${env.CHECKOV_STATUS})")
                    }
                    if (env.TRIVY_CONFIG_STATUS != '0') {
                        failedScans.add("Trivy config (exit ${env.TRIVY_CONFIG_STATUS})")
                    }
                    if (env.TRIVY_IMAGE_STATUS != 'NOT_RUN' && env.TRIVY_IMAGE_STATUS != '0') {
                        failedScans.add("Trivy image (exit ${env.TRIVY_IMAGE_STATUS})")
                    }
                    if (failedScans) {
                        error("Security scans found issues or failed: ${failedScans.join(', ')}. Review the archived JSON reports.")
                    }
                }
            }
        }

        stage('Push Docker Image') {
            when {
                allOf {
                    branch 'main'
                    expression { fileExists('Dockerfile') }
                }
            }
            steps {
                script {
                    docker.withRegistry('https://index.docker.io/v1/', 'dockerhub-credentials-id') {
                        docker.image("${params.DOCKER_USER}/${params.DOCKER_IMAGE_NAME}:${env.DOCKER_IMAGE_TAG}").push()
                    }
                }
            }
        }

        stage('Terraform Apply Multi-AZ Deployment') {
            when {
                allOf {
                    branch 'main'
                    expression { params.DEPLOY && fileExists('Dockerfile') }
                }
            }
            steps {
                input message: 'Security scans passed. Apply this Terraform deployment to AWS?', ok: 'Apply'
                withCredentials([
                    string(credentialsId: 'db-admin-password', variable: 'TF_VAR_database_password')
                ]) {
                    sh '''
                        terraform init -input=false
                        terraform plan -input=false -out=tfplan \
                          -var="docker_user=${DOCKER_USER}" \
                          -var="docker_image_name=${DOCKER_IMAGE_NAME}" \
                          -var="docker_image_tag=${DOCKER_IMAGE_TAG}"
                        terraform apply -input=false tfplan
                        terraform output -raw alb_dns_name
                    '''
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts(
                artifacts: 'checkov-results.json,trivy-config-results.json,trivy-image-results.json',
                allowEmptyArchive: true
            )
        }
    }
}
