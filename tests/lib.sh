# Shared helpers for the Sprint 6 test scripts (sourced, not executed).
# Each check prints PASS/FAIL; finish() exits non-zero if any check failed, so Jenkins marks the stage red.

PASSED=0
FAILED=0

pass() { echo "  PASS  $*"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL  $*"; FAILED=$((FAILED + 1)); }
section() { echo; echo "== $* =="; }

# check "<description>" <expected> <actual>
check() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

# check_ge "<description>" <minimum> <actual>
check_ge() {
  if [ -n "$3" ] && [ "$3" -ge "$2" ] 2>/dev/null; then pass "$1 ($3)"; else fail "$1 (expected >= $2, got '$3')"; fi
}

finish() {
  echo
  echo "Result: $PASSED passed, $FAILED failed"
  [ "$FAILED" -eq 0 ]
}

# json '<python expression on d>' : reads JSON from stdin (python3 is on Jenkins, WSL and Git Bash)
json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
