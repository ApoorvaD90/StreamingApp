# StreamingApp — Execution Runbook (Sprints 1–4)

End-to-end steps to build, provision, configure and deploy StreamingApp on AWS EKS with Jenkins, Terraform and Ansible. Follow the phases in order.

## Sprint coverage

| Sprint task | Phase |
|---|---|
| S1 — Dockerize the app, images in ECR | 1 (local), 7 (Jenkins pushes to ECR) |
| S1 — Jenkins server on EC2 with plugins | 4 (EC2 via Terraform), 5 (Ansible installs), 6 (plugins) |
| S1 — Jenkins access to AWS/EKS via IAM roles | 4 (IAM role, EKS access entry), 6 (no static keys) |
| S1 — Git integration triggers builds | 6 (webhook + Multibranch job) |
| S2 — Terraform: VPC, EKS, subnets, SGs, EC2 | 4 |
| S2 — Jenkins job for Terraform, state in S3 | 4 (S3/DynamoDB backend), 7 (`streamingapp-infra` job) |
| S3 — Ansible playbooks for EC2 (Docker, kubectl, …) | 5, 7 |
| S3 — Jenkins Ansible job triggered after Terraform | 7 (`streamingapp-infra` → `streamingapp-ansible`) |
| S4 — Multi-stage pipeline: build, test, deploy | 7 (`streamingapp-app` job) |
| S4 — Build image, push to ECR, deploy manifests to EKS | 7 |
| S4 — Health checks and autoscaling | 7 (probes + HPA), 8 (load test) |
| S4 — End-to-end test from code push to EKS | 7, 8 |

## Pipeline design

| Jenkins job | Definition | Purpose |
|---|---|---|
| `streamingapp-infra` | [`jenkins/Jenkinsfile.infra`](../jenkins/Jenkinsfile.infra) | Terraform init → validate → plan → manual approval → apply. On a successful apply it triggers `streamingapp-ansible`. |
| `streamingapp-ansible` | [`jenkins/Jenkinsfile.ansible`](../jenkins/Jenkinsfile.ansible) | Reads Terraform outputs, configures EC2 (`ansible/site.yml`), bootstraps EKS add-ons, namespace and app secret (`ansible/k8s-bootstrap.yml`). |
| `streamingapp-app` (Multibranch) | [`Jenkinsfile`](../Jenkinsfile) | Unit tests → Docker build → push to ECR (git-SHA tag) → Helm deploy to EKS → smoke tests. Deploy/smoke run only on `Develop` and `main`. |

Security and reproducibility rules this setup follows:

- **No account IDs, ARNs or AWS keys in code or Jenkins.** Jenkins uses the `streamingapp-jenkins-role` EC2 IAM role; the account ID is resolved at runtime with `aws sts get-caller-identity`; IRSA roles are created by Terraform from cluster outputs.
- **No default access CIDR.** `admin_cidr` must be supplied explicitly (`TF_VAR_admin_cidr` locally, the `admin-cidr` credential in Jenkins) and must be a single `/32`. The EKS public API endpoint is restricted to it.
- **No `latest`.** Images are tagged with the git SHA, ECR tags are immutable, the Helm chart refuses an empty or `latest` tag, and EKS add-ons, the Jenkins AMI, tools (kubectl, Helm, Terraform, Ansible) and Helm charts are pinned to exact versions.

## Conventions

- Commands run in **PowerShell** from the repository root unless marked **WSL**.
- ✅ marks the expected result. ❌ means stop and investigate before continuing.
- Keep **one PowerShell window open from Phase 2 to Phase 4** so `$env:` variables persist.

---

## Phase 0 — Laptop prerequisites

**0.1 Tools**
```powershell
git --version
aws --version            # AWS CLI v2
terraform -version       # must be exactly v1.15.7 (same as the Jenkins server)
kubectl version --client # v1.34–v1.36 (cluster is 1.35)
helm version --short     # v3.x or v4.x (only `helm list` is used locally; Jenkins runs the pinned v3.16.4)
node -v                  # v18+ (to run tests locally)
docker --version; docker compose version
```
> Terraform must match the Jenkins server's version (1.15.7, pinned in `terraform/provider.tf` and `ansible/roles/kubectl/defaults/main.yml`). If one side runs a newer version and writes the S3 state, the other can no longer read it. To change versions, update both files together. If several Terraform binaries are installed, check which one each shell picks up: `Get-Command terraform -All` (PowerShell) or `which -a terraform` (Git Bash).

