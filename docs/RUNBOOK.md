# StreamingApp — Execution Runbook (Sprints 1–6)

End-to-end steps to build, provision, configure and deploy StreamingApp on AWS EKS with Jenkins, Terraform and Ansible — and to tear it all down again. Follow the phases in order. Phases 0–9 were executed on a real AWS account (Free plan) on 15–17 Oct 2026; errors hit along the way are folded into the steps and listed in [Troubleshooting](#troubleshooting). Sprint 5 (monitoring) and Sprint 6 (testing, final automation) are integrated into the same phases and add Phases 10–11.

## Rebuild quick start

**Starting point:** everything from the last run was deleted (Phase 9) — no AWS resources, no Terraform state bucket or lock table, and no `streamingapp-admin` IAM user. All code fixes are already committed on the **`Sprint-3`** branch, which the Jenkins jobs build from.

| Phase | What you do | Time |
|---|---|---|
| 0 | Check laptop tools (one-off fixes already done on this laptop are noted) | 5 min |
| 1 | Run unit + alert-rule tests and the Docker stack locally (incl. `/metrics`) | 15 min |
| 2 | Create the IAM user + access key, create the state bucket and lock table, set your IP | 15 min |
| 3 | Pull the latest `Sprint-3` | 1 min |
| 4 | `terraform apply` from the laptop | 25 min |
| 5 | Ansible from WSL (installs tools + node_exporter on Jenkins) | 10 min |
| 6 | Slack app; Jenkins UI: unlock, plugins, 7 credentials, Slack, 3 jobs, webhook | 35 min |
| 7 | Run infra → ansible → app as one automatic chain, then a git push | 40 min |
| 8 | Verify and take screenshots | 20 min |
| 10 | Sprint 5: Prometheus, Grafana, alerts to Slack, Jenkins notifications | 40 min |
| 11 | Sprint 6: test evidence, end-to-end validation | 30 min |
| 9 | Tear everything down (**last**, after 10 and 11) | 30 min |

> **Free plan budget.** EKS, the NAT gateway and the ALB are not free: about **$7.20/day fully running, ~$4.35/day paused** (the 4th Spot node and Prometheus' 5 GiB volume add ~$0.25/day). Check remaining credits with `aws freetier get-account-plan-state --query accountPlanRemainingCredits.amount`. The plan expires **13 Nov 2026** — finish and tear down before then.

**Resuming after a laptop restart** (do this before continuing at any phase after 4):
1. New PowerShell window → `kubectl version --client` ✅ Docker Desktop's kubectl (profile loaded). Start Docker Desktop if a later step uses it.
2. Home IP changed? `(Invoke-RestMethod https://checkip.amazonaws.com).Trim()` vs `aws eks describe-cluster --name streamingapp-cluster --query cluster.resourcesVpcConfig.publicAccessCidrs`. If they differ, Jenkins (`:8080`), SSH and `kubectl` all time out although everything is running → set `$env:TF_VAR_admin_cidr = "<new-ip>/32"`, then in `terraform/`: `terraform plan "-out=ip.tfplan"` (✅ only in-place updates: Jenkins SG, EKS public CIDRs, OIDC thumbprint "known after apply"; 0 to destroy) → `terraform apply ip.tfplan`. Update the Jenkins `admin-cidr` credential to the same value if it already exists.
3. `kubectl get nodes` ✅ 4 Ready; `http://<JENKINS_EIP>:8080` ✅ login page.

**Delivery branch:** the jobs and the Jenkinsfile deploy condition use **`Sprint-3`**. If the code is merged into `Develop` or `main` later, use that branch name in Steps 6.4–6.6 and 7.3 (deploy already runs on `main`, `Develop` and `Sprint-3`).

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
| S5 — Prometheus in EKS collecting app and node metrics | 7 (Ansible installs it), 10.1–10.2 |
| S5 — Grafana dashboards for application performance and resource health | 10.3 |
| S5 — Jenkins integrated with Prometheus/Grafana | 6.1 (plugin), 5 (node_exporter), 10.4 |
| S5 — Alert rules, Jenkins notifications for failed deployments / resource issues | 6.1b, 6.3a (Slack), 10.5–10.7 |
| S5 — Test monitoring and alerting | 10.5–10.7, 11.2 |
| S6 — Test cases: app functionality, deployment, infrastructure | 1.1, 7, 11.1–11.3 |
| S6 — Documentation of pipeline, Terraform, Ansible incl. troubleshooting | this runbook, README, [`tests/README.md`](../tests/README.md) |
| S6 — Automated triggers (code → build → deploy; infra → config → deploy) | 6.7, 7, 11.4 |
| S6 — Final end-to-end testing, feedback and adjustments | 11.4–11.6 |

## Pipeline design

| Jenkins job | Definition | Purpose |
|---|---|---|
| `streamingapp-infra` | [`jenkins/Jenkinsfile.infra`](../jenkins/Jenkinsfile.infra) | Terraform init → validate → plan → manual approval → apply. On a successful apply it triggers `streamingapp-ansible`. |
| `streamingapp-ansible` | [`jenkins/Jenkinsfile.ansible`](../jenkins/Jenkinsfile.ansible) | Reads Terraform outputs → tests the alert rules → configures EC2 (`ansible/site.yml`) → bootstraps EKS add-ons, namespace, app secret **and the monitoring stack** (`ansible/k8s-bootstrap.yml`) → verifies infrastructure and monitoring. On success it **triggers `streamingapp-app/Sprint-3`**. |
| `streamingapp-app` (Multibranch) | [`Jenkinsfile`](../Jenkinsfile) | Unit tests → Docker build → push to ECR (git-SHA tag) → Helm deploy to EKS → deployment tests → API tests → monitoring check. Deploy and tests run only on `Sprint-3`, `Develop` and `main`. Triggered by a GitHub push or by `streamingapp-ansible`. |

All three jobs post to Slack `#devops-alerts` on failure (the app job also on success); Alertmanager posts firing/resolved alerts to the same channel.

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

Laptop-specific notes (already handled on the current laptop; redo on a new one):
- **`kubectl` "blocked by an Application Control policy"** — Windows Smart App Control blocks the unsigned Chocolatey `kubectl` (it cannot be uninstalled while Minikube depends on it). A PowerShell profile puts Docker Desktop's signed kubectl first: `notepad $PROFILE` containing `$env:Path = "C:\Program Files\Docker\Docker\resources\bin;" + $env:Path`. Check: `(Get-Command kubectl).Source`. Do not disable Smart App Control.
- **Two Terraform versions** — `C:\terraform\terraform.exe` (1.15.7, used by PowerShell) and an old `C:\Users\Apoorva\bin\terraform` (1.7.0, only seen by Git Bash). Always run Terraform from **PowerShell**; the pin in `provider.tf` rejects 1.7.0.
- **Windows PowerShell 5.1 quirks** — quote arguments containing dots (`"-out=destroy.tfplan"`); avoid `"` inside `git commit -m` messages (use `git commit -F file.txt`).

**0.2 WSL (used to run Ansible from the laptop)**
```bash
aws --version                                       # AWS CLI v2 inside WSL (separate from Windows')
ansible --version                                   # 2.15+
python3 -c "import boto3, botocore; print('boto3 ok')"
ansible-galaxy collection list | grep amazon.aws
ls -l ~/.ssh/streamingapp-key                       # must exist with -rw------- (600)
```
Fix if missing:
```bash
# AWS CLI v2 (official installer; not the old apt/snap package)
cd ~ && sudo apt update && sudo apt install -y unzip curl
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip
# The "Tip: run 'aws configure agent-toolkit'" message after install is optional — ignore it

pip3 install --user ansible boto3 botocore
cp /mnt/c/Users/Apoorva/.ssh/streamingapp-key ~/.ssh/ && chmod 600 ~/.ssh/streamingapp-key
```

**0.3 GitHub access**

1. GitHub → profile picture → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token (classic)**: note `jenkins-streamingapp`, expiration 90 days, scopes **`repo`** and **`admin:repo_hook`** → Generate → **copy it immediately** (`ghp_...`; GitHub shows it only once). It is used only as a Jenkins credential (Step 6.3). Lost it? Generate a new one and edit the Jenkins credential.
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
✅ Every suite reports `passed` — backend: auth 5, streaming 3, admin 6, chat 5 tests (each includes 2 new `metrics.test.js` tests).

**1.1b Alert rule tests** (Sprint 6) — start Docker Desktop first; run in **WSL** (Git Bash mangles the Docker volume path):
```bash
cd "/mnt/c/Users/Apoorva/OneDrive/Documents/Personal/HV/Capstone/Final Project/Own_Repo/StreamingApp"
bash tests/monitoring/run-rule-tests.sh
```
✅ `SUCCESS: 12 rules found` and `SUCCESS` (5 alert unit tests). The Ansible pipeline runs the same script.
❌ `docker: command not found` in WSL: Docker Desktop → Settings → Resources → **WSL integration** → enable your distro → Apply.

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
(Invoke-WebRequest http://localhost:3002/metrics -UseBasicParsing).Content -split "`n" | Select-String "^http_request_duration_seconds_count"
#   ✅ lines like http_request_duration_seconds_count{method="GET",route="/api/health",status_code="200"} 3  (Sprint 5 app metrics)
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
3. Open the user → **Security credentials** tab → scroll to **Access keys** → **Create access key** → *Command Line Interface (CLI)* → tick the confirmation → Next → Create → **Download .csv file** (the secret is shown only once). Store it safely; never commit it.
4. Recommended: account menu (top right) → *Security credentials* → enable **MFA** on the root user.

> The name must be exactly `streamingapp-admin` — Terraform grants this user EKS cluster-admin and KMS key-admin (`admin_iam_user` in `variables.tf`).

**2.2 Point the CLI at the IAM user**
```powershell
aws configure                  # Access Key ID (AKIA..., 20 chars) and Secret (40 chars) from the .csv; region us-east-1; output json
aws sts get-caller-identity    # ✅ Arn ends in :user/streamingapp-admin (NOT :root)
```
> `InvalidClientTokenId` here means the wrong values were entered — the CLI needs the **access key** pair from the .csv, not the user name or console password. If a console password was ever shown on screen, change it (IAM → user → Security credentials → Manage console access).

**2.3 Deactivate or delete the root access keys** (only after 2.2 works; nothing in the project uses them)

Console → account menu → *Security credentials* → **Access keys** → *Actions* → **Deactivate** (reversible) or Delete.
```powershell
aws iam get-account-summary --query SummaryMap.AccountAccessKeysPresent   # ✅ 0 after delete
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
aws dynamodb describe-table --table-name streamingapp-tflock --query Table.TableStatus   # ✅ "ACTIVE"
```
> If "table ready" scrolled past or didn't print, the `describe-table` line (or DynamoDB → Tables in the console, region N. Virginia) confirms it.
>
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
| Helm charts | metrics-server `3.14.0`, aws-load-balancer-controller `1.17.1`, kube-prometheus-stack `92.3.1` | `ansible/k8s-bootstrap.yml` |
| Monitoring | node_exporter `1.12.1` (Jenkins host, checksum-verified), `prom/prometheus:v3.15.1` (rule tests), `prom-client` 15.1.3 (lock files) | `ansible/roles/node_exporter/defaults/main.yml`, `tests/monitoring/run-rule-tests.sh`, `backend/*/package-lock.json` |
| Tools on Jenkins | kubectl `v1.35.0`, Helm `v3.16.4`, Terraform `1.15.7`, Ansible `10.7.0` | `ansible/roles/*/defaults/main.yml` |

> Pinning means upgrades are deliberate: change the value, plan, apply. The comments next to each variable show the command to look up newer versions. Avoid EKS versions in *extended support* — the control plane costs 6× more (`aws eks describe-cluster-versions`).
>
> Instance types are limited to **Free Tier eligible** ones on the AWS Free plan (`aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true`): Jenkins uses `c7i-flex.large`, nodes 4 × `t3.small` (a t3.small runs at most 11 pods; add-ons + app + monitoring need ~34). A rebuild weeks later may find the pinned add-on versions or AMI retired — `plan` then fails with an invalid-version error; look up current values with the commands in `variables.tf` and update them.

**2.7 Budget alert (recommended, free)** — emails at 50% and 80% of $100:
```powershell
$acct = aws sts get-caller-identity --query Account --output text
aws budgets create-budget --account-id $acct `
  --budget '{\"BudgetName\":\"streamingapp-credits\",\"BudgetLimit\":{\"Amount\":\"100\",\"Unit\":\"USD\"},\"TimeUnit\":\"MONTHLY\",\"BudgetType\":\"COST\"}' `
  --notifications-with-subscribers '[{\"Notification\":{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":50,\"ThresholdType\":\"PERCENTAGE\"},\"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"<your-email>\"}]},{\"Notification\":{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":80,\"ThresholdType\":\"PERCENTAGE\"},\"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"<your-email>\"}]}]'
```

---

## Phase 3 — Get the latest code

All fixes are already committed on `Sprint-3`; the Jenkins jobs build from it.
```powershell
git checkout Sprint-3
git pull origin Sprint-3
git status --short     # ✅ clean (or only your own doc edits)
```
If you change anything before running Jenkins, commit and push it to `Sprint-3` — **Jenkins builds from GitHub, not from your laptop** (a missing push caused `Unable to find jenkins/Jenkinsfile.infra` in the last run).

---

## Phase 4 — Terraform from the laptop (Sprint 2)

The first apply runs from the laptop because the Jenkins server and its IAM role do not exist yet. Use the same PowerShell window (`TF_VAR_admin_cidr` must still be set).

**4.1 Initialise**
```powershell
cd terraform
terraform -version                   # ✅ v1.15.7 (PowerShell's binary)
terraform init -reconfigure          # ✅ "Successfully configured the backend "s3"!"
```
Do not add `-upgrade`: it rewrites `.terraform.lock.hcl` with newer providers, and Jenkins must use the same providers as the laptop (the lock file is committed).

**4.1b Remove leftovers from an earlier cluster** (they make `apply` fail with *already exists*)
```powershell
aws logs describe-log-groups --log-group-name-prefix /aws/eks/streamingapp-cluster --query "logGroups[].logGroupName" --output text
aws iam list-open-id-connect-providers --output text
```
If the log group exists and no cluster exists, delete it:
`aws logs delete-log-group --log-group-name /aws/eks/streamingapp-cluster/cluster`. Old EKS OIDC providers do not block apply but can be deleted (`aws iam delete-open-id-connect-provider --open-id-connect-provider-arn <arn>`).

**4.2 Plan and review**
```powershell
terraform plan -out tfplan
```
✅ New account: `Plan: <n> to add, 0 to change, 0 to destroy` — VPC, subnets, NAT/IGW, EKS cluster + node group (4 nodes) + add-ons, IAM roles (Jenkins, IRSA, node S3 policy), access entries, ECR ×5, S3 video bucket, Jenkins EC2 + Elastic IP + key pair + security group (incl. the Sprint 5 rules for ports 8080/9100 from the private subnets).
✅ Existing infrastructure: only intended changes; **nothing** to destroy or replace.
❌ Do not apply if the plan destroys or replaces (`-/+`) the EKS cluster, node group, VPC or `aws_instance.jenkins`.

**4.3 Apply** (≈20–25 min on a new account; EKS is the slow part)
```powershell
terraform apply tfplan
terraform output
cd ..
```
Note `jenkins_public_ip` (Elastic IP) and `jenkins_private_ip` (Prometheus scrapes this one). Jenkins will be at `http://<EIP>:8080` after Phase 5.
If apply stops on an error, fix it and run `terraform plan -out tfplan` + `terraform apply tfplan` again — resources already created are kept.

**4.4 Cluster access from the laptop**
```powershell
aws eks update-kubeconfig --name streamingapp-cluster --region us-east-1
kubectl get nodes      # ✅ 4 Ready (the IAM user that ran apply is cluster admin)
```

---

## Phase 5 — Ansible from WSL (Sprint 3; Sprint 1 Jenkins tooling)

**5.1 Run** (**WSL**)
```bash
aws sts get-caller-identity          # ✅ :user/streamingapp-admin — if not, run aws configure with the IAM user keys from 2.1 (never root)
cd "/mnt/c/Users/Apoorva/OneDrive/Documents/Personal/HV/Capstone/Final Project/Own_Repo/StreamingApp/ansible"
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-inventory -i inventory/aws_ec2.yml --graph   # ✅ Jenkins host under @tag_Role_jenkins
ansible-playbook -i inventory/aws_ec2.yml site.yml   # ✅ PLAY RECAP failed=0
```
Installs Docker, kubectl v1.35.0, Helm v3.16.4, AWS CLI, Terraform 1.15.7, Node 20, Ansible 10.7.0, node_exporter 1.12.1 (Sprint 5) and Jenkins (versions pinned in `ansible/roles/*/defaults/main.yml`).

**5.2 Verify the Jenkins host** (**WSL**)
```bash
ssh -i ~/.ssh/streamingapp-key ubuntu@<JENKINS_EIP>
sudo systemctl restart jenkins                          # picks up docker group membership
node -v; ansible --version | head -1; helm version --short; kubectl version --client; terraform -version | head -1
sudo -u jenkins aws sts get-caller-identity             # ✅ ...assumed-role/streamingapp-jenkins-role/...
sudo -u jenkins aws eks update-kubeconfig --name streamingapp-cluster --region us-east-1
sudo -u jenkins kubectl get nodes                       # ✅ 4 Ready (access entry + private endpoint)
sudo -u jenkins docker ps                               # ✅ no permission error
systemctl is-active node_exporter; curl -s localhost:9100/metrics | grep -c ^node_   # ✅ active, a few hundred
sudo cat /var/lib/jenkins/secrets/initialAdminPassword  # 32-character unlock password for Step 6.0
exit
```
> Once logged in, the prompt changes to `ubuntu@ip-10-0-...` — you are **on** the server, so run the remaining commands directly; running `ssh ... ubuntu@<EIP>` again from there times out. When copying the unlock password, select only the 32 characters (paste through Notepad if unsure); stray spaces cause "password is incorrect".

---

## Phase 6 — Jenkins configuration (Sprints 1, 5)

**6.0 Unlock** — open `http://<JENKINS_EIP>:8080` (from your laptop; only your IP is allowed) → paste the password from 5.2 → **Install suggested plugins** → create your admin user → Save and Finish. Next time, just log in with that user.

**6.1 Plugins** — Manage Jenkins → **Plugins** → **Available plugins** → search, tick, **Install** → tick *Restart Jenkins when installation is complete*:

| Purpose | Plugins |
|---|---|
| Pipeline core | Pipeline, Pipeline Utility Steps, Timestamper, Workspace Cleanup |
| Git integration | Git, GitHub, GitHub Branch Source |
| Docker | Docker, Docker Pipeline |
| Kubernetes | Kubernetes CLI |
| AWS | AWS Credentials, Pipeline: AWS Steps |
| Credentials | Credentials Binding, SSH Agent |
| Notifications | **Slack Notification** (required — all three pipelines call `slackSend`) |
| Monitoring (Sprint 5) | **Prometheus metrics** (exposes `/prometheus/` for Prometheus in EKS) |

> A plugin missing from *Available plugins* is usually **already installed** by *Install suggested plugins* (Pipeline, Timestamper, Workspace Cleanup, Git, Credentials Binding, SSH Agent, GitHub Branch Source…). Check **Installed plugins** and search there.

After the restart, check the metrics endpoint from the laptop (PowerShell; leave the plugin's settings in Manage Jenkins → System → *Prometheus* at their defaults — the endpoint must stay **without** authentication):
```powershell
(curl.exe -s http://<JENKINS_EIP>:8080/prometheus/) -split "`n" | Select-String "^default_jenkins_" | Select-Object -First 5
#   ✅ lines like default_jenkins_executors_available 2.0
```

**6.1b Slack app** (Sprint 5 — one app gives both the Jenkins bot token and the Alertmanager webhook)

1. No Slack workspace yet? https://slack.com/get-started → *Create a new workspace* (free). Create a channel **`#devops-alerts`**.
2. https://api.slack.com/apps → **Create New App** → *Blank app* (older UI: *From scratch*) → Continue → name `StreamingApp Alerts`, pick the workspace → Create App.
3. Left menu **Incoming Webhooks** → switch **On** → **Add New Webhook to Workspace** → channel `#devops-alerts` → Allow → copy the **Webhook URL** (`https://hooks.slack.com/services/...`) → credential `slack-webhook-url` in 6.3.
4. Left menu **OAuth & Permissions** → *Bot Token Scopes* → **Add an OAuth Scope** → `chat:write` → scroll up → **Reinstall to Workspace** → Allow → copy the **Bot User OAuth Token** (`xoxb-...`) → credential `slack-bot-token` in 6.3.
5. In Slack, in `#devops-alerts`, type `/invite @StreamingApp Alerts`.
6. Note your **workspace subdomain**: the part before `.slack.com` in the workspace URL (Slack → workspace name → *Settings* / browser address bar).

Treat both values like passwords: they let anyone post to the channel. Lost one? Regenerate it on the same page and update the Jenkins credential.

**6.2a Grafana admin password** (PowerShell) — copy the output into credential `grafana-admin-password` in 6.3:
```powershell
$b = New-Object byte[] 18; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [Convert]::ToBase64String($b)
```

**6.2 JWT secret** (PowerShell on the laptop — this command works in Windows PowerShell 5.1)
```powershell
# New cluster: generate a random 48-byte secret
$b = New-Object byte[] 48; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [Convert]::ToBase64String($b)

# Existing cluster: read the current one instead (keeps user sessions valid)
$b64 = kubectl get secret streamingapp-secrets -n streamingapp -o jsonpath='{.data.JWT_SECRET}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
```
Copy the output straight into the credential in 6.3 — Jenkins stores it, no other copy is needed. Lost before saving it? Just generate another.

**6.3 Credentials** — Manage Jenkins → **Credentials** → **System** → **Global credentials (unrestricted)** → **Add Credentials** → pick the kind → **Next**:

| ID (exact) | Kind | Fields |
|---|---|---|
| `github-token` | Username with password | Username `ApoorvaD90`; Password = the `ghp_...` token from 0.3 |
| `streamingapp-ssh-key` | SSH Username with private key | Username `ubuntu`; Private Key → *Enter directly* → **Add** → paste the key; Passphrase empty |
| `jwt-secret` | Secret text | Secret = value from 6.2 |
| `admin-cidr` | Secret text | Secret = value from 2.5, e.g. `203.0.113.10/32` |
| `slack-bot-token` | Secret text | Secret = `xoxb-...` from 6.1b step 4 |
| `slack-webhook-url` | Secret text | Secret = `https://hooks.slack.com/services/...` from 6.1b step 3 |
| `grafana-admin-password` | Secret text | Secret = value from 6.2a |

To copy the private key without displaying it (PowerShell):
```powershell
Get-Content C:\Users\Apoorva\.ssh\streamingapp-key -Raw | Set-Clipboard
```
then Ctrl+V into the Private Key box. It must start with `-----BEGIN OPENSSH PRIVATE KEY-----` and end with `-----END OPENSSH PRIVATE KEY-----`.

Do not create static AWS credentials — AWS access comes only from the Jenkins IAM role.

**6.3a Slack in Jenkins** — Manage Jenkins → **System** → scroll to **Slack**:
- Workspace: the subdomain from 6.1b step 6
- Credential: `slack-bot-token`
- Default channel / member id: `#devops-alerts`
- Tick **Custom slack app bot user**
- **Test Connection** → ✅ `Success` and a test message appears in `#devops-alerts` → **Save**.

**6.4 Terraform job** — **New Item** → name `streamingapp-infra` → **Pipeline** → OK → *Pipeline* section: Definition **Pipeline script from SCM** → SCM **Git** → Repository URL `https://github.com/ApoorvaD90/StreamingApp.git`, Credentials `github-token` → Branch Specifier **`*/Sprint-3`** → Script Path `jenkins/Jenkinsfile.infra` → **Save**.

**6.5 Ansible job** — New Item → `streamingapp-ansible` (exact name — the infra job triggers it by name) → **Pipeline**, same settings, Branch **`*/Sprint-3`**, Script Path `jenkins/Jenkinsfile.ansible` → Save.

**6.6 App job** — New Item → `streamingapp-app` → **Multibranch Pipeline**:
- Branch Sources → Add source → **GitHub**: Credentials `github-token`, Repository HTTPS URL as above.
- Behaviours → Add → **Filter by name (with wildcards)** → Include **`Sprint-3`** (older branches carry an outdated Jenkinsfile).
- Build Configuration → Mode *by Jenkinsfile*, Script Path `Jenkinsfile` → **Save**.

Saving triggers a scan, which **immediately builds `Sprint-3`** — including Deploy. Before Phase 7.1 has run the Ansible bootstrap this build fails at Deploy (no secret/StorageClass yet); abort it (✕) or ignore it (the failure also posts a ❌ to Slack — that is fine). The real run is triggered automatically in 7.1–7.3.

**6.7 Webhook** — GitHub repo → **Settings** → **Webhooks** → **Add webhook**: Payload URL `http://<JENKINS_EIP>:8080/github-webhook/`, Content type `application/json`, *Just the push event* → Add webhook.
✅ Edit → **Recent Deliveries** shows a green ✔ ping. (Settings is visible only to repo admins.)

---

## Phase 7 — Run the pipelines (Sprints 2, 3, 4, 5, 6)

One apply now starts the whole chain automatically: **`streamingapp-infra` → `streamingapp-ansible` (configuration + monitoring + verification) → `streamingapp-app/Sprint-3` (build, deploy, tests)**.

**7.1 Sprint 2 — Terraform through Jenkins** (`streamingapp-infra`)
1. **Build Now** the first time (the job learns its `ACTION` parameter from the Jenkinsfile and runs a `plan`); afterwards use **Build with Parameters**.
2. ACTION **`plan`** → Build.
   ✅ **"No changes. Your infrastructure matches the configuration."** — Jenkins reads the same S3 state the laptop wrote.
3. ACTION **`apply`** → Build. It pauses at **Approve**: open the build → **Console Output** (or **Pipeline Overview** → the paused stage) and scroll to the bottom for **Proceed / Abort**.
   - **Read the `Plan:` line first. Proceed only if it says `0 to destroy`.** Anything to destroy or replace → **Abort** and investigate (in the last run this caught a change that would have removed the laptop user's cluster access).
   - ✅ `Apply complete!` and `streamingapp-ansible` **starts automatically**.

If `fmt -check` fails: `terraform fmt -recursive` locally, commit, push.

**7.2 Sprint 3 + 5 — Ansible after Terraform** (nothing to run — just check; ~15 min)

Open `streamingapp-ansible` → the newest build:
- Status page says **"Started by upstream project streamingapp-infra"** — the Sprint 3 evidence screenshot.
- *Test alert rules* ✅ `SUCCESS: 12 rules found` and `SUCCESS` (Sprint 6).
- *Configure EC2 instances* ✅ `failed=0` (now includes node_exporter on the Jenkins host).
- *Configure EKS cluster* ✅ metrics-server, AWS Load Balancer Controller, gp3 StorageClass, namespace and secret, then **Sprint 5**: monitoring namespace, Grafana/Slack secrets, *Install kube-prometheus-stack* (~5 min), alert rules, 2 dashboards.
- *Verify infrastructure* ✅ `Result: N passed, 0 failed` (Sprint 6).
- *Verify monitoring* ✅ `Result: ... passed, 0 failed` — includes `Jenkins (Prometheus metrics plugin)` and `Jenkins host (node_exporter)` targets up.
- `APP_PUBLIC_URL = ''` is expected on a new cluster — the ALB only appears in 7.3.
- At the end: *Scheduling project: streamingapp-app » Sprint-3* (Sprint 6 trigger).

Optional check from the laptop:
```powershell
kubectl get deploy -n kube-system aws-load-balancer-controller metrics-server   # ✅ READY 2/2 and 1/1
kubectl get storageclass                                                       # ✅ gp3 (default)
kubectl get pods -n monitoring                                                 # ✅ 8 pods Running (node-exporter x4)
```

**7.3 Sprint 4 + 6 — app deploy, started by Ansible, then by a code push** (`streamingapp-app`)

First run: `streamingapp-app » Sprint-3` starts automatically after 7.2 — status page **"Started by upstream project streamingapp-ansible"** (Sprint 6 trigger evidence). Let it finish (~20 min the first time), then push to show the webhook path:
```powershell
git pull origin Sprint-3
git commit --allow-empty -m "Trigger CI/CD pipeline"
git push origin Sprint-3
```
✅ `streamingapp-app » Sprint-3` starts within seconds (webhook, **"Started by GitHub push"**) and all stages pass:
1. **Checkout** — git SHA and AWS account resolved at runtime
2. **Unit Tests** — 5 parallel suites
3. **Docker Build & Push** — 5 images tagged with the SHA, pushed to ECR (skipped if that tag already exists)
4. **Deploy to EKS** — MongoDB StatefulSet, Helm `--atomic` (auto-rollback on failed health checks; now also creates 4 ServiceMonitors), Ingress. On a new cluster it waits for the ALB, sets the CORS origin and restarts the pods (`CORS origin set to http://k8s-...`) — Sprint 6, replaces the old manual Ansible re-run
5. **Deployment Tests** — rollouts, SHA tags, probes, HPAs, `/api/health` + `/metrics` of each backend (`Result: N passed, 0 failed`)
6. **API Tests** — through the ALB: SPA, register/login/JWT, 401/403 access control, catalogue (`App URL: http://k8s-streamingapp-....elb.amazonaws.com`, `Result: N passed, 0 failed`)
7. **Monitoring Check** — Prometheus scrapes the 4 backends, nodes, Jenkins; rules, Alertmanager, Grafana

✅ Slack `#devops-alerts` shows `:white_check_mark: Build #N on Sprint-3 succeeded. Tag: <sha>`.

Harmless log line: `Could not update commit status` (GitHub status badge). It does not fail the build.
No build started? `streamingapp-app` → **Scan Repository Now**, and check the webhook's Recent Deliveries.

**7.4 CORS** — automatic now (step 4 above). Fallback if the browser still shows CORS errors: `streamingapp-ansible` → **Build with Parameters** → leave `APP_URL` empty → Build. ✅ `APP_PUBLIC_URL = 'http://k8s-streamingapp-....'`; the secret tasks show `ok` when the app pipeline already set the same value.

**7.5 Promote** (optional) — PR **Sprint-3 → Develop** (then `main`), merge, and add the branch to the job's filter (e.g. `Sprint-3 Develop main`) → *Scan Repository Now*.

---

## Phase 8 — Verification and evidence

Connect kubectl first in each new PowerShell window: `aws eks update-kubeconfig --name streamingapp-cluster --region us-east-1`.

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
✅ Replicas rise above 1 within ~2 min; Ctrl+C the load and they drop back after ~5 min.

**8.4 Self-healing**
```powershell
kubectl delete pod -n streamingapp -l app=auth-service --wait=false; kubectl get pods -n streamingapp -w
```

**8.5 Automatic rollback** (optional) — push a change that breaks a health endpoint to `Sprint-3`; the Deploy stage fails and Helm `--atomic` restores the previous release (`helm history streamingapp -n streamingapp`). Revert afterwards.

**8.6 Application** — open the App URL: register, log in, chat. DevTools (F12) → Network: calls go to `/api/auth/...` on the same host. The video list is empty until videos are uploaded to S3.

**8.7 Webhook evidence** — GitHub → Settings → Webhooks → Edit → **Recent Deliveries** → expand a `push` delivery → **Response 200**. Pair it with the app build's status page: *"Started by GitHub push"*.

**8.8 Security posture**
```powershell
aws sts get-caller-identity                     # ✅ :user/streamingapp-admin
aws eks describe-cluster --name streamingapp-cluster --query cluster.resourcesVpcConfig.publicAccessCidrs   # ✅ only the admin /32
```

Screenshot checklist: infra stage view + "No changes" plan · ansible "Started by upstream project" · ansible stage view · app `Sprint-3` stage view (all green) · webhook delivery 200 · ECR SHA tags · `kubectl get pods,svc,hpa,ingress` · HPA scaling · app in a browser. Crop out keys, tokens and passwords.

---

## Phase 9 — Teardown (after screenshots)

> Run this **after Phases 10 and 11** — teardown is the last step even though it is numbered 9.

Order matters: Kubernetes-created AWS resources first (Terraform does not know them and they block VPC deletion), then empty ECR/S3, then Terraform, then the backend. Use one PowerShell window from the repo root.

**9.1 Kubernetes-created resources** (ALB, target groups, MongoDB's and Prometheus' EBS volumes)
```powershell
kubectl delete ingress --all -n streamingapp --wait=true
helm uninstall streamingapp -n streamingapp --wait
kubectl delete statefulset mongo -n streamingapp --wait=true
kubectl delete pvc --all -n streamingapp --wait=true
helm uninstall monitoring -n monitoring --wait
kubectl delete pvc --all -n monitoring --wait=true
aws ec2 describe-volumes --filters Name=tag-key,Values=kubernetes.io/created-for/pvc/name --query "Volumes[].[VolumeId,State]"   # ✅ [] (wait a minute if not)
aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerName"   # ✅ [] (wait a minute if not)
```

**9.2 ECR repositories** — force-delete (removes all images; Terraform cannot delete non-empty repos)
```powershell
foreach ($r in "admin-service","auth-service","chat-service","frontend","streaming-service") { aws ecr delete-repository --repository-name "streamingapp/$r" --force --query repository.repositoryName --output text }
```
(The video bucket `streamingapp-videos` must also be empty; if you uploaded videos, empty it in the S3 console → *Empty*.)

**9.3 Terraform destroy** (laptop only — never from Jenkins, which runs on this infrastructure)
```powershell
$env:TF_VAR_admin_cidr = "$((Invoke-RestMethod https://checkip.amazonaws.com).Trim())/32"
cd terraform
terraform plan -destroy "-out=destroy.tfplan"     # quotes needed in PowerShell 5.1; review: only project resources
terraform apply destroy.tfplan                    # ~15 min
terraform state list                              # ✅ empty
Remove-Item destroy.tfplan; cd ..
```

**9.4 Leftovers** — check, and delete anything project-related:
```powershell
aws logs describe-log-groups --log-group-name-prefix /aws/eks --query "logGroups[].logGroupName"
aws iam list-open-id-connect-providers
aws ec2 describe-volumes --query "Volumes[].VolumeId"
aws elbv2 describe-target-groups --query "TargetGroups[].TargetGroupName"
```
The EKS KMS key shows *PendingDeletion* for 30 days — normal, not billed.

**9.5 State backend**
```powershell
# Empty the versioned bucket (all versions) in the S3 console: streamingapp-tfstate → Empty, then:
aws s3api delete-bucket --bucket streamingapp-tfstate
aws dynamodb delete-table --table-name streamingapp-tflock
```

**9.5b Slack** (optional) — https://api.slack.com/apps → `StreamingApp Alerts` → *Basic Information* → **Delete App** (revokes the bot token and webhook).

**9.6 IAM user** — Console as **root** → IAM → Users → `streamingapp-admin` → **Delete** (removes its key and policy). The CLI cannot do this step: it uses that user's own key. Afterwards `aws sts get-caller-identity` fails with `InvalidClientTokenId` — confirmation it is gone. Optionally delete `C:\Users\Apoorva\.aws\credentials` and `~/.aws/credentials` in WSL.

---

## Phase 10 — Monitoring and alerting (Sprint 5)

Everything was installed by the pipelines in Phase 7; this phase shows it working and tests the alerts. Connect kubectl first in each new PowerShell window: `aws eks update-kubeconfig --name streamingapp-cluster --region us-east-1`.

**10.1 Components**
```powershell
kubectl get pods -n monitoring -o wide
#   ✅ Running: prometheus-...-0 (2/2), alertmanager-...-0 (2/2), monitoring-grafana (3/3),
#      monitoring-kube-prometheus-operator, monitoring-kube-state-metrics, node-exporter x4 (one per node)
kubectl get servicemonitors -A        # ✅ 4 in streamingapp (one per backend) + the chart's own
kubectl get prometheusrules -n monitoring streamingapp-alerts
kubectl get pvc -n monitoring         # ✅ Bound, 5Gi, gp3
```

**10.2 Prometheus** — terminal 1 (keep it open while you look):
```powershell
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
```
Browser http://localhost:9090:
- **Status → Target health**: ✅ every pool **UP** — `serviceMonitor/streamingapp/auth-service/0`, `.../streaming-service/0`, `.../admin-service/0`, `.../chat-service/0`, `jenkins`, `jenkins-node`, `node-exporter` (4), `kube-state-metrics`, `kubelet`, `apiserver`, `coredns`. Screenshot.
- **Alerts**: ✅ groups `streamingapp.application`, `streamingapp.nodes`, `streamingapp.jenkins` (all *inactive*, green) plus the chart's defaults; `Watchdog` firing is normal (it proves the alert path works). Screenshot.
- **Query** tab, *Graph* — try:
  - `sum by (job) (rate(http_request_duration_seconds_count{namespace="streamingapp"}[5m]))` — requests/s per service
  - `100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))` — CPU per node, incl. `jenkins`
  - `default_jenkins_builds_last_build_result_ordinal` — 0 = success per Jenkins job

Ctrl+C to stop the port-forward.

**10.3 Grafana dashboards** — terminal 1:
```powershell
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```
(If port 3000 is busy, `docker compose down` from Phase 1.) Browser http://localhost:3000 → user `admin`, password = the `grafana-admin-password` credential.
- **Dashboards** → folder *General* → **StreamingApp - Application**: request rate, 5xx, p95 latency per service; pod CPU/memory; HPA replicas; restarts; Node.js heap and event loop; node CPU/memory/pods/disk. Use the app in another tab for a minute first so the traffic panels have data. Screenshot.
- **StreamingApp - Jenkins CI/CD**: Jenkins UP, last build result per job (green SUCCESS), build durations, executors, Jenkins host CPU/memory/disk. Screenshot.
- Built-in: **Kubernetes / Compute Resources / Namespace (Pods)** (namespace `streamingapp`) and **Node Exporter / Nodes** — resource health. Screenshot one.

**10.4 Jenkins ↔ Prometheus integration** (evidence)
```powershell
(curl.exe -s http://<JENKINS_EIP>:8080/prometheus/) -split "`n" | Select-String "last_build_result_ordinal"
#   ✅ one line per job, e.g. default_jenkins_builds_last_build_result_ordinal{jenkins_job="streamingapp-app/Sprint-3",...} 0.0
```
The same values appear in the Jenkins dashboard (10.3), so Prometheus scrapes Jenkins over the private network.

**10.5 Alert test — service down → Slack** (~3 min each way). Terminal 1 (port-forward Alertmanager to watch it):
```powershell
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093
```
Terminal 2:
```powershell
kubectl scale deploy admin-service -n streamingapp --replicas=0
```
- Prometheus Alerts page (10.2) shows `AppServiceDown` **pending** then **firing** after 1 min; http://localhost:9093 lists it.
- ✅ Slack `#devops-alerts`: `:rotating_light: FIRING: AppServiceDown (critical)` — *admin-service has no available pods*. Screenshot.

Restore:
```powershell
kubectl scale deploy admin-service -n streamingapp --replicas=1
```
✅ A few minutes later Slack shows `:white_check_mark: RESOLVED: AppServiceDown`. Screenshot.
(admin-service has no HPA, so scaling it is safe. Do not use a service with an HPA — the HPA cannot scale up from 0 and the app pipeline's next deploy would be needed.)

**10.6 Jenkins failed-deployment notification** (Sprint 5: "Jenkins sends notifications for failed deployments"). Break a unit test on purpose; the pipeline fails **before** Deploy, so the running app is not touched:
```powershell
(Get-Content backend\streamingService\__tests__\health.test.js) -replace "msg: 'OK'", "msg: 'BROKEN'" | Set-Content backend\streamingService\__tests__\health.test.js
git commit -am "Demo: failing test to show Jenkins failure notification"
git push origin Sprint-3
```
✅ `streamingapp-app » Sprint-3` fails at *Unit Tests → Streaming Service*; Slack shows `:x: Build #N on Sprint-3 FAILED ...` with the link. Screenshot.
✅ ~2 min later (Prometheus plugin refreshes every 2 min) Slack also shows `FIRING: JenkinsJobFailed` from Alertmanager. Screenshot.

Revert:
```powershell
git revert --no-edit HEAD
git push origin Sprint-3
```
✅ Build succeeds (`:white_check_mark: ... succeeded`), then `RESOLVED: JenkinsJobFailed`.

**10.7 Resource alerts under load** (optional) — rerun the load test from 8.3 for ~10 min and watch *StreamingApp - Application* (requests/s, CPU by pod, HPA replicas rising). If a node stays above 85% CPU for 10 min, `HostHighCPU` fires to Slack.

Screenshot checklist (Sprint 5): `kubectl get pods -n monitoring` · Prometheus targets all UP · Prometheus alert rules · both StreamingApp dashboards · one built-in Kubernetes dashboard · `/prometheus/` output from Jenkins · Slack FIRING + RESOLVED (AppServiceDown) · Slack Jenkins ❌ and ✅ messages · JenkinsJobFailed alert. Crop out tokens, webhook URLs and the Grafana password.

---

## Phase 11 — Testing and final validation (Sprint 6)

**11.1 Test inventory** — what runs where (details: [`tests/README.md`](../tests/README.md)):

| Level | Script / suite | Runs in |
|---|---|---|
| Unit (19 backend + frontend tests) | `backend/*/__tests__/`, `frontend/src/App.test.js` | Phase 1.1; app pipeline *Unit Tests* |
| Alert rules (12 rules, 5 unit tests) | `tests/monitoring/run-rule-tests.sh` | Phase 1.1b; ansible pipeline *Test alert rules* |
| Infrastructure integrity | `tests/infra/verify-infra.sh` | ansible pipeline *Verify infrastructure* |
| Monitoring | `tests/monitoring/verify-monitoring.sh` | ansible *Verify monitoring*; app *Monitoring Check* |
| Deployment success | `tests/deployment/verify-deployment.sh` | app *Deployment Tests* |
| Application functionality | `tests/api/api-tests.sh` | app *API Tests* |

**11.2 Pipeline test evidence** — open the green builds from Phase 7 and screenshot the console output of: `streamingapp-ansible` → *Verify infrastructure* and *Verify monitoring* (the `PASS` lines and `Result: N passed, 0 failed`); `streamingapp-app » Sprint-3` → *Deployment Tests*, *API Tests*, *Monitoring Check*; and the stage view of both jobs (all stages green).

**11.3 Run the tests by hand** (**WSL**, repository root — shows they are independent of Jenkins):
```bash
cd "/mnt/c/Users/Apoorva/OneDrive/Documents/Personal/HV/Capstone/Final Project/Own_Repo/StreamingApp"
aws eks update-kubeconfig --name streamingapp-cluster --region us-east-1
bash tests/infra/verify-infra.sh
bash tests/deployment/verify-deployment.sh
bash tests/api/api-tests.sh
bash tests/monitoring/verify-monitoring.sh --with-app
```
✅ Each ends with `Result: N passed, 0 failed`.
❌ `kubectl ... timed out` from WSL: your public IP changed — see Troubleshooting. `python3: not found`: `sudo apt install -y python3`.

**11.4 Final end-to-end run** — prove the whole chain from one action, with nothing done by hand:
1. `streamingapp-infra` → **Build with Parameters** → `apply` → Approve (✅ `0 to destroy`; on an unchanged environment the plan shows *No changes* and apply is a no-op).
2. ✅ `streamingapp-ansible` starts (*Started by upstream project streamingapp-infra*) → all stages green.
3. ✅ `streamingapp-app » Sprint-3` starts (*Started by upstream project streamingapp-ansible*) → all 7 stages green.
4. ✅ Slack shows the app success message; no alert other than any you triggered.
Screenshot the three build status pages showing the *Started by upstream project* lines, and the Jenkins dashboard in Grafana with all three jobs SUCCESS.

**11.5 Resilience checks** (repeat Phase 8.3–8.5 if not captured yet): HPA scale-out under load, self-healing after a pod delete, automatic Helm rollback (8.5 — the failed deploy also posts ❌ to Slack and fires `JenkinsJobFailed`).

**11.6 Feedback and adjustments** — changes made for production readiness during Sprints 5–6 (cite in the report):

| Observation | Adjustment |
|---|---|
| A new cluster needed a manual Ansible re-run to set the CORS origin | The app pipeline sets it once the ALB exists (Deploy stage) |
| Ansible and app deploys were started by hand | `streamingapp-ansible` triggers the app pipeline; push → build → deploy → test via webhook |
| Smoke tests checked only health endpoints | Deployment, API (auth flow, access control) and monitoring tests with PASS/FAIL reports |
| 3 × t3.small could not fit the monitoring stack (11 pods per node) | 4 Spot nodes (+~$0.17/day); monitoring requests kept small; Prometheus retention 3 days on 5 GiB |
| Grafana/Prometheus would need another load balancer (~$0.55/day) and public exposure | Accessed with `kubectl port-forward` only |
| EKS control-plane components cannot be scraped and would alert permanently | Those scrape jobs and default rules disabled |
| Slack secrets must not be in code | Jenkins credentials → Kubernetes Secrets (Alertmanager reads the webhook URL from a file) |

---

## Troubleshooting

Every error below was hit during a real run; the fix is either already in the code or a step above.

| Symptom | Cause / fix |
|---|---|
| `aws: InvalidClientTokenId` after `aws configure` | User name / console password entered instead of the **access key** pair (2.2) |
| `head-bucket ... 404 Not Found` | State bucket does not exist (new account or after teardown) — create it (2.4) |
| `aws: command not found` in WSL | Install AWS CLI v2 in WSL (0.2) |
| `kubectl.exe`: "An Application Control policy has blocked this file" | Smart App Control blocks the unsigned Chocolatey kubectl; use Docker Desktop's signed kubectl via the PowerShell profile (0.1). `choco uninstall kubernetes-cli` fails while Minikube depends on it. Do not disable Smart App Control |
| `Unsupported Terraform Core version` / `state snapshot was created by Terraform v1.x` | Wrong Terraform binary — use PowerShell's 1.15.7 (0.1). Laptop and Jenkins must match |
| `No value for required variable "admin_cidr"` | Laptop: re-run 2.5 in the current window. Jenkins: `admin-cidr` credential missing |
| `Invalid value for variable` | A pinned value in `variables.tf` is malformed or retired (2.6), or the CIDR is not a `/32` |
| `Error: Too many command line arguments` (PowerShell) | PowerShell 5.1 split an argument at a dot — quote it: `"-out=destroy.tfplan"` |
| `InvalidParameterCombination: ... not eligible for Free Tier` | Free plan allows Free Tier instance types only — Jenkins `c7i-flex.large`, nodes `t3.small` (already in code) |
| `ResourceAlreadyExistsException: The specified log group already exists` | Left over from an earlier cluster — delete it (4.1b) and re-apply |
| Jenkins plan wants to **replace** `aws_eks_access_entry` (admin user → Jenkins role) | Fixed in code: admins are explicit (`admin_iam_user` + Jenkins role) with `moved` blocks. If it reappears, Abort and check `eks.tf` |
| `kubectl` from laptop times out | Public IP changed — redo 2.5, `terraform apply`, update the `admin-cidr` credential |
| `ssh: connect to host <EIP> port 22: Connection timed out` while on the Jenkins server | You are already on it (`ubuntu@ip-10-0-...`) — run commands directly (5.2) |
| Unlock: "The password entered is incorrect" | Copied extra characters — copy only the 32-character line (5.2) |
| Ansible: no hosts matched | WSL lacks AWS credentials (`aws configure` in WSL with the IAM user keys) |
| `ERROR: Unable to find jenkins/Jenkinsfile.infra` | Job reads a branch without the file — jobs must use `*/Sprint-3` and changes must be pushed (Phase 3, 6.4) |
| Approve step "missing" on apply | It is waiting at the bottom of **Console Output** / in **Pipeline Overview** (7.1) |
| `npm: not found` in Unit Tests | Phase 5 incomplete, or Jenkins not restarted (5.2) |
| `docker compose up --build`: `ERROR: invalid file request chatService/node_modules/...` (other builds `CANCELED`) | The `backend/` build context sent the Windows `node_modules` from 1.1 — fixed: `backend/.dockerignore` excludes them |
| *Test alert rules* / 1.2: `promtool: error: stat rules.yml: permission denied` | Container ran as `nobody` and could not read the temp folder — fixed: `run-rule-tests.sh` runs it as the calling user |
| `permission denied ... docker.sock` | `sudo systemctl restart jenkins` on the Jenkins host |
| Docker build: `bcrypt` / `node-pre-gyp ... ECONNREFUSED`, `gyp ERR! find Python` | Prebuilt binary download blocked; fixed in code (multi-stage auth Dockerfile with build tools) |
| `No such DSL method 'slackSend'` | Install the Slack Notification plugin (6.1) |
| `Slack notification failed ... credential ... could not be found` | Slack not configured in Jenkins — do 6.1b, 6.3 (`slack-bot-token`) and 6.3a; *Test Connection* must succeed |
| Slack *Test Connection*: `not_in_channel` / no message | Invite the app: `/invite @StreamingApp Alerts` in `#devops-alerts` (6.1b step 5) |
| Ansible: `VPC_ID, LB_ROLE_ARN, ... must be set` | A Jenkins credential is missing (`grafana-admin-password`, `slack-webhook-url` must start with `https://hooks.slack.com/`), or the Terraform apply that added the `jenkins_private_ip` output has not run |
| Ansible: `Install kube-prometheus-stack` times out; pods `Pending`, events `Too many pods` | Fewer than 4 nodes. New cluster: check `node_desired`; existing: `aws eks update-nodegroup-config ... --scaling-config minSize=4,maxSize=6,desiredSize=4` |
| *Test alert rules* fails: `docker: permission denied` | `sudo systemctl restart jenkins` on the Jenkins host (docker group) |
| *Test alert rules* fails on a rule | The output names the rule/test; fix `k8s/monitoring/alert-rules.yaml` and run 1.1b locally before pushing |
| Prometheus target `jenkins` or `jenkins-node` DOWN (`context deadline exceeded`) | Security group rules for 8080/9100 not applied (run the infra job), node_exporter not running (5.2), or Jenkins stopped |
| Target `jenkins` DOWN with `403` / `401` | Prometheus plugin authentication was enabled — Manage Jenkins → System → *Prometheus* → untick *Enable authentication for prometheus end-point* |
| Grafana Jenkins dashboard: some panels *No data* | Jobs have not run since the plugin was installed, or the plugin version names a metric differently: check names with the 10.4 command and adjust the panel query |
| App targets missing in Prometheus | Chart deployed before the monitoring stack existed (no ServiceMonitor CRD) — rerun the app pipeline; check `kubectl get servicemonitors -n streamingapp` |
| No Slack message for a firing alert | `kubectl logs -n monitoring alertmanager-monitoring-kube-prometheus-alertmanager-0 -c alertmanager` — `invalid_token` / `no_service`: wrong webhook URL; update `slack-webhook-url` and rerun the Ansible job |
| *Verify monitoring* / *Monitoring Check* hangs at "Scrape targets"; `error trying to reach service: dial tcp 10.0.x.x:9090: connect: connection timed out` | The API server's service proxy could not reach the Prometheus pod: the node security group allowed the control plane on webhook ports only — fixed: `node_security_group_additional_rules` in `eks.tf` opens 9090/9093/3000 from the cluster SG; `terraform apply`, rerun `streamingapp-ansible` |
| Grafana login fails | Password is the `grafana-admin-password` credential; after changing it, rerun the Ansible job (it restarts Grafana) |
| `port-forward`: `address already in use` | Something else uses the port (e.g. Docker Compose on 3000) — stop it or use another local port, e.g. `3001:80` |
| *API Tests*: `register new user` gets 500 | MongoDB not ready — `kubectl get pods -n streamingapp`, `kubectl logs -n streamingapp deploy/auth-service` |
| Test scripts in WSL: `$'\r': command not found` | CRLF line endings — `git pull` (the repo forces LF for `*.sh` via `.gitattributes`), or `git checkout -- tests/` after pulling |
| Deploy: `timed out waiting for the condition`; `mongo-0` Pending, PVC "no storage class is set" | EKS 1.30+ has no default StorageClass — fixed: gp3 default created by the Ansible bootstrap (run 7.1/7.2 before 7.3) |
| Deploy: `release ... failed ... atomic ... context deadline exceeded`; events `Too many pods`, `Insufficient memory` | Nodes full — fixed: 3 × t3.small, services start at 1 replica. Check `kubectl get events -n streamingapp` |
| `global.imageTag must be a pinned version` | Guard working as intended — Helm was run without `--set global.imageTag=<sha>` |
| CORS error / login fails in the browser | Run 7.4 (Ansible with `APP_URL` empty) — it sets `CLIENT_URLS` from the Ingress and restarts the pods |
| Ansible re-run shows `ok` / `skipping` for the secret tasks | Correct — the secret already had the right values |
| Deploy/Smoke stages skipped | Branch is not `Sprint-3`/`Develop`/`main` — other branches only test and build |
| Webhook delivery times out / `failed to connect to host` | Jenkins SG lacks the GitHub ranges (Phase 4 not applied), GitHub added new ranges — compare `(Invoke-RestMethod https://api.github.com/meta).hooks` with `github_webhook_cidrs` in `variables.tf` (the `9.234.x.x/28` ranges were added this way), apply, push — or Jenkins is stopped |
| Destroy: `ECR Repository ... not empty` | Force-delete the repos (9.2), then `terraform destroy` again |

## Cost control

EKS, the NAT gateway, the ALB and EC2 cost about **$7.20/day** fully running (Sprint 5 adds a 4th Spot node and a 5 GiB volume; Grafana/Prometheus use port-forward instead of another ALB). Pause at the end of every session (~$4.35/day):
```powershell
aws ec2 stop-instances --instance-ids (aws ec2 describe-instances --filters Name=tag:Name,Values=streamingapp-jenkins --query "Reservations[].Instances[].InstanceId" --output text)
aws eks update-nodegroup-config --cluster-name streamingapp-cluster --nodegroup-name (aws eks list-nodegroups --cluster-name streamingapp-cluster --query "nodegroups[0]" --output text) --scaling-config minSize=0,maxSize=6,desiredSize=0
```
Resume (wait ~4 min before using Jenkins or the app; Prometheus and the alerts come back with the nodes — expect a short burst of `RESOLVED` messages in Slack):
```powershell
aws ec2 start-instances --instance-ids (aws ec2 describe-instances --filters Name=tag:Name,Values=streamingapp-jenkins --query "Reservations[].Instances[].InstanceId" --output text)
aws eks update-nodegroup-config --cluster-name streamingapp-cluster --nodegroup-name (aws eks list-nodegroups --cluster-name streamingapp-cluster --query "nodegroups[0]" --output text) --scaling-config minSize=4,maxSize=6,desiredSize=4
```
The Elastic IP keeps the Jenkins URL and webhook stable across stop/start. Away for 3+ days or finished: run **Phase 9**. Check credits any time: `aws freetier get-account-plan-state --query accountPlanRemainingCredits.amount`.
