#!/usr/bin/env bash
# Sprint 6: deployment success - every workload rolled out with the image just built, health checks
# and autoscaling configured, each backend healthy from inside the cluster, metrics wired to Prometheus.
# Runs in the Post-deploy Tests stage of the Jenkinsfile (IMAGE_TAG = git SHA); locally see tests/README.md.
set -uo pipefail
source "$(dirname "$0")/../lib.sh"

NS=streamingapp
aws eks update-kubeconfig --name "${EKS_CLUSTER:-streamingapp-cluster}" --region "${AWS_DEFAULT_REGION:-us-east-1}" > /dev/null
DEPLOYMENTS="frontend auth-service streaming-service admin-service chat-service"

section "Rollout"
for d in $DEPLOYMENTS; do
  if kubectl rollout status deploy/"$d" -n $NS --timeout=3m > /dev/null; then pass "$d rolled out"; else fail "$d rollout incomplete"; fi
done
check_ge "MongoDB ready" 1 "$(kubectl get statefulset mongo -n $NS -o jsonpath='{.status.readyReplicas}')"
check "MongoDB volume bound" Bound "$(kubectl get pvc mongo-data-mongo-0 -n $NS -o jsonpath='{.status.phase}')"

section "Images (pinned to the git SHA, never latest)"
for d in $DEPLOYMENTS; do
  IMAGE=$(kubectl get deploy "$d" -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}')
  if [ -n "${IMAGE_TAG:-}" ]; then
    check "$d image tag" "$IMAGE_TAG" "${IMAGE##*:}"
  elif [[ "$IMAGE" =~ :[0-9a-f]{8}$ ]]; then
    pass "$d image pinned (${IMAGE##*:})"
  else
    fail "$d image not pinned to a SHA ($IMAGE)"
  fi
done

section "Health checks and autoscaling"
for d in $DEPLOYMENTS; do
  PROBES=$(kubectl get deploy "$d" -n $NS -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.path} {.spec.template.spec.containers[0].readinessProbe.httpGet.path}')
  if [ "$(wc -w <<< "$PROBES")" -eq 2 ]; then pass "$d liveness + readiness probes ($PROBES)"; else fail "$d missing probes"; fi
done
for h in auth-service streaming-service chat-service; do
  check "HPA $h-hpa targets $h" "$h" "$(kubectl get hpa "$h-hpa" -n $NS -o jsonpath='{.spec.scaleTargetRef.name}')"
done

section "In-cluster health endpoints"
# The frontend image has busybox wget; service DNS names prove Service -> Pod routing works
for svc in auth-service:3001 streaming-service:3002 admin-service:3003 chat-service:3004; do
  NAME=${svc%%:*}; PORT=${svc##*:}
  if kubectl exec -n $NS deploy/frontend -- wget -qO- -T 5 "http://$NAME:$PORT/api/health" > /dev/null; then
    pass "$NAME /api/health"
  else
    fail "$NAME /api/health"
  fi
  # Capture first: with pipefail, grep -q closing the pipe early would make wget's exit status fail the check
  METRICS=$(kubectl exec -n $NS deploy/frontend -- wget -qO- -T 5 "http://$NAME:$PORT/metrics")
  if grep -q '^http_request_duration_seconds' <<< "$METRICS"; then
    pass "$NAME /metrics"
  else
    fail "$NAME /metrics"
  fi
done

section "Monitoring wiring"
check "ServiceMonitors for the 4 backends" 4 "$(kubectl get servicemonitors -n $NS --no-headers 2>/dev/null | wc -l)"

finish
