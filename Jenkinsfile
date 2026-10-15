// Sprint 4: application CI/CD (Multibranch job: streamingapp-app)
// Every branch: test + build + push to ECR. main/Develop: also deploy to EKS + smoke test.
// Infrastructure and configuration run in their own jobs: jenkins/Jenkinsfile.infra and jenkins/Jenkinsfile.ansible.
// AWS access comes from the Jenkins EC2 IAM role (no static keys).
pipeline {
  agent any
  environment {
    AWS_DEFAULT_REGION = 'us-east-1'
    EKS_CLUSTER        = 'streamingapp-cluster'
    NAMESPACE          = 'streamingapp'
    SLACK_CHANNEL      = '#devops-alerts'
  }
  options {
    buildDiscarder(logRotator(numToKeepStr: '10'))
    timeout(time: 45, unit: 'MINUTES')
    disableConcurrentBuilds()
    timestamps()
  }
  stages {
    // -- Stage 1: Checkout -----------------------------------------
    stage('Checkout') {
      steps {
        checkout scm
        script {
          env.IMAGE_TAG      = sh(script: 'git rev-parse --short=8 HEAD', returnStdout: true).trim()
          env.AWS_ACCOUNT_ID = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
          env.ECR_REGISTRY   = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_DEFAULT_REGION}.amazonaws.com"
        }
        sh 'git log --oneline -5'
      }
    }
    // -- Stage 2: Unit Tests ---------------------------------------
    stage('Unit Tests') {
      parallel {
        stage('Auth Service')      { steps { dir('backend/authService')      { sh 'npm ci && npm test' } } }
        stage('Streaming Service') { steps { dir('backend/streamingService') { sh 'npm ci && npm test' } } }
        stage('Admin Service')     { steps { dir('backend/adminService')     { sh 'npm ci && npm test' } } }
        stage('Chat Service')      { steps { dir('backend/chatService')      { sh 'npm ci && npm test' } } }
        stage('Frontend')          { steps { dir('frontend')                 { sh 'npm ci && CI=true npm test -- --watchAll=false' } } }
      }
    }
    // -- Stage 3: Docker Build & Push ------------------------------
    stage('Docker Build & Push') {
      steps {
        script {
          sh 'aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REGISTRY'
          def services = [
            [name: 'frontend',          context: 'frontend',            dockerfile: 'frontend/Dockerfile'],
            [name: 'auth-service',      context: 'backend/authService', dockerfile: 'backend/authService/Dockerfile'],
            [name: 'streaming-service', context: 'backend',             dockerfile: 'backend/streamingService/Dockerfile'],
            [name: 'admin-service',     context: 'backend',             dockerfile: 'backend/adminService/Dockerfile'],
            [name: 'chat-service',      context: 'backend',             dockerfile: 'backend/chatService/Dockerfile'],
          ]
          // Images are tagged only with the git SHA (no 'latest'); ECR tags are immutable,
          // so a re-run of the same commit reuses the already-pushed image instead of overwriting it
          services.each { svc ->
            def repo   = "${env.ECR_REGISTRY}/streamingapp/${svc.name}"
            def exists = sh(returnStatus: true,
              script: "aws ecr describe-images --repository-name streamingapp/${svc.name} --image-ids imageTag=${env.IMAGE_TAG} > /dev/null 2>&1") == 0
            if (exists) {
              echo "${svc.name}:${env.IMAGE_TAG} already in ECR, skipping build"
            } else {
              sh "docker build -f ${svc.dockerfile} -t ${repo}:${env.IMAGE_TAG} ${svc.context}"
              sh "docker push ${repo}:${env.IMAGE_TAG}"
            }
          }
        }
      }
    }
    // -- Stage 4: Deploy to EKS ------------------------------------
    stage('Deploy to EKS') {
      when { anyOf { branch 'main'; branch 'Develop' } }
      steps {
        sh '''
          aws eks update-kubeconfig --name $EKS_CLUSTER --region $AWS_DEFAULT_REGION

          kubectl apply -f k8s/namespace.yaml
          kubectl apply -f k8s/mongo-statefulset.yaml
          kubectl rollout status statefulset/mongo -n $NAMESPACE --timeout=5m

          # --atomic rolls back automatically if the new pods fail their health checks
          helm upgrade --install streamingapp ./helm/streamingapp \
            --namespace $NAMESPACE \
            -f helm/values-prod.yaml \
            --set global.imageRegistry=$ECR_REGISTRY \
            --set global.imageTag=$IMAGE_TAG \
            --atomic --wait --timeout 10m

          kubectl apply -f k8s/ingress-api.yaml -f k8s/ingress-frontend.yaml
          kubectl get pods,svc,hpa,ingress -n $NAMESPACE
        '''
      }
    }
    // -- Stage 5: Smoke Tests --------------------------------------
    stage('Smoke Tests') {
      when { anyOf { branch 'main'; branch 'Develop' } }
      steps {
        sh '''
          # In-cluster: every backend answers its health check (frontend image has busybox wget)
          for svc in auth-service:3001 streaming-service:3002 admin-service:3003 chat-service:3004; do
            NAME=${svc%%:*}; PORT=${svc##*:}
            kubectl exec -n $NAMESPACE deploy/frontend -- wget -qO- -T 5 http://$NAME:$PORT/api/health > /dev/null \
              || { echo "FAIL: $NAME"; exit 1; }
            echo "OK: $NAME"
          done

          # External: through the ALB, end to end (frontend, then streaming API + MongoDB)
          # A new ALB takes a few minutes to get its hostname and pass health checks
          for i in $(seq 1 30); do
            ALB=$(kubectl get ingress streamingapp-ingress-frontend -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
            [ -n "$ALB" ] && break
            echo "Waiting for ALB hostname ($i/30)..."; sleep 10
          done
          [ -n "$ALB" ] || { echo "FAIL: Ingress has no ALB hostname after 5 minutes"; exit 1; }
          echo "App URL: http://$ALB"
          curl -fsS --retry 30 --retry-delay 10 --retry-all-errors -o /dev/null http://$ALB/health
          curl -fsS --retry 30 --retry-delay 10 --retry-all-errors -o /dev/null http://$ALB/api/streaming/videos/featured
          echo "All smoke tests passed"
        '''
      }
    }
  }
  post {
    success {
      slackSend channel: env.SLACK_CHANNEL, color: 'good',
        message: ":white_check_mark: Build #${BUILD_NUMBER} on ${BRANCH_NAME} succeeded. Tag: ${env.IMAGE_TAG}"
    }
    failure {
      slackSend channel: env.SLACK_CHANNEL, color: 'danger',
        message: ":x: Build #${BUILD_NUMBER} on ${BRANCH_NAME} FAILED. Check: ${BUILD_URL}"
    }
    always {
      sh 'docker image prune -af --filter "until=24h" || true'
      cleanWs()
    }
  }
}