Install anything missing:
```powershell
winget install Amazon.AWSCLI; winget install Kubernetes.kubectl; winget install Helm.Helm
winget install OpenJS.NodeJS.LTS; winget install Docker.DockerDesktop
```

**0.2 WSL (used to run Ansible from the laptop)**
```bash
ansible --version                                   # 2.15+
python3 -c "import boto3, botocore; print('boto3 ok')"
ansible-galaxy collection list | grep amazon.aws
ls -l ~/.ssh/streamingapp-key                       # must exist with -rw------- (600)
```
Fix if missing:
```bash
pip3 install --user ansible boto3 botocore
chmod 600 ~/.ssh/streamingapp-key
```

**0.3 GitHub access**

1. GitHub → Settings → Developer settings → Personal access tokens → generate a **classic** token with scopes `repo` and `admin:repo_hook`. It is used only as a Jenkins credential (Step 6.3).
2. Make sure no token is embedded in the Git remote:
   ```powershell
   git remote -v          # ✅ https://github.com/ApoorvaD90/StreamingApp.git (no token in the URL)
   git remote set-url origin https://github.com/ApoorvaD90/StreamingApp.git   # if it contained one
   ```
   If a token was ever embedded in the URL, revoke that token on GitHub.

---

## Phase 1 — Local validation (Sprint 1: Dockerize)

**1.1 Unit tests (the same suites Jenkins runs)**
```powershell
foreach ($s in "authService","streamingService","adminService","chatService") {
  Push-Location "backend\$s"; npm ci; npm test; Pop-Location
}
Push-Location frontend; npm ci; $env:CI="true"; npm test -- --watchAll=false; Remove-Item Env:CI; Pop-Location
```
✅ Every suite reports `passed`.

**1.2 Local env file** — start Docker Desktop and wait for "Engine running".
```powershell
Copy-Item .env.example .env      # .env is gitignored
notepad .env
```
Set `JWT_SECRET` to a long random string. Optional (video playback from S3): fill the AWS keys, `AWS_S3_BUCKET=streamingapp-videos` and add `AWS_REGION=us-east-1`.

**1.3 Build and run the stack**
```powershell
docker compose up --build -d
docker compose ps                                  # ✅ 6 containers running
3001..3004 | ForEach-Object { "$_ -> " + (Invoke-RestMethod "http://localhost:$_/api/health" | ConvertTo-Json -Compress) }
(Invoke-WebRequest http://localhost:3000/health -UseBasicParsing).StatusCode   # ✅ 200
```
Open http://localhost:3000 and test register, login and chat. Optional sample data: `docker compose exec streaming npm run seed`.
❌ On failure: `docker compose logs <service>`.

**1.4 Stop**
```powershell
docker compose down        # add -v to also wipe the local MongoDB volume
```

---

## Phase 2 — AWS account access and Terraform backend

> Never run this project with the AWS **root** user's access keys. Create an IAM user once (2.1), use its keys everywhere, and delete the root keys (2.3).

**2.1 Create an IAM admin user** (AWS Console, signed in as root — the only time root is used)

1. IAM → **Users** → **Create user** → name `streamingapp-admin` → Next.
2. **Attach policies directly** → tick `AdministratorAccess` → Next → **Create user**.
3. Open the user → **Security credentials** → **Create access key** → *Command Line Interface (CLI)* → tick the confirmation → Create → **Download .csv**. Store it safely; never commit it.
4. Recommended: account menu (top right) → *Security credentials* → enable **MFA** on the root user.

**2.2 Point the CLI at the IAM user**
```powershell
aws configure                  # keys from the .csv, region us-east-1, output json
aws sts get-caller-identity    # ✅ Arn ends in :user/streamingapp-admin (NOT :root)
```

**2.3 Delete the root access keys** (only after 2.2 works)

Console → account menu → *Security credentials* → **Access keys** → *Actions* → Deactivate → Delete.
```powershell
aws iam get-account-summary --query SummaryMap.AccountAccessKeysPresent   # ✅ 0
```

