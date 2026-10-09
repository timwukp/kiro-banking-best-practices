#!/usr/bin/env bash
# test-lockdown.sh - tests for mdm/lockdown-linux.sh.
#
# DEFAULT MODE (no root, no system changes, safe in CI and on a laptop):
#   DRY-RUN tests. They validate the shipped managed-settings JSON, the hook manifest
#   (agent-hooks/SHA256SUMS) and the planned actions, and check that bad input is refused:
#   effect "allow", malformed JSON, unknown fields, BOM / UTF-16, tampered hooks, unpinned or
#   wrongly pinned manifests, and hook commands outside /opt/kiro/hooks. They also check that a
#   refusal happens before any install is planned (validate-before-apply). HOME is redirected to
#   a temporary directory and the test asserts that nothing was written. Runs on Linux and macOS.
#
# ROOT MODE (opt-in, never run by default):
#   KIRO_MDM_ROOT_TESTS=1 sudo -E bash mdm/tests/test-lockdown.sh
#   Only on a disposable Linux host. Deploys into a temporary --prefix under /var/tmp (never the
#   real /etc or /opt), uses an EXISTING unprivileged account (KIRO_MDM_TEST_USER, default
#   "nobody") with a temporary home, and checks chattr +i / +a, idempotency, drift detection,
#   self-heal and refusal of a poisoned re-apply. It also confirms one documented LIMITATION: the
#   user owns ~/.kiro/audit and can rename it. It creates and deletes no user accounts.
set -u

