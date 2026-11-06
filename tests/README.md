# Tests (Sprint 6)

The pipelines run all of these automatically. To run one by hand, use **WSL** (or the Jenkins host) from the repository root: the scripts need `bash`, `python3`, `aws`, `kubectl` and `curl`, plus AWS credentials with cluster access. They only read; the one exception, `api-tests.sh`, registers one throw-away user per run (`ci-test-<timestamp>@streamingapp.test`).

| Script | Checks | Pipeline stage |
|---|---|---|
| `monitoring/run-rule-tests.sh` | `promtool check rules` and the unit tests in `monitoring/alert-rules.test.yml`. Needs Docker; no AWS access | `streamingapp-ansible` → *Test alert rules* |
| `infra/verify-infra.sh` | EKS (status, version, endpoint access, add-ons), node group and Ready nodes, subnets and NAT, Jenkins security group and IAM role, S3 security, Terraform state backend, ECR settings, Ansible bootstrap results | `streamingapp-ansible` → *Verify infrastructure* |
| `monitoring/verify-monitoring.sh [--with-app]` | Monitoring components, scrape targets up (nodes, kube-state-metrics, Jenkins, Jenkins host; with `--with-app` also the 4 backends), alert rule groups, Alertmanager → Slack, Grafana and dashboards | `streamingapp-ansible` → *Verify monitoring*; `streamingapp-app` → *Monitoring Check* |
| `deployment/verify-deployment.sh` | Rollouts, image tag (set `IMAGE_TAG=<sha>` to compare against a specific commit), probes, HPAs, `/api/health` and `/metrics` from inside the cluster, ServiceMonitors | `streamingapp-app` → *Deployment Tests* |
| `api/api-tests.sh [http://<ALB DNS>]` | Through the ALB: SPA, register / duplicate / invalid e-mail, login right and wrong, JWT verify, admin 401/403, chat 401, video catalogue | `streamingapp-app` → *API Tests* |

```bash
# WSL, repository root
aws eks update-kubeconfig --name streamingapp-cluster --region us-east-1
bash tests/infra/verify-infra.sh
bash tests/deployment/verify-deployment.sh
bash tests/api/api-tests.sh
bash tests/monitoring/verify-monitoring.sh --with-app
bash tests/monitoring/run-rule-tests.sh     # Docker Desktop must be running
```

Each script prints one `PASS` / `FAIL` line per check, then `Result: N passed, M failed`. It exits non-zero if any check failed, which turns the Jenkins stage red.

The unit tests live next to the code: `backend/*/__tests__/` (Jest, `npm test`) and `frontend/src/App.test.js`.