**2.4 Terraform state backend (S3 + DynamoDB lock)**
```powershell
aws s3api head-bucket --bucket streamingapp-tfstate; "bucket ok"
aws dynamodb describe-table --table-name streamingapp-tflock --query Table.TableStatus
```
If they exist (✅ `bucket ok` and `"ACTIVE"`), skip ahead. On a new account (`404 Not Found` / `ResourceNotFoundException`), create them:
```powershell
aws s3api create-bucket --bucket streamingapp-tfstate --region us-east-1
aws s3api put-bucket-versioning --bucket streamingapp-tfstate --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket streamingapp-tfstate --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}'
aws s3api put-public-access-block --bucket streamingapp-tfstate --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws dynamodb create-table --table-name streamingapp-tflock --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
aws dynamodb wait table-exists --table-name streamingapp-tflock; "table ready"
```
> S3 bucket names are global. If `create-bucket` reports `BucketAlreadyExists`, the name is taken by another account: choose a new name and update `bucket` in [`terraform/provider.tf`](../terraform/provider.tf) to match.

**2.5 Admin IP (no default in code)**
```powershell
$myip = (Invoke-RestMethod https://checkip.amazonaws.com).Trim()
$env:TF_VAR_admin_cidr = "$myip/32"
$env:TF_VAR_admin_cidr     # ✅ e.g. 203.0.113.10/32 — also stored in Jenkins in Step 6.3
```

**2.6 Pinned versions** — already set in code; nothing to look up for a new build:

| Item | Pinned value | Where |
|---|---|---|
| EKS | 1.35 (standard support until 2027-03) | `terraform/variables.tf` → `cluster_version` |
| EKS add-ons | coredns `v1.13.2-eksbuild.50`, kube-proxy `v1.35.3-eksbuild.29`, vpc-cni `v1.22.4-eksbuild.3`, aws-ebs-csi-driver `v1.67.0-eksbuild.1` | `eks_addon_versions` |
| Jenkins AMI | `ami-062944a84867f2386` (Ubuntu 22.04, us-east-1) | `jenkins_ami_id` |
| Node AMI type | AL2023 | `terraform/eks.tf` |
| Helm charts | metrics-server `3.14.0`, aws-load-balancer-controller `1.17.1` | `ansible/k8s-bootstrap.yml` |
| Tools on Jenkins | kubectl `v1.35.0`, Helm `v3.16.4`, Terraform `1.15.7`, Ansible `10.7.0` | `ansible/roles/*/defaults/main.yml` |

> Pinning means upgrades are deliberate: change the value, plan, apply. The comments next to each variable show the command to look up newer versions. Avoid EKS versions in *extended support* — the control plane costs 6× more (`aws eks describe-cluster-versions`).

---

## Phase 3 — Commit and merge

```powershell
git add -A
git status --short     # ✅ no .env, node_modules or *.tfvars listed
git commit -m "<message>"
git push origin <your-branch>
```
Open a PR into **Develop** on GitHub and merge it — all Jenkins jobs build from `Develop`.

---

## Phase 4 — Terraform from the laptop (Sprint 2)

The first apply runs from the laptop because the Jenkins server and its IAM role do not exist yet. Use the same PowerShell window (`TF_VAR_admin_cidr` must still be set).

**4.1 Initialise**
```powershell
cd terraform
terraform init -reconfigure -upgrade     # ✅ "Successfully configured the backend "s3"!"
```

**4.2 Plan and review**
```powershell
terraform plan -out tfplan
```
✅ New account: `Plan: <n> to add, 0 to change, 0 to destroy` — VPC, subnets, NAT/IGW, EKS cluster + node group + add-ons, IAM roles (Jenkins, IRSA, node S3 policy), access entries, ECR ×5, S3 video bucket, Jenkins EC2 + Elastic IP + key pair + security group.
✅ Existing infrastructure: only intended changes; **nothing** to destroy or replace.
❌ Do not apply if the plan destroys or replaces (`-/+`) the EKS cluster, node group, VPC or `aws_instance.jenkins`.

**4.3 Apply** (≈20–25 min on a new account; EKS is the slow part)
```powershell
terraform apply tfplan
terraform output
cd ..
```
Note `jenkins_public_ip` (Elastic IP). Jenkins will be at `http://<EIP>:8080` after Phase 5.