MDM="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$MDM/.." && pwd)"
SCRIPT="$MDM/lockdown-linux.sh"
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
ng()   { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP + 1)); }
sha()  { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

if [ "${KIRO_MDM_ROOT_TESTS:-0}" = 1 ]; then
  W="$(mktemp -d /var/tmp/kiro-mdm-test.XXXXXX)"
else
  W="$(mktemp -d "${TMPDIR:-/tmp}/kiro-mdm-test.XXXXXX")"
fi
cleanup() {
  if command -v chattr >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
    find "$W" -exec chattr -ia {} + 2>/dev/null
  fi
  rm -rf "$W"
}
trap cleanup EXIT
export HOME="$W/fakehome"; mkdir -p "$HOME"
unset KIRO_MANAGED_SETTINGS_SRC KIRO_HOOKS_SRC KIRO_HOOKS_MANIFEST_SHA256 KIRO_DEPLOY_HOOKS \
      KIRO_INSTALL_USER KIRO_AUDIT_USER KIRO_USER_HOME KIRO_ROOT_PREFIX KIRO_DRY_RUN KIRO_STRICT

# expect <rc> <description> <args...> : run the script, keep its output in $W/out.
expect() {
  local want="$1" desc="$2"; shift 2
  bash "$SCRIPT" "$@" > "$W/out" 2>&1; local rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$desc (rc=$rc)"; else ng "$desc (rc=$rc, expected $want)"; sed 's/^/      | /' "$W/out" | tail -5; fi
}
out_has() { if grep -qF -- "$2" "$W/out"; then ok "$1"; else ng "$1 (missing: $2)"; fi; }
out_lacks() { if grep -qF -- "$2" "$W/out"; then ng "$1 (unexpected: $2)"; else ok "$1"; fi; }

# A self-contained hook fixture built from the repo's hook scripts, so the manifest logic is
# tested even when agent-hooks/SHA256SUMS is being regenerated.
make_fixture() {
  local d="$1" s list=""
  mkdir -p "$d/hooks"
  for s in "$REPO"/agent-hooks/*.sh; do cp "$s" "$d/"; list="$list $(basename "$s")"; done
  ( cd "$d" && for s in $list; do printf '%s  %s\n' "$(sha "$s")" "$s"; done > SHA256SUMS )
  jq -n --argjson s "$(printf '%s\n' $list | jq -R . | jq -s .)" \
    '{name:"banking-secure", hooks:{preToolUse:[$s[] | {matcher:"*", command:("/opt/kiro/hooks/" + .)}]}}' > "$d/banking-secure.agent.json"
  jq -n --argjson s "$(printf '%s\n' $list | jq -R . | jq -s .)" \
    '{version:"v1", hooks:[$s[] | {name:., trigger:"PreToolUse", matcher:"*", action:{type:"command", command:("/opt/kiro/hooks/" + .)}}]}' > "$d/hooks/banking-guards.json"
}

BANK="$REPO/managed-settings/managed-settings.banking.json"
OPTB="$REPO/managed-settings/managed-settings.option-b.json"
FX="$W/fixture"; make_fixture "$FX"
ME="$(id -un)"

echo "== DRY RUN: shipped managed-settings =="
if [ -f "$BANK" ]; then
  expect 0 "Option A policy validates (dry run)" --dry-run
  out_has "plans the official Linux path" "/etc/kiro/managed-settings.json"
  out_has "reports no allow effects" "no allow effects"
  expect 2 "--strict refuses the shipped placeholders (d-xxxxxxxxxx, example.com)" --dry-run --strict
  jq '.settings = {idc_start_url:"https://d-1234567890.awsapps.com/start", idc_region:"ap-southeast-1", signin_help_url:"https://it.bank.test/kiro"}' "$BANK" > "$W/real.json"
  expect 0 "--strict accepts the same policy with real values" --dry-run --strict --settings "$W/real.json"
else
  skip "managed-settings/managed-settings.banking.json not present"
fi
if [ -f "$OPTB" ]; then expect 0 "Option B policy validates (dry run)" --dry-run --option-b; else skip "Option B file not present"; fi

echo "== DRY RUN: invalid policies are refused =="
neg() { # neg <description> <file contents>
  printf '%s' "$2" > "$W/bad.json"
  expect 2 "$1" --dry-run --settings "$W/bad.json"
}
neg 'effect "allow" refused'            '{"rules":[{"capability":"shell","match":["git *"],"effect":"allow"}]}'
out_has "allow refusal explains why" 'effect "allow" is not permitted'
neg 'malformed JSON refused'            '{"rules":[{"capability":"shell","effect":"deny"},]}'
neg 'missing "rules" refused'           '{"settings":{"idc_region":"us-east-1"}}'
neg 'unknown top-level field refused'   '{"rules":[],"comment":"x"}'
neg 'unknown rule field refused'        '{"rules":[{"capability":"shell","match":["sudo *"],"effect":"deny","note":"x"}]}'
neg 'missing effect refused'            '{"rules":[{"capability":"shell","match":["sudo *"]}]}'
neg 'non-array match refused'           '{"rules":[{"capability":"shell","match":"sudo *","effect":"deny"}]}'
neg 'http signin_help_url refused'      '{"rules":[],"settings":{"signin_help_url":"http://it.bank.test/help"}}'
neg 'more than 16 sign-in entries refused' '{"rules":[{"capability":"signin_method","match":["*","idc","idc","idc","idc","idc","idc","idc","idc","idc","idc","idc","idc","idc","idc","idc"],"exclude":["idc"],"effect":"deny"}]}'
printf '\357\273\277{"rules":[]}' > "$W/bom.json"
expect 2 "UTF-8 BOM refused" --dry-run --settings "$W/bom.json"
printf '\377\376{\000}\000' > "$W/utf16.json"
expect 2 "UTF-16 refused" --dry-run --settings "$W/utf16.json"
printf '%s' '{"rules":[{"capability":"web_fetch","effect":"deny"},{"capability":"future_cap","effect":"deny"}]}' > "$W/fwd.json"
expect 0 "unknown capability is a warning only (Kiro skips it)" --dry-run --settings "$W/fwd.json"

echo "== DRY RUN: hook manifest and user files =="
expect 0 "fixture hooks verify against SHA256SUMS" --dry-run --hooks --hooks-src "$FX"
out_has "plans /opt/kiro/hooks" "/opt/kiro/hooks/"
out_has "hash check ran" "hook hashes verified"
PIN="$(sha "$FX/SHA256SUMS")"
expect 0 "correct manifest pin accepted" --dry-run --hooks --hooks-src "$FX" --manifest-sha256 "$PIN"
expect 2 "wrong manifest pin refused" --dry-run --hooks --hooks-src "$FX" --manifest-sha256 "$(printf '0%.0s' $(seq 1 64))"
cp -R "$FX" "$W/tampered"; printf '\nexit 0\n' >> "$W/tampered/$(head -1 "$FX/SHA256SUMS" | awk '{print $2}')"
expect 2 "tampered hook script refused" --dry-run --hooks --hooks-src "$W/tampered"
out_has "tamper refusal says nothing was deployed" "nothing deployed"
out_lacks "validate-before-apply: no install planned when the hooks fail verification" "would install"
cp -R "$FX" "$W/unsafe"; printf '%s  ../evil.sh\n' "$(printf 'a%.0s' $(seq 1 64))" >> "$W/unsafe/SHA256SUMS"
expect 2 "path traversal in SHA256SUMS refused" --dry-run --hooks --hooks-src "$W/unsafe"
cp -R "$FX" "$W/malformed"; echo "not a checksum line" >> "$W/malformed/SHA256SUMS"
expect 2 "malformed SHA256SUMS line refused" --dry-run --hooks --hooks-src "$W/malformed"
mkdir -p "$W/nomanifest"; cp "$FX"/*.sh "$W/nomanifest/"
expect 2 "hooks without SHA256SUMS refused" --dry-run --hooks --hooks-src "$W/nomanifest"
expect 0 "user install planned (v1 hook file + agent + audit log)" --dry-run --hooks-src "$FX" --install-user "$ME" --user-home "$HOME"
out_has "plans ~/.kiro/hooks/banking-guards.json" ".kiro/hooks/banking-guards.json"
out_has "plans ~/.kiro/agents/banking-secure.json" ".kiro/agents/banking-secure.json"
out_has "states the user files are not tamper-resistant" "not tamper-resistant"
out_has "plans chattr +a on the audit log" "chattr +a"
cp -R "$FX" "$W/evilagent"; jq '.hooks.preToolUse[0].command = "/tmp/evil.sh"' "$FX/banking-secure.agent.json" > "$W/evilagent/banking-secure.agent.json"
expect 2 "agent hook command outside /opt/kiro/hooks refused" --dry-run --hooks-src "$W/evilagent" --install-user "$ME" --user-home "$HOME"
cp -R "$FX" "$W/unpinned"; jq '.hooks[0].action.command = "/opt/kiro/hooks/not-in-manifest.sh"' "$FX/hooks/banking-guards.json" > "$W/unpinned/hooks/banking-guards.json"
expect 2 "v1 hook command for a script not in SHA256SUMS refused" --dry-run --hooks-src "$W/unpinned" --install-user "$ME" --user-home "$HOME"
out_lacks "validate-before-apply: no install planned when a user hook file is refused" "would install"
cp -R "$FX" "$W/interp"; jq '.hooks[0].action.command = ("bash " + .hooks[0].action.command)' "$FX/hooks/banking-guards.json" > "$W/interp/hooks/banking-guards.json"
expect 0 "hook command run through bash (bash /opt/kiro/hooks/x.sh) accepted" --dry-run --hooks-src "$W/interp" --install-user "$ME" --user-home "$HOME"

echo "== DRY RUN: shipped agent-hooks (if present) =="
if [ -f "$REPO/agent-hooks/SHA256SUMS" ]; then
  expect 0 "shipped agent-hooks/SHA256SUMS verifies" --dry-run --hooks
  if [ -f "$REPO/agent-hooks/hooks/banking-guards.json" ] && [ -f "$REPO/agent-hooks/banking-secure.agent.json" ]; then
    expect 0 "shipped v1 hook file and agent reference only hash-pinned /opt/kiro/hooks scripts" \
      --dry-run --install-user "$ME" --user-home "$HOME"
  else
    skip "agent-hooks/hooks/banking-guards.json or banking-secure.agent.json not present"
  fi
else
  skip "agent-hooks/SHA256SUMS not present (shipped-manifest checks skipped)"
fi

echo "== DRY RUN makes no changes =="
expect 0 "dry run with a test prefix" --dry-run --prefix "$W/root" --hooks-src "$FX" --install-user "$ME" --user-home "$HOME"
[ ! -e "$W/root" ] && ok "nothing created under the prefix" || ng "dry run created $W/root"
[ -z "$(ls -A "$HOME")" ] && ok "nothing written to HOME" || ng "dry run wrote to HOME: $(ls -A "$HOME")"
if [ "$(id -u)" -ne 0 ]; then
  expect 1 "real run without root is refused" --prefix "$W/root"
fi
expect 3 "--check reports drift when nothing is deployed" --check --prefix "$W/root"

# -------------------------------------------------------------------------------------------
if [ "${KIRO_MDM_ROOT_TESTS:-0}" != 1 ]; then
  echo
  echo "(root tests not run: set KIRO_MDM_ROOT_TESTS=1 and run as root on a disposable Linux host)"
  echo "RESULT: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
  [ "$FAIL" -eq 0 ]; exit
fi

echo "== ROOT: real deployment into a temporary prefix =="
[ "$(id -u)" -eq 0 ] || { echo "ROOT tests need root"; exit 1; }
[ "$(uname -s)" = Linux ] || { echo "ROOT tests are Linux only"; exit 1; }
TU="${KIRO_MDM_TEST_USER:-nobody}"
id "$TU" >/dev/null 2>&1 || { echo "test user $TU does not exist (this test never creates users)"; exit 1; }
[ "$(id -u "$TU")" -ne 0 ] || { echo "test user must not be root"; exit 1; }
chmod 0755 "$W"                                   # let the test user traverse the work dir
TH="$W/home-$TU"; mkdir -p "$TH"; chown "$TU" "$TH"; chmod 0700 "$TH"
asu() { runuser -u "$TU" -- "$@"; }
P="$W/root"
ARGS="--prefix $P --hooks-src $FX --install-user $TU --user-home $TH"
# shellcheck disable=SC2086
expect 0 "deploy as root" $ARGS
S="$P/etc/kiro/managed-settings.json"; H="$P/opt/kiro/hooks/$(head -1 "$FX/SHA256SUMS" | awk '{print $2}')"
A="$TH/.kiro/audit/kiro-hooks.jsonl"
[ "$(stat -c '%U %a' "$S")" = "root 644" ] && ok "managed-settings is root 0644" || ng "managed-settings owner/mode: $(stat -c '%U %a' "$S")"
[ "$(stat -c '%U %a' "$H")" = "root 755" ] && ok "hook is root 0755" || ng "hook owner/mode: $(stat -c '%U %a' "$H")"
if lsattr -d "$S" 2>/dev/null | awk '{print $1}' | grep -q i; then
  ok "managed-settings has chattr +i"
  ( echo x >> "$S" ) 2>/dev/null && ng "root could append to an immutable file" || ok "immutable: even root cannot modify until chattr -i"
  rm -f "$S" 2>/dev/null && ng "immutable file was deleted" || ok "immutable: cannot be deleted"
else
  skip "filesystem under /var/tmp does not support chattr +i (immutability not tested)"
  ARGS="$ARGS --no-immutable"
fi
asu sh -c "echo x >> '$S'" 2>/dev/null && ng "$TU could modify managed-settings" || ok "$TU cannot modify managed-settings"
asu sh -c "echo x >> '$H'" 2>/dev/null && ng "$TU could modify a hook" || ok "$TU cannot modify a hook"
[ "$(stat -c '%U' "$TH/.kiro/hooks/banking-guards.json")" = "$TU" ] && ok "v1 hook file installed, owned by $TU (user-owned by design)" || ng "v1 hook file missing or wrong owner"
asu sh -c "echo '{\"e\":1}' >> '$A'" && ok "$TU can append to the audit log" || ng "$TU cannot append to the audit log"
if lsattr -d "$A" 2>/dev/null | awk '{print $1}' | grep -q a; then
  asu sh -c ": > '$A'" 2>/dev/null && ng "$TU truncated the append-only log" || ok "$TU cannot truncate the audit log"
  asu rm -f "$A" 2>/dev/null; [ -e "$A" ] && ok "$TU cannot delete the audit log" || ng "$TU deleted the audit log"
  asu chattr -a "$A" 2>/dev/null && ng "$TU cleared +a" || ok "$TU cannot clear +a (needs CAP_LINUX_IMMUTABLE)"
  if asu mv "$TH/.kiro/audit" "$TH/.kiro/audit.moved" 2>/dev/null; then
    ok "LIMITATION confirmed: $TU owns ~/.kiro/audit and can rename it (the log is supplementary evidence)"
    asu mv "$TH/.kiro/audit.moved" "$TH/.kiro/audit"
  else
    skip "could not rename ~/.kiro/audit as $TU (limitation not demonstrated)"
  fi
else
  skip "chattr +a not supported here (append-only not tested)"
fi

echo "== ROOT: idempotency, drift and self-heal =="
before="$(sha "$S")"
# shellcheck disable=SC2086
expect 0 "second run" $ARGS
out_has "second run leaves managed-settings unchanged" "unchanged: $S"
# shellcheck disable=SC2086
expect 0 "--check is clean after deployment" --check $ARGS
chattr -i "$S" 2>/dev/null; echo ' ' >> "$S"
# shellcheck disable=SC2086
expect 3 "--check detects a modified managed-settings" --check $ARGS
# shellcheck disable=SC2086
expect 0 "re-run restores it" $ARGS
[ "$(sha "$S")" = "$before" ] && ok "self-heal restored the original content" || ng "content not restored"
hbefore="$(sha "$H")"
cp -R "$FX" "$W/poison"; printf '\nexit 0\n' >> "$W/poison/$(basename "$H")"
expect 2 "re-apply from a poisoned source is refused" --prefix "$P" --hooks-src "$W/poison" --hooks
[ "$(sha "$H")" = "$hbefore" ] && ok "deployed hook untouched after the refused re-apply" || ng "deployed hook changed"
P2="$W/root2"
expect 2 "first deployment from a poisoned source is refused" --prefix "$P2" --hooks-src "$W/poison" --hooks
[ ! -e "$P2/etc/kiro/managed-settings.json" ] && ok "validate-before-apply: nothing deployed" || ng "managed-settings deployed despite the refusal"

echo
echo "RESULT: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
