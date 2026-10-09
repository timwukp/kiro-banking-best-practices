#!/usr/bin/env bash
# run-tests.sh - regression tests for the agent-hooks guards and audit logger.
#
# Pure bash + jq. No network, no root, never touches the real $HOME (a temp HOME
# is used). Commands in the fixtures are fed to the guards as JSON text only;
# nothing from the fixtures is executed.
#
#   bash agent-hooks/tests/run-tests.sh
#
# Fixtures (tab-separated) live in agent-hooks/tests/fixtures/:
#   git-fs-cases.tsv : expected_exit  hook  command  [known_gap]
#   pii-cases.tsv    : expected_exit  description  tool_input-JSON
# Expected exit codes are exact: 2 = blocked, 0 = allowed.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOKS="$(cd "$HERE/.." && pwd)"
FIX="$HERE/fixtures"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/kiro-hook-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"; mkdir -p "$HOME"
export KIRO_AUDIT_LOG="$WORK/audit.jsonl"
BASH_BIN="$(command -v bash)"

command -v jq >/dev/null 2>&1 || { echo "run-tests: jq is required"; exit 1; }

PASS=0; FAIL=0; GAP=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $*"; }
expect() { # description expected actual
  if [ "$2" = "$3" ]; then ok; else bad "$1 (expected exit $2, got $3)"; fi
}

run_hook() { # hook-file stdin-text -> prints exit code
  printf '%s' "$2" | "$BASH_BIN" "$HOOKS/$1" >/dev/null 2>&1
  echo $?
}
shell_event() { jq -cn --arg c "$1" '{hook_event_name:"preToolUse",cwd:"/repo",session_id:"test",tool_name:"execute_bash",tool_input:{command:$c}}'; }

# Token- and key-shaped test values are assembled at runtime (never committed).
PEM_BEGIN="-----""BEGIN"
GH_TOKEN="gh""p_$(printf 'a%.0s' $(seq 1 36))"
AWS_EXAMPLE_SECRET="wJalrXUtnFEMI""K7MDENGbPxRfiCY""EXAMPLEKEY"   # AWS documentation example secret key (split for secret scanners)

echo "== git-guard / destructive-fs-guard fixtures"
while IFS=$'\t' read -r expected hook cmd gap; do
  case "$expected" in ''|\#*) continue ;; esac
  if [ "${gap:-}" = "known_gap" ]; then GAP=$((GAP + 1)); continue; fi
  expect "$hook: $cmd" "$expected" "$(run_hook "$hook.sh" "$(shell_event "$cmd")")"
done < "$FIX/git-fs-cases.tsv"

echo "== pii-guard fixtures"
while IFS=$'\t' read -r expected desc json; do
  case "$expected" in ''|\#*) continue ;; esac
  json="${json//__PEM_BEGIN__/$PEM_BEGIN}"
  json="${json//__GH_TOKEN__/$GH_TOKEN}"
  json="${json//__AWS_EXAMPLE_SECRET__/$AWS_EXAMPLE_SECRET}"
  ev="$(jq -cn --argjson ti "$json" '{hook_event_name:"preToolUse",cwd:"/repo",session_id:"test",tool_name:"fs_write",tool_input:$ti}')" \
    || { bad "pii fixture is not valid JSON: $desc"; continue; }
  expect "pii-guard: $desc" "$expected" "$(run_hook pii-guard.sh "$ev")"
done < "$FIX/pii-cases.tsv"

echo "== fail-closed behaviour"
NOJQ="$WORK/nojq"; mkdir -p "$NOJQ"
for t in cat sed awk tr grep dirname mkdir date tail head cut seq shasum sha256sum env; do
  p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$NOJQ/$t"
done
for g in pii-guard.sh git-guard.sh destructive-fs-guard.sh; do
  expect "$g: invalid JSON"  2 "$(run_hook "$g" '{not json')"
  expect "$g: empty stdin"   2 "$(run_hook "$g" '')"
  expect "$g: JSON array"    2 "$(run_hook "$g" '[1,2]')"
  rc="$(shell_event "git status" | PATH="$NOJQ" "$BASH_BIN" "$HOOKS/$g" >/dev/null 2>&1; echo $?)"
  expect "$g: jq missing" 2 "$rc"