**4.4 Cluster access from the laptop**
```powershell
aws eks update-kubeconfig --name streamingapp-cluster --region us-east-1
kubectl get nodes      # ✅ 2 Ready (the IAM user that ran apply is cluster admin)
```

---

## Phase 5 — Ansible from WSL (Sprint 3; Sprint 1 Jenkins tooling)

**5.1 Run** (**WSL**)
```bash
aws sts get-caller-identity          # ✅ :user/streamingapp-admin — if not, run aws configure with the IAM user keys from 2.1 (never root)
cd "<repo>/ansible"                  # e.g. /mnt/c/Users/<you>/.../StreamingApp/ansible
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-inventory -i inventory/aws_ec2.yml --graph   # ✅ Jenkins host under @tag_Role_jenkins
ansible-playbook -i inventory/aws_ec2.yml site.yml   # ✅ PLAY RECAP failed=0
```
Installs Docker, kubectl v1.35.0, Helm v3.16.4, AWS CLI, Terraform 1.15.7, Node 20, Ansible 10.7.0 and Jenkins (versions pinned in `ansible/roles/*/defaults/main.yml`).

**5.2 Verify the Jenkins host** (**WSL**)
```bash
ssh -i ~/.ssh/streamingapp-key ubuntu@<JENKINS_EIP>
sudo systemctl restart jenkins                          # picks up docker group membership
node -v; ansible --version | head -1; helm version --short; kubectl version --client; terraform -version | head -1
sudo -u jenkins aws sts get-caller-identity             # ✅ ...assumed-role/streamingapp-jenkins-role/...
sudo -u jenkins aws eks update-kubeconfig --name streamingapp-cluster --region us-east-1
sudo -u jenkins kubectl get nodes                       # ✅ 2 Ready (access entry + private endpoint)
sudo -u jenkins docker ps                               # ✅ no permission error
sudo cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null   # only for a never-unlocked Jenkins
exit
```

---

## Phase 6 — Jenkins configuration (Sprint 1)

Open `http://<JENKINS_EIP>:8080`. On a fresh install, unlock with the password from 5.2, choose *Install suggested plugins*, create the admin user.

**6.1 Plugins** — Manage Jenkins → Plugins → Available, then *Restart when done*:

| Purpose | Plugins |
|---|---|
| Pipeline core | Pipeline, Pipeline Utility Steps, Timestamper, Workspace Cleanup |
| Git integration | Git, GitHub, GitHub Branch Source |
| Docker | Docker, Docker Pipeline |
| Kubernetes | Kubernetes CLI |
| AWS | AWS Credentials, Pipeline: AWS Steps |
| Credentials | Credentials Binding, SSH Agent |
| Notifications | **Slack Notification** (required — the pipeline calls `slackSend`) |

**6.2 JWT secret** — on an existing cluster reuse the current value (keeps user sessions valid); on a new cluster generate one
```powershell
# New cluster: generate a random 48-byte secret
[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))

# Existing cluster: read the current one instead
$b64 = kubectl get secret streamingapp-secrets -n streamingapp -o jsonpath='{.data.JWT_SECRET}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
```

**6.3 Credentials** — Manage Jenkins → Credentials → System → Global credentials → Add:

| ID (exact) | Kind | Value |
|---|---|---|
| `github-token` | Username with password | GitHub username + the token from 0.3 |
| `streamingapp-ssh-key` | SSH Username with private key | Username `ubuntu`; paste the private key `streamingapp-key` |
| `jwt-secret` | Secret text | Value from 6.2 |
| `admin-cidr` | Secret text | Value from 2.5 (e.g. `203.0.113.10/32`) |

Remove any old static AWS credentials (e.g. `aws-credentials`, `aws-account-id`) — AWS access comes only from the IAM role.

**6.4 Terraform job** — New Item → `streamingapp-infra` → **Pipeline**:
Definition *Pipeline script from SCM* → Git → URL `https://github.com/ApoorvaD90/StreamingApp.git`, credentials `github-token`, branch `*/Develop`, Script Path `jenkins/Jenkinsfile.infra`.

**6.5 Ansible job** — New Item → `streamingapp-ansible` (name must match exactly; the infra job triggers it by name) → **Pipeline**, same settings, Script Path `jenkins/Jenkinsfile.ansible`.

