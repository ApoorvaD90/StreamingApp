pipeline {
  agent any
  environment {
    AWS_ACCOUNT_ID     = credentials('aws-account-id')
    AWS_DEFAULT_REGION = 'us-east-1'
    ECR_REGISTRY       = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
    IMAGE_TAG          = "${GIT_COMMIT[0..7]}"
    EKS_CLUSTER        = 'streamingapp-cluster'
    NAMESPACE          = 'streamingapp'
    SLACK_CHANNEL      = '#devops-alerts'
  }
  options {
    buildDiscarder(logRotator(numToKeepStr: '10'))
    timeout(time: 45, unit: 'MINUTES')
    disableConcurrentBuilds()
  }
  stages {
    // -- Stage 1: Checkout -----------------------------------------
    stage('Checkout') {
      steps {
        checkout scm
        sh 'git log --oneline -5'
      }
    }
    // -- Stage 2: Unit Tests ---------------------------------------
    stage('Unit Tests') {
      parallel {
            stage('Test Auth Service') {
          steps {
            dir('backend/authService') {
              sh 'npm ci && npm test -- --watchAll=false'
            }
          }
        }
        stage('Test Streaming Service') {
          steps {
            dir('backend/streamingService') {
              sh 'npm ci && npm test -- --watchAll=false'
            }
          }
        }
        stage('Test Frontend') {
          steps {
            dir('frontend') {
              sh 'npm ci && npm test -- --watchAll=false --passWithNoTests'
            }
          }
        }
      }
    }
    // -- Stage 3: Docker Build & Push ------------------------------
    stage('Docker Build & Push') {
      steps {
        script {
          sh """
            aws ecr get-login-password --region ${AWS_DEFAULT_REGION} \
              | docker login --username AWS --password-stdin ${ECR_REGISTRY}
          """
          def services = [
            [name: 'frontend',          context: 'frontend',                dockerfile: 'frontend/Dockerfile'],
            [name: 'auth-service',      context: 'backend/authService',      dockerfile: 'backend/authService/Dockerfile'],
            [name: 'streaming-service', context: 'backend',                  dockerfile: 'backend/streamingService/Dockerfile'],
            [name: 'admin-service',     context: 'backend',                  dockerfile: 'backend/adminService/Dockerfile'],
            [name: 'chat-service',      context: 'backend',                  dockerfile: 'backend/chatService/Dockerfile'],
            ]
          services.each { svc ->
            def img = "${ECR_REGISTRY}/streamingapp/${svc.name}:${IMAGE_TAG}"
            sh "docker build -f ${svc.dockerfile} -t ${img} ${svc.context}"
            sh "docker push ${img}"
            sh "docker tag ${img} ${ECR_REGISTRY}/streamingapp/${svc.name}:latest"
            sh "docker push ${ECR_REGISTRY}/streamingapp/${svc.name}:latest"
          }
        }
      }
    }
    // -- Stage 4: Terraform Plan -----------------------------------
    stage('Terraform Plan') {
      when { branch 'main' }
      steps { 
                dir('terraform') {
          withCredentials([[$class:'AmazonWebServicesCredentialsBinding',
                            credentialsId:'aws-credentials']]) {
            sh '''
              terraform init -backend-config="bucket=streamingapp-tfstate" \
                             -backend-config="key=eks/terraform.tfstate" \
                             -backend-config="region=us-east-1"
              terraform plan -out=tfplan
            '''
          }
        }
      }
    }
    // -- Stage 5: Terraform Apply ----------------------------------
    stage('Terraform Apply') {
      when { branch 'main' }
      input { message "Apply Terraform changes?" }
      steps {
        dir('terraform') {
          withCredentials([[$class:'AmazonWebServicesCredentialsBinding',
                            credentialsId:'aws-credentials']]) {
            sh 'terraform apply -auto-approve tfplan'
          }
        }
      }
    }
    // -- Stage 6: Ansible Configuration ---------------------------
    stage('Ansible Configure') {
      when { branch 'main' }
      steps {
        dir('ansible') {
          sh 'ansible-playbook -i inventory/aws_ec2.yml site.yml --extra-vars "env=prod"'
        }
      }
    }
    // -- Stage 7: Deploy to EKS ------------------------------------
    stage('Deploy to EKS') {
      when { branch 'main' }
      steps {
        sh """
          aws eks update-kubeconfig --name ${EKS_CLUSTER} --region ${AWS_DEFAULT_REGION}
          helm upgrade --install streamingapp ./helm/streamingapp \
            --namespace ${NAMESPACE} --create-namespace \
            -f helm/values-prod.yaml \
            --set global.imageTag=${IMAGE_TAG} \
            --wait --timeout 5m
        """
      }
    }
    // -- Stage 8: Smoke Tests --------------------------------------
    stage('Smoke Tests') {
      when { branch 'main' }
      steps {
        sh '''
          for svc in auth-service:3001 streaming-service:3002 admin-service:3003 chat-service:3004; do
            NAME=$(echo $svc | cut -d: -f1)
            PORT=$(echo $svc | cut -d: -f2)
            STATUS=$(kubectl run smoke-test-$NAME --rm -i --restart=Never --namespace ${NAMESPACE} \
              --image=curlimages/curl -- curl -s -o /dev/null -w "%{http_code}" http://$NAME:$PORT/api/health)
            [ "$STATUS" = "200" ] || { echo "FAIL: $NAME returned $STATUS"; exit 1; }
          done
          echo "All smoke tests passed"
        '''
      }
    }
  }
  post {
    success {
      slackSend channel: env.SLACK_CHANNEL, color: 'good',
        message: ":white_check_mark: Build #${BUILD_NUMBER} on ${BRANCH_NAME} deployed successfully. Tag: ${IMAGE_TAG}"
    }
    failure {
      slackSend channel: env.SLACK_CHANNEL, color: 'danger',
        message: ":x: Build #${BUILD_NUMBER} on ${BRANCH_NAME} FAILED. Check: ${BUILD_URL}"
    }
    always {
      cleanWs()
    }
  }
} 