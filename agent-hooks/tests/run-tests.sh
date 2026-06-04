#!/usr/bin/env bash
# Reference test harness for the banking agent-runtime hooks.
# Pure bash + coreutils; no kiro-cli required. Runs on macOS dev and Amazon Linux EC2.

HERE="$(cd "$(dirname "$0")/.." && pwd)"   # agent-hooks/
PASS=0; FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
ng() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# ev <event> <tool> <tool_input_json>  -> emits a hook JSON event
ev() { printf '{"hook_event_name":"%s","cwd":"/tmp","tool_name":"%s","tool_input":%s}' "$1" "$2" "$3"; }

echo "== pii-guard =="
ev preToolUse write '{"path":"a.txt","content":"card 4111 1111 1111 1111"}'   | bash "$HERE/pii-guard.sh" 2>/dev/null && ng "should block credit card"   || ok "blocks credit card"
ev preToolUse write '{"path":"a.txt","content":"key AKIAIOSFODNN7EXAMPLE x"}'  | bash "$HERE/pii-guard.sh" 2>/dev/null && ng "should block AWS key"       || ok "blocks AWS access key"
ev preToolUse write '{"path":"id.txt","content":"NRIC S1234567D"}'             | bash "$HERE/pii-guard.sh" 2>/dev/null && ng "should block NRIC"          || ok "blocks Singapore NRIC"
ev preToolUse write '{"path":".env","content":"password=SuperSecret123!"}'     | bash "$HERE/pii-guard.sh" 2>/dev/null && ng "should block secret"        || ok "blocks secret assignment"
ev preToolUse write '{"path":"app.py","content":"def add(a,b): return a+b"}'   | bash "$HERE/pii-guard.sh" 2>/dev/null && ok "allows clean code"           || ng "false positive on clean code"

echo "== git-guard =="
ev preToolUse shell '{"command":"git push --force origin main"}' | bash "$HERE/git-guard.sh" 2>/dev/null && ng "should block force-push"   || ok "blocks force-push"
ev preToolUse shell '{"command":"git push -u origin main"}'      | bash "$HERE/git-guard.sh" 2>/dev/null && ng "should block protected push" || ok "blocks push to main"
ev preToolUse shell '{"command":"git reset --hard HEAD~3"}'      | bash "$HERE/git-guard.sh" 2>/dev/null && ng "should block reset --hard"   || ok "blocks reset --hard"
ev preToolUse shell '{"command":"git push origin feature/x"}'    | bash "$HERE/git-guard.sh" 2>/dev/null && ok "allows feature-branch push"  || ng "false positive on feature push"
ev preToolUse shell '{"command":"git status"}'                   | bash "$HERE/git-guard.sh" 2>/dev/null && ok "allows git status"           || ng "false positive on git status"

echo "== audit-logger =="
TMPLOG="$(mktemp)"; TMPSTATE="$(mktemp)"
export KIRO_AUDIT_LOG="$TMPLOG" KIRO_AUDIT_STATE="$TMPSTATE" KIRO_SESSION_ID="test-session"
ev postToolUse shell '{"command":"ls"}' | bash "$HERE/audit-logger.sh" >/dev/null 2>&1
[ -s "$TMPLOG" ]                      && ok "writes an audit record"   || ng "no audit record written"
grep -q '"tool":"shell"' "$TMPLOG"    && ok "records tool name"        || ng "tool name missing"
grep -q 'hash=' "$TMPLOG"             && ok "record is hash-chained"   || ng "hash chain missing"
ev postToolUse read '{"path":"x"}' | bash "$HERE/audit-logger.sh" >/dev/null 2>&1
[ "$(wc -l < "$TMPLOG")" -eq 2 ]      && ok "appends (2 records)"      || ng "append failed"
rm -f "$TMPLOG" "$TMPSTATE"

echo "== agent config =="
python3 -m json.tool "$HERE/banking-secure.agent.json" >/dev/null 2>&1 && ok "banking-secure.agent.json is valid JSON" || ng "agent JSON invalid"
if command -v kiro-cli >/dev/null 2>&1; then
  kiro-cli agent validate --path "$HERE/banking-secure.agent.json" >/dev/null 2>&1 && ok "kiro-cli agent validate passed" || ng "kiro-cli agent validate failed"
else
  echo "  SKIP: kiro-cli not installed (agent schema validation skipped)"
fi

echo
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
