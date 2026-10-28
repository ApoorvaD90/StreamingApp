#!/usr/bin/env bash
# Sprint 6: application functionality through the public ALB - the path real users take.
# Registers a throw-away user (unique e-mail, random password generated per run), then checks
# login, token verification, access control on admin/chat APIs, the video catalogue and the SPA.
# Usage: bash tests/api/api-tests.sh [http://<ALB DNS>]   (default: read from the Ingress)
set -uo pipefail
source "$(dirname "$0")/../lib.sh"

URL="${1:-}"
if [ -z "$URL" ]; then
  # A new ALB takes a few minutes to get its hostname and pass health checks
  for i in $(seq 1 30); do
    ALB=$(kubectl get ingress streamingapp-ingress-frontend -n streamingapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    [ -n "$ALB" ] && break
    echo "Waiting for ALB hostname ($i/30)..."; sleep 10
  done
  [ -n "${ALB:-}" ] || { echo "FAIL: Ingress has no ALB hostname after 5 minutes"; exit 1; }
  URL="http://$ALB"
fi
echo "App URL: $URL"
curl -fsS --retry 30 --retry-delay 10 --retry-all-errors -o /dev/null "$URL/health" || { echo "FAIL: ALB never became healthy"; exit 1; }

BODY=$(mktemp); trap 'rm -f "$BODY"' EXIT
# status <method> <path> [json body] [bearer token] -> HTTP status code; response body in $BODY
status() {
  local args=(-s -o "$BODY" -w '%{http_code}' -X "$1" "$URL$2" -H 'Content-Type: application/json')
  [ -n "${3:-}" ] && args+=(-d "$3")
  [ -n "${4:-}" ] && args+=(-H "Authorization: Bearer $4")
  curl "${args[@]}"
}

EMAIL="ci-test-$(date +%s)-$RANDOM@streamingapp.test"
PASSWORD=$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')

section "Frontend"
check "GET /health" 200 "$(status GET /health)"
check "GET / serves the React app" 200 "$(status GET /)"
if grep -q 'id="root"' "$BODY"; then pass "index.html contains the React root"; else fail "index.html has no React root"; fi

section "Auth service"
check "register new user" 201 "$(status POST /api/auth/register "{\"name\":\"CI Test\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")"
check "register same e-mail again is rejected" 409 "$(status POST /api/auth/register "{\"name\":\"CI Test\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")"
check "register with invalid e-mail is rejected" 400 "$(status POST /api/auth/register '{"name":"x","email":"not-an-email","password":"123456"}')"
check "login with wrong password" 401 "$(status POST /api/auth/login "{\"email\":\"$EMAIL\",\"password\":\"wrong-$PASSWORD\"}")"
check "login with correct password" 200 "$(status POST /api/auth/login "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")"
TOKEN=$(json 'd.get("token", "")' < "$BODY" 2>/dev/null)
if [ -n "$TOKEN" ]; then pass "login returns a JWT"; else fail "login returned no token"; fi
check "verify token" 200 "$(status GET /api/auth/verify "" "$TOKEN")"
check "verified user is the one registered" "$EMAIL" "$(json 'd["user"]["email"]' < "$BODY" 2>/dev/null)"
check "verify without token" 401 "$(status GET /api/auth/verify)"

section "Access control"
check "admin API without token" 401 "$(status GET /api/admin/videos)"
check "admin API with a normal user's token" 403 "$(status GET /api/admin/videos "" "$TOKEN")"
check "chat history without token" 401 "$(status GET /api/chat/history/any-video)"

section "Streaming service (through MongoDB)"
check "featured videos" 200 "$(status GET /api/streaming/videos/featured)"
if json 'type(d).__name__' < "$BODY" > /dev/null 2>&1; then pass "featured videos returns JSON"; else fail "featured videos did not return JSON"; fi
check "video list" 200 "$(status GET /api/streaming/videos)"

finish