**6.6 App job** — New Item → `streamingapp-app` → **Multibranch Pipeline**:
- Branch Sources → **GitHub**: credentials `github-token`, repository HTTPS URL.
- Behaviours → *Filter by name (with wildcards)* → Include `Develop` (add `main` later; older branches carry an outdated Jenkinsfile).
- Build Configuration → by Jenkinsfile, Script Path `Jenkinsfile` → Save.

**6.7 Webhook** — GitHub repo → Settings → Webhooks → Add:
Payload URL `http://<JENKINS_EIP>:8080/github-webhook/`, content type `application/json`, *Just the push event*.
✅ Recent Deliveries shows a green ping.

---

## Phase 7 — Run the pipelines (Sprints 2, 3, 4)

**7.1 Sprint 2 — Terraform through Jenkins**
1. `streamingapp-infra` → Build with Parameters → ACTION `plan`.
   ✅ **"No changes. Your infrastructure matches the configuration."** — Jenkins reads the same S3 state the laptop wrote, proving provisioning is reproducible.
2. Build with ACTION `apply` → review archived `tfplan.txt` at *Approve* → **Proceed**.
   ✅ `Apply complete!` and `streamingapp-ansible` **starts automatically**.

If `fmt -check` fails: `terraform fmt -recursive` locally, commit, merge.

**7.2 Sprint 3 — Ansible after Terraform**
- *Configure EC2 instances* ✅ `failed=0` (private IP, Jenkins SSH credential).
- *Configure EKS cluster* ✅ metrics-server, AWS Load Balancer Controller, namespace and secret applied.
- ✅ Log shows `APP_PUBLIC_URL = 'http://k8s-streamin-....elb.amazonaws.com'`. On a new cluster it is `''` — expected, the ALB is created by the first app deploy (fixed in 7.4).

If a Helm task reports an existing release or ServiceAccount (from earlier manual installs):
```powershell
helm list -A
helm uninstall <old-release-name> -n kube-system
kubectl delete sa aws-load-balancer-controller -n kube-system
```
Then rebuild the job.

**7.3 Sprint 4 — code push to EKS**
```powershell
git checkout Develop; git pull origin Develop
git commit --allow-empty -m "Trigger CI/CD pipeline"
git push origin Develop
```
✅ `streamingapp-app » Develop` starts within seconds (webhook) and all stages pass:
1. **Checkout** — git SHA and AWS account resolved at runtime
2. **Unit Tests** — 5 parallel suites
3. **Docker Build & Push** — 5 images tagged with the SHA, pushed to ECR (skipped if that tag already exists)
4. **Deploy to EKS** — MongoDB StatefulSet, Helm `--atomic` (auto-rollback on failed health checks), Ingress
5. **Smoke Tests** — 4 in-cluster health checks + 2 external checks through the ALB

✅ Log prints `App URL: http://...elb.amazonaws.com`.

**7.4 New cluster only — set the app URL for CORS** (once, after 7.3 created the ALB)

`streamingapp-ansible` → **Build with Parameters** → leave `APP_URL` empty → Build.
✅ Log shows `APP_PUBLIC_URL = 'http://k8s-streamin-....elb.amazonaws.com'` and the task *Restart app deployments to pick up the changed secret* reports **changed**. Browser login now works through the ALB.

**7.5 Promote to `main`** (optional) — PR **Develop → main**, merge, add `main` to the job's branch filter (`Develop main`), *Scan Repository Now*.

---

## Phase 8 — Verification and evidence

**8.1 Pinned images**
```powershell
kubectl get deploy -n streamingapp -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image
#   ✅ all end in :<8-char SHA>
aws ecr describe-repositories --query "repositories[].[repositoryName,imageTagMutability]" --output table
#   ✅ IMMUTABLE
```

**8.2 Deployment, health checks, autoscaling**
```powershell
kubectl get pods,svc,hpa,ingress -n streamingapp           # ✅ Running 1/1; HPA TARGETS like cpu: 2%/70%
kubectl describe deploy auth-service -n streamingapp | Select-String "Liveness|Readiness"
kubectl top pods -n streamingapp                           # ✅ metrics-server working
```