done
# A non-shell tool call (no command) is allowed by the shell guards.
nonshell='{"hook_event_name":"preToolUse","tool_name":"fs_read","tool_input":{"path":"README.md"}}'
expect "git-guard: non-shell tool"            0 "$(run_hook git-guard.sh "$nonshell")"
expect "destructive-fs-guard: non-shell tool" 0 "$(run_hook destructive-fs-guard.sh "$nonshell")"

echo "== audit-logger"
: > "$KIRO_AUDIT_LOG"
SECRET_MARKER="S1234567D-audit-marker"
for k in 1 2 3; do
  ev="$(jq -cn --arg m "$SECRET_MARKER" --arg k "$k" '{hook_event_name:"postToolUse",cwd:"/repo",session_id:"test",tool_name:"execute_bash",tool_input:{command:("echo " + $m + " " + $k)},tool_response:{stdout:"ok"}}')"
  expect "audit-logger exit code ($k)" 0 "$(run_hook audit-logger.sh "$ev")"
done
expect "audit-logger: garbage input exit code" 0 "$(run_hook audit-logger.sh 'not json')"
lines="$(wc -l < "$KIRO_AUDIT_LOG" | tr -d ' ')"
expect "audit-logger: one line per call" 4 "$lines"
if jq -e . "$KIRO_AUDIT_LOG" >/dev/null 2>&1 && [ "$(jq -s 'length' "$KIRO_AUDIT_LOG")" = "$lines" ]; then ok; else bad "audit log is not valid JSONL"; fi
if grep -q "$SECRET_MARKER" "$KIRO_AUDIT_LOG"; then bad "audit log contains raw tool input"; else ok; fi
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1; else sha256sum | cut -d' ' -f1; fi; }
prev="GENESIS"; chain_ok=1
while IFS= read -r l; do
  r="$(printf '%s' "$l" | jq -cS 'del(.hash)')"; h="$(printf '%s' "$l" | jq -r .hash)"
  p="$(printf '%s' "$l" | jq -r .prev_hash)"
  [ "$p" = "$prev" ] || chain_ok=0
  [ "$(printf '%s%s' "$prev" "$r" | sha)" = "$h" ] || chain_ok=0
  prev="$h"
done < "$KIRO_AUDIT_LOG"
if [ "$chain_ok" = 1 ]; then ok; else bad "audit hash chain does not verify"; fi

echo "== config files"
for f in "$HOOKS/banking-secure.agent.json" "$HOOKS/hooks/banking-guards.json"; do
  if jq -e . "$f" >/dev/null 2>&1; then ok; else bad "invalid JSON: $f"; fi
done
if jq -e '.toolsSettings == null and (.permissions.rules | length > 0)' "$HOOKS/banking-secure.agent.json" >/dev/null 2>&1; then ok; else bad "agent must use permissions.rules, not toolsSettings"; fi
if [ -f "$HOOKS/SHA256SUMS" ]; then
  if (cd "$HOOKS" && { shasum -a 256 -c SHA256SUMS >/dev/null 2>&1 || sha256sum -c SHA256SUMS >/dev/null 2>&1; }); then ok; else bad "SHA256SUMS does not match the hook scripts"; fi
fi

# Optional: validate the agent with a local Kiro CLI (off by default; no network).
if [ "${KIRO_VALIDATE_AGENT:-0}" = "1" ] && command -v kiro-cli >/dev/null 2>&1; then
  if kiro-cli agent validate --path "$HOOKS/banking-secure.agent.json" >/dev/null 2>&1; then ok; else bad "kiro-cli agent validate failed"; fi
fi

echo
echo "PASS=$PASS FAIL=$FAIL KNOWN_GAP=$GAP"
[ "$FAIL" -eq 0 ]
