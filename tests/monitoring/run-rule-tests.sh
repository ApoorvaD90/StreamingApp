#!/usr/bin/env bash
# Sprint 6: validate and unit-test the Prometheus alert rules with promtool (in Docker, pinned image).
# Usage (repo root): bash tests/monitoring/run-rule-tests.sh
set -euo pipefail

PROMETHEUS_IMAGE="prom/prometheus:v3.15.1"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# promtool reads plain rule files: take the PrometheusRule's spec (everything under 'spec:'), de-indented
awk 'f { sub(/^  /, ""); print } /^spec:/ { f = 1 }' k8s/monitoring/alert-rules.yaml > "$WORK/rules.yml"
cp tests/monitoring/alert-rules.test.yml "$WORK/"

# Run as the calling user: the image defaults to 'nobody', which cannot read the private (700) mktemp folder
PROMTOOL=(docker run --rm --user "$(id -u):$(id -g)" -v "$WORK:/work" -w /work --entrypoint promtool "$PROMETHEUS_IMAGE")
"${PROMTOOL[@]}" check rules rules.yml
"${PROMTOOL[@]}" test rules alert-rules.test.yml
