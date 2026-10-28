// Sprint 4: application CI/CD (Multibranch job: streamingapp-app)
// Every branch: test + build + push to ECR. main/Develop/Sprint-3: also deploy to EKS + post-deploy tests.
// Sprint 5: Slack notifications; Sprint 6: deployment, API and monitoring tests (scripts in tests/).
// Triggered by a GitHub push (webhook) or by streamingapp-ansible after configuration changes.
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
      when { anyOf { branch 'main'; branch 'Develop'; branch 'Sprint-3' } }
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

          # Brand-new cluster: Ansible wrote the secret before any ALB existed, so CORS has no allowed origin.
          # Fill it in once the ALB has a hostname (the same value Ansible computes, so its next run
          # reports no change) and restart the pods, which read the secret only at start-up.
          if [ -z "$(kubectl get secret streamingapp-secrets -n $NAMESPACE -o jsonpath='{.data.CLIENT_URLS}')" ]; then
            for i in $(seq 1 30); do
              ALB=$(kubectl get ingress streamingapp-ingress-frontend -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
              [ -n "$ALB" ] && break
              echo "Waiting for ALB hostname to set CORS ($i/30)..."; sleep 10
            done
            if [ -n "$ALB" ]; then
              APP_URL_B64=$(printf 'http://%s' "$ALB" | base64 -w0)
              kubectl patch secret streamingapp-secrets -n $NAMESPACE --type merge \
                -p "{\"data\":{\"CLIENT_URLS\":\"$APP_URL_B64\",\"STREAMING_PUBLIC_URL\":\"$APP_URL_B64\"}}"
              kubectl rollout restart deployment -n $NAMESPACE -l chart
              for d in $(kubectl get deploy -n $NAMESPACE -l chart -o name); do
                kubectl rollout status "$d" -n $NAMESPACE --timeout=5m
              done
              echo "CORS origin set to http://$ALB"
            fi
          fi
          kubectl get pods,svc,hpa,ingress -n $NAMESPACE
        '''
      }
    }
    // -- Stage 5: Deployment Tests (Sprint 6) -------------------
    // Rollout, image tags = this commit, probes, HPAs, in-cluster health + /metrics, ServiceMonitors
    stage('Deployment Tests') {
      when { anyOf { branch 'main'; branch 'Develop'; branch 'Sprint-3' } }
      steps {
        sh 'bash tests/deployment/verify-deployment.sh'
      }
    }
    // -- Stage 6: API Tests (Sprint 6) --------------------------
    // Through the public ALB: register/login/JWT, access control, video catalogue (MongoDB), SPA
    stage('API Tests') {
      when { anyOf { branch 'main'; branch 'Develop'; branch 'Sprint-3' } }
      steps {
        sh 'bash tests/api/api-tests.sh'
      }
    }
    // -- Stage 7: Monitoring Check (Sprints 5-6) ----------------
    // Prometheus scrapes the new pods, nodes and Jenkins; alert rules, Alertmanager and Grafana up
    stage('Monitoring Check') {
      when { anyOf { branch 'main'; branch 'Develop'; branch 'Sprint-3' } }
      steps {
        sh 'bash tests/monitoring/verify-monitoring.sh --with-app'
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
        message: ":x: Build #${BUILD_NUMBER} on ${BRANCH_NAME} FAILED (if Deploy failed, Helm --atomic rolled back to the previous release). Check: ${BUILD_URL}"
    }
    always {
      sh 'docker image prune -af --filter "until=24h" || true'
      cleanWs()
    }
  }
}
