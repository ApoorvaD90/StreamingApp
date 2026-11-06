#!/usr/bin/env bash
# Sprint 6: checks that monitoring and alerting work end to end: components running, every scrape
# target up (nodes, Jenkins, and with --with-app the 4 backend services), alert rules loaded,
# Alertmanager routing to Slack, Grafana healthy with the StreamingApp dashboards.
# Talks to Prometheus/Alertmanager/Grafana through the Kubernetes API service proxy (no port-forward).
# Usage: bash tests/monitoring/verify-monitoring.sh [--with-app]
set -uo pipefail
source "$(dirname "$0")/../lib.sh"

NS=monitoring
WITH_APP=false
[ "${1:-}" = "--with-app" ] && WITH_APP=true
aws eks update-kubeconfig --name "${EKS_CLUSTER:-streamingapp-cluster}" --region "${AWS_DEFAULT_REGION:-us-east-1}" > /dev/null

proxy() { kubectl get --raw "/api/v1/namespaces/$NS/services/$1/proxy$2"; }
prom()  { proxy monitoring-kube-prometheus-prometheus:9090 "$1"; }
# promq '<PromQL>' -> first value of an instant query ('' if no result)
promq() {
  local q
  q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")
  prom "/api/v1/query?query=$q" | json 'd["data"]["result"][0]["value"][1] if d["data"]["result"] else ""'
}

section "Components"
for d in monitoring-kube-prometheus-operator monitoring-grafana monitoring-kube-state-metrics; do
  check_ge "deployment $d available" 1 "$(kubectl get deploy "$d" -n $NS -o jsonpath='{.status.availableReplicas}')"
done
check_ge "Prometheus ready" 1 "$(kubectl get statefulset prometheus-monitoring-kube-prometheus-prometheus -n $NS -o jsonpath='{.status.readyReplicas}')"
check_ge "Alertmanager ready" 1 "$(kubectl get statefulset alertmanager-monitoring-kube-prometheus-alertmanager -n $NS -o jsonpath='{.status.readyReplicas}')"
NODES=$(kubectl get nodes --no-headers | wc -l)
check "node-exporter on every node" "$NODES" "$(kubectl get ds monitoring-prometheus-node-exporter -n $NS -o jsonpath='{.status.numberReady}')"

section "Scrape targets (up == 1)"
# A new target needs one or two scrape intervals (30s) before it reports up: retry for up to 3 minutes
wait_up() {
  local desc=$1 query=$2 min=$3 got=""
  for _ in $(seq 1 18); do
    got=$(promq "$query")
    [ -n "$got" ] && [ "$got" -ge "$min" ] 2>/dev/null && break
    sleep 10
  done
  check_ge "$desc" "$min" "$got"
}
wait_up "EKS nodes (node-exporter)" 'sum(up{job="node-exporter"})' "$NODES"
wait_up "kube-state-metrics" 'sum(up{job="kube-state-metrics"})' 1
wait_up "Jenkins (Prometheus metrics plugin)" 'sum(up{job="jenkins"})' 1
wait_up "Jenkins host (node_exporter)" 'sum(up{job="jenkins-node"})' 1
if $WITH_APP; then
  for svc in auth-service streaming-service admin-service chat-service; do
    wait_up "app $svc /metrics" "sum(up{namespace=\"streamingapp\", job=\"$svc\"})" 1
  done
  wait_up "app request metrics recorded" 'count(http_request_duration_seconds_count{namespace="streamingapp"})' 1
fi

section "Alerting"
RULE_GROUPS=$(prom /api/v1/rules | json '" ".join(sorted(g["name"] for g in d["data"]["groups"]))')
for g in streamingapp.application streamingapp.nodes streamingapp.jenkins; do
  if [[ " $RULE_GROUPS " == *" $g "* ]]; then pass "rule group $g loaded"; else fail "rule group $g not loaded"; fi
done
check "Prometheus connected to Alertmanager" 1 "$(prom /api/v1/alertmanagers | json 'len(d["data"]["activeAlertmanagers"])')"
check "Watchdog alert firing (alert pipeline alive)" 1 "$(promq 'count(ALERTS{alertname="Watchdog", alertstate="firing"})')"
AM_CONFIG=$(proxy monitoring-kube-prometheus-alertmanager:9093 /api/v2/status | json 'd["config"]["original"]')
if grep -q "api_url_file: /etc/alertmanager/secrets/alertmanager-slack/webhook-url" <<< "$AM_CONFIG"; then
  pass "Alertmanager routes to Slack (webhook URL read from Secret)"
else
  fail "Alertmanager has no Slack receiver"
fi

section "Grafana"
check "Grafana health" ok "$(proxy monitoring-grafana:80 /api/health | json 'd["database"]')"
for cm in grafana-dashboard-streamingapp-application grafana-dashboard-jenkins-ci; do
  check "dashboard ConfigMap $cm" 1 "$(kubectl get configmap "$cm" -n $NS -o jsonpath='{.metadata.labels.grafana_dashboard}')"
done

finish