**8.3 Autoscaling under load** — terminal 1:
```powershell
kubectl run load -n streamingapp --rm -it --image=busybox:1.36 --restart=Never -- sh -c "while true; do wget -qO- http://auth-service:3001/api/health >/dev/null; done"
```
Terminal 2:
```powershell
kubectl get hpa auth-service-hpa -n streamingapp -w
```
✅ Replicas rise above 2 within ~2 min; Ctrl+C the load and they drop back after ~5 min.

**8.4 Self-healing**
```powershell
kubectl delete pod -n streamingapp -l app=auth-service --wait=false; kubectl get pods -n streamingapp -w
```

**8.5 Automatic rollback** (optional) — push a change that breaks a health endpoint to `Develop`; the Deploy stage fails and Helm `--atomic` restores the previous release (`helm history streamingapp -n streamingapp`). Revert afterwards.

**8.6 Application** — open `http://<ALB DNS>`: register, log in, play a video, chat. DevTools → Network: calls go to `/api/auth/...` on the same host.

**8.7 Security posture**
```powershell
aws eks describe-cluster --name streamingapp-cluster --query cluster.resourcesVpcConfig.publicAccessCidrs   # ✅ only the admin /32
```
Jenkins → Credentials holds no AWS keys; the pipeline log shows the account resolved via `sts get-caller-identity`.

Suggested evidence: stage views of all three jobs, the infra → ansible downstream link, webhook delivery, ECR image list, `kubectl get pods,hpa,ingress`, HPA scaling, the app in a browser.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `No value for required variable "admin_cidr"` | Laptop: re-run 2.5 in the current window. Jenkins: `admin-cidr` credential missing |
| `Invalid value for variable` | A pinned value in `variables.tf` is malformed (2.6), or the CIDR is not a `/32` |
| `state snapshot was created by Terraform v1.x` | Laptop and Jenkins Terraform versions differ — both must be 1.15.7 (0.1) |
| `kubectl` from laptop times out | Public IP changed — redo 2.5, `terraform apply`, update the `admin-cidr` credential |
| Ansible: no hosts matched | WSL lacks AWS credentials (`aws configure` in WSL with the IAM user keys) |
| `npm: not found` in Unit Tests | Phase 5 incomplete, or Jenkins not restarted (5.2) |
| `permission denied ... docker.sock` | `sudo systemctl restart jenkins` on the Jenkins host |
| `No such DSL method 'slackSend'` | Install the Slack Notification plugin (6.1) |
| `global.imageTag must be a pinned version` | Guard working as intended — Helm was run without `--set global.imageTag=<sha>` |
| Helm `--atomic` timed out / rolled back | `kubectl get pods -n streamingapp`, `kubectl describe pod <pod>`, `kubectl logs <pod>` |
| CORS error in the browser | Rebuild `streamingapp-ansible` with `APP_URL` empty: it refreshes `CLIENT_URLS` from the Ingress and restarts the pods (7.4) |
| Deploy/Smoke stages skipped | Branch is not `Develop`/`main` — other branches only test and build |
| Webhook delivery times out | Jenkins SG lacks the GitHub ranges (Phase 4 not applied) or Jenkins is stopped |
| `kubectl.exe`: "An Application Control policy has blocked this file" | Windows Smart App Control blocks unsigned binaries (e.g. the Chocolatey kubectl). Remove it (`choco uninstall kubernetes-cli -y`, admin PowerShell) so the Docker Desktop kubectl (signed) is used. If another package depends on it (e.g. Minikube), instead add `$env:Path = "C:\Program Files\Docker\Docker\resources\bin;" + $env:Path` to your PowerShell profile (`notepad $PROFILE`) and open a new window. Check with `(Get-Command kubectl).Source`. Do not disable Smart App Control |

## Cost control

EKS, NAT gateway, ALB and EC2 cost roughly **$6–8/day**. Between work sessions: stop the Jenkins instance and scale the node group to zero:
```powershell
aws eks list-nodegroups --cluster-name streamingapp-cluster
aws eks update-nodegroup-config --cluster-name streamingapp-cluster --nodegroup-name <name> --scaling-config minSize=0,maxSize=6,desiredSize=0
```
Scale back to `minSize=2,desiredSize=2` and start Jenkins before the next session (the Elastic IP keeps the webhook URL stable). Never run `terraform destroy` from Jenkins — it runs on this infrastructure; tear down from the laptop only.
