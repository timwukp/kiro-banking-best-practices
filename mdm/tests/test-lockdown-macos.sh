#!/usr/bin/env bash
# test-lockdown-macos.sh - tests for mdm/lockdown-macos.sh.
#
# DEFAULT MODE (no root, no system changes, safe in CI; runs on macOS and Linux):
#   DRY-RUN tests: policy validation, hook manifest verification, validate-before-apply ordering,
#   and the rewrite of the shipped /opt/kiro/hooks commands to "/Library/Application Support/Kiro/
#   hooks" (written only to a temp directory via --rewrite-out). HOME is redirected and the test
#   asserts nothing was written.
#   On macOS it also runs an HONESTY CHECK on the USER flags (uappnd, uchg) that the audit-log step
#   uses by default: while set they block truncation and writes, but the file OWNER can clear them.
#   This test does NOT claim any protection against the owner of a file when a user flag is used.
#
# ROOT MODE (opt-in, never run by default):
#   sudo KIRO_MDM_ROOT_TESTS=1 bash mdm/tests/test-lockdown-macos.sh
#   Only on a disposable or test Mac. Deploys into a temporary --prefix under /private/var/tmp,
#   uses an EXISTING unprivileged account (KIRO_MDM_TEST_USER, default "nobody"), checks root:wheel
#   ownership and, only when kern.securelevel is 0 (so the test can clean up), schg on the policy
#   and sappnd (--audit-sappnd) on the audit log. It creates and deletes no user accounts.
set -u

MDM="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$MDM/.." && pwd)"
SCRIPT="$MDM/lockdown-macos.sh"
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  PASS: $1"; PASS=$((PASS + 1)); }
ng()   { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  SKIP: $1"; SKIP=$((SKIP + 1)); }
sha()  { if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'; else sha256sum "$1" | awk '{print $1}'; fi; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

if [ "${KIRO_MDM_ROOT_TESTS:-0}" = 1 ]; then W="$(mktemp -d /private/var/tmp/kiro-mac-test.XXXXXX)"
else W="$(mktemp -d "${TMPDIR:-/tmp}/kiro-mac-test.XXXXXX")"; fi
cleanup() {
  [ "$(uname -s)" = Darwin ] && chflags -R noschg,nosappnd,nouchg,nouappnd "$W" 2>/dev/null
  rm -rf "$W" 2>/dev/null || echo "NOTE: could not remove $W (schg at kern.securelevel>0 needs Recovery mode)"
}
trap cleanup EXIT
export HOME="$W/fakehome"; mkdir -p "$HOME"
unset KIRO_MANAGED_SETTINGS_SRC KIRO_HOOKS_SRC KIRO_HOOKS_DEST KIRO_HOOKS_MANIFEST_SHA256 KIRO_DEPLOY_HOOKS \
      KIRO_INSTALL_USER KIRO_AUDIT_USER KIRO_USER_HOME KIRO_ROOT_PREFIX KIRO_DRY_RUN KIRO_STRICT KIRO_AUDIT_FLAG

expect() {
  local want="$1" desc="$2"; shift 2
  bash "$SCRIPT" "$@" > "$W/out" 2>&1; local rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$desc (rc=$rc)"; else ng "$desc (rc=$rc, expected $want)"; sed 's/^/      | /' "$W/out" | tail -5; fi
}
out_has() { if grep -qF -- "$2" "$W/out"; then ok "$1"; else ng "$1 (missing: $2)"; fi; }
out_lacks() { if grep -qF -- "$2" "$W/out"; then ng "$1 (unexpected: $2)"; else ok "$1"; fi; }

make_fixture() {
  local d="$1" s list=""
  mkdir -p "$d/hooks"
  for s in "$REPO"/agent-hooks/*.sh; do cp "$s" "$d/"; list="$list $(basename "$s")"; done
  ( cd "$d" && for s in $list; do printf '%s  %s\n' "$(sha "$s")" "$s"; done > SHA256SUMS )
  jq -n --argjson s "$(printf '%s\n' $list | jq -R . | jq -s .)" \
    '{name:"banking-secure", mcpServers:{x:{command:"npx"}}, hooks:{preToolUse:[$s[] | {matcher:"*", command:("/opt/kiro/hooks/" + .)}]}}' > "$d/banking-secure.agent.json"
  jq -n --argjson s "$(printf '%s\n' $list | jq -R . | jq -s .)" \
    '{version:"v1", hooks:[$s[] | {name:., trigger:"PreToolUse", matcher:"*", action:{type:"command", command:("/opt/kiro/hooks/" + .)}}]}' > "$d/hooks/banking-guards.json"
}
FX="$W/fixture"; make_fixture "$FX"
ME="$(id -un)"
MACDIR="/Library/Application Support/Kiro/hooks"

echo "== DRY RUN: policy validation =="
if [ -f "$REPO/managed-settings/managed-settings.banking.json" ]; then
  expect 0 "Option A policy validates" --dry-run
  out_has "plans the official macOS path" "/Library/Application Support/Kiro/managed-settings.json"
  expect 0 "Option B policy validates" --dry-run --option-b
else
  skip "managed-settings/managed-settings.banking.json not present"
fi
printf '%s' '{"rules":[{"capability":"shell","match":["*"],"effect":"allow"}]}' > "$W/allow.json"
expect 2 'effect "allow" refused' --dry-run --settings "$W/allow.json"
printf '%s' '{"rules":[' > "$W/broken.json"
expect 2 "malformed JSON refused" --dry-run --settings "$W/broken.json"
printf '\357\273\277{"rules":[]}' > "$W/bom.json"
expect 2 "UTF-8 BOM refused" --dry-run --settings "$W/bom.json"

echo "== DRY RUN: hashes and hook-path rewrite =="
expect 0 "fixture hooks verify" --dry-run --hooks --hooks-src "$FX"
out_has "plans the macOS hook directory" "$MACDIR/"
cp -R "$FX" "$W/tampered"; printf '\nexit 0\n' >> "$W/tampered/$(head -1 "$FX/SHA256SUMS" | awk '{print $2}')"
expect 2 "tampered hook refused" --dry-run --hooks --hooks-src "$W/tampered"
out_lacks "validate-before-apply: no install planned when the hooks fail verification" "would install"
expect 0 "user files rewritten (preview only)" --dry-run --hooks-src "$FX" --install-user "$ME" --user-home "$HOME" --rewrite-out "$W/rw"
for f in banking-guards.json banking-secure.agent.json; do
  cmds="$(jq -r '(.hooks // empty) | .. | objects | select(has("command")) | .command | strings' "$W/rw/$f" 2>/dev/null)"
  [ -n "$cmds" ] || { ng "$f: no rewritten output"; continue; }
  printf '%s\n' "$cmds" | grep -q '/opt/kiro/hooks' && ng "$f still references /opt/kiro/hooks" || ok "$f no longer references /opt/kiro/hooks"
  printf '%s\n' "$cmds" | grep -vqF "\"$MACDIR/" && ng "$f has a hook command not quoted under $MACDIR" || ok "$f hook commands are quoted under $MACDIR"
done
jq -e '.mcpServers.x.command == "npx"' "$W/rw/banking-secure.agent.json" >/dev/null && ok "non-hook commands (mcpServers) are not rewritten" || ng "mcpServers command was changed"
expect 0 "--hooks-dest /opt/kiro/hooks needs no quoting" --dry-run --hooks-src "$FX" --hooks-dest /opt/kiro/hooks --install-user "$ME" --user-home "$HOME" --rewrite-out "$W/rw2"
jq -r '.hooks[].action.command' "$W/rw2/banking-guards.json" | grep -q '^/opt/kiro/hooks/[^"]*$' && ok "unquoted /opt/kiro/hooks commands kept" || ng "unexpected /opt rewrite"
out_has "plans uappnd (default) for the audit log" "chflags uappnd"
out_has "states that the owner can clear uappnd" "not protection against"
expect 0 "--audit-sappnd planned" --dry-run --hooks-src "$FX" --install-user "$ME" --user-home "$HOME" --audit-sappnd
out_has "plans sappnd (super-user append-only) for the audit log" "chflags sappnd"
cp -R "$FX" "$W/interp"
jq '.hooks[0].action.command = ("bash " + .hooks[0].action.command)' "$FX/hooks/banking-guards.json" > "$W/interp/hooks/banking-guards.json"
expect 0 "hook command run through bash is accepted and rewritten" --dry-run --hooks-src "$W/interp" --install-user "$ME" --user-home "$HOME" --rewrite-out "$W/rw4"
jq -r '.hooks[0].action.command' "$W/rw4/banking-guards.json" 2>/dev/null | grep -q "^bash \"$MACDIR/" && ok "interpreter prefix kept, path quoted" || ng "interpreter-prefixed command not rewritten as expected"
cp -R "$FX" "$W/evil"; jq '.hooks[0].action.command = "/tmp/evil.sh"' "$FX/hooks/banking-guards.json" > "$W/evil/hooks/banking-guards.json"
expect 2 "hook command outside /opt/kiro/hooks refused" --dry-run --hooks-src "$W/evil" --install-user "$ME" --user-home "$HOME"
if [ -f "$REPO/agent-hooks/SHA256SUMS" ] && [ -f "$REPO/agent-hooks/hooks/banking-guards.json" ]; then
  expect 0 "shipped agent-hooks verify and rewrite" --dry-run --install-user "$ME" --user-home "$HOME" --rewrite-out "$W/rw3"
else
  skip "shipped agent-hooks/SHA256SUMS or hooks/banking-guards.json not present"
fi
[ -z "$(ls -A "$HOME")" ] && ok "dry run wrote nothing to HOME" || ng "dry run wrote to HOME"
if [ "$(id -u)" -ne 0 ]; then expect 1 "real run without root is refused" --prefix "$W/root"; fi
[ ! -e "$W/root" ] && ok "nothing created under the prefix" || ng "prefix was created"

echo "== HONESTY CHECK: user flags (uappnd, uchg) do not protect against the owner =="
if [ "$(uname -s)" = Darwin ]; then
  f="$W/uappnd-demo"; echo '{"seed":1}' > "$f"
  if chflags uappnd "$f" 2>/dev/null; then
    ( echo '{"e":2}' >> "$f" ) 2>/dev/null && ok "uappnd allows appends" || ng "uappnd blocked an append"
    ( : > "$f" ) 2>/dev/null && ng "uappnd file was truncated while the flag was set" || ok "uappnd blocks truncation while it is set"
    rm -f "$f" 2>/dev/null; [ -e "$f" ] && ok "uappnd blocks deletion while it is set" || ng "uappnd file was deleted"
    if chflags nouappnd "$f" 2>/dev/null && ( : > "$f" ) 2>/dev/null; then
      ok "LIMITATION confirmed: the OWNER can clear uappnd and truncate the log (no protection against the developer)"
    else
      ng "owner could not clear uappnd (unexpected on macOS)"
    fi
  else
    skip "chflags uappnd not supported in this directory"
  fi
  f="$W/uchg-demo"; echo data > "$f"
  if chflags uchg "$f" 2>/dev/null; then
    ( echo x >> "$f" ) 2>/dev/null && ng "uchg file was writable" || ok "uchg blocks writes while it is set"
    if chflags nouchg "$f" 2>/dev/null && ( echo x >> "$f" ) 2>/dev/null; then
      ok "LIMITATION confirmed: the OWNER can clear uchg (the scripts protect root-owned files with schg, not uchg)"
    else
      ng "owner could not clear uchg (unexpected on macOS)"
    fi
  else
    skip "chflags uchg not supported in this directory"
  fi
else
  skip "honesty check is macOS only"
fi

if [ "${KIRO_MDM_ROOT_TESTS:-0}" != 1 ]; then
  echo
  echo "(root tests not run: set KIRO_MDM_ROOT_TESTS=1 and run with sudo on a disposable Mac)"
  echo "RESULT: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
  [ "$FAIL" -eq 0 ]; exit
fi

echo "== ROOT: real deployment into a temporary prefix =="
[ "$(uname -s)" = Darwin ] || { echo "ROOT tests are macOS only"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "ROOT tests need root"; exit 1; }
TU="${KIRO_MDM_TEST_USER:-nobody}"
id "$TU" >/dev/null 2>&1 || { echo "test user $TU does not exist (this test never creates users)"; exit 1; }
chmod 0755 "$W"
TH="$W/home-$TU"; mkdir -p "$TH"; chown "$TU" "$TH"; chmod 0700 "$TH"
asu() { sudo -n -u "$TU" -- "$@"; }
SL="$(sysctl -n kern.securelevel 2>/dev/null || echo unknown)"
IMM=""; [ "$SL" = 0 ] || { IMM="--no-system-immutable"; skip "kern.securelevel=$SL: schg/sappnd not set by this test (could not be cleaned up without Recovery)"; }
P="$W/root"
ARGS="--prefix $P --hooks-src $FX --install-user $TU --user-home $TH $IMM"
# shellcheck disable=SC2086
expect 0 "deploy as root" $ARGS
S="$P/Library/Application Support/Kiro/managed-settings.json"
H="$P$MACDIR/$(head -1 "$FX/SHA256SUMS" | awk '{print $2}')"
A="$TH/.kiro/audit/kiro-hooks.jsonl"
[ "$(stat -f '%Su:%Sg %Lp' "$S")" = "root:wheel 644" ] && ok "managed-settings is root:wheel 0644" || ng "managed-settings: $(stat -f '%Su:%Sg %Lp' "$S")"
[ "$(stat -f '%Su %Lp' "$H")" = "root 755" ] && ok "hook is root 0755" || ng "hook: $(stat -f '%Su %Lp' "$H")"
asu sh -c "echo x >> '$S'" 2>/dev/null && ng "$TU could modify managed-settings" || ok "$TU cannot modify managed-settings"
if [ -z "$IMM" ]; then
  stat -f '%Sf' "$S" | grep -q schg && ok "managed-settings has schg" || ng "schg missing"
  ( echo x >> "$S" ) 2>/dev/null && ng "root could modify an schg file" || ok "schg: root cannot modify without clearing the flag"
  # Default audit flag: uappnd (user flag). Check what it does and, honestly, what it does not do.
  asu sh -c "echo '{\"e\":1}' >> '$A'" && ok "$TU can append to the uappnd audit log" || ng "$TU cannot append"
  asu sh -c ": > '$A'" 2>/dev/null && ng "$TU truncated the log while uappnd was set" || ok "uappnd blocks truncation while set"
  if asu chflags nouappnd "$A" 2>/dev/null; then
    ok "LIMITATION confirmed: $TU (the owner) can clear uappnd - not protection against the developer"
  else
    ng "$TU could not clear uappnd (unexpected)"
  fi
  # Opt-in super-user flag: sappnd.
  # shellcheck disable=SC2086
  expect 0 "re-run with --audit-sappnd" $ARGS --audit-sappnd
  stat -f '%Sf' "$A" | grep -q sappnd && ok "audit log has sappnd" || ng "sappnd missing"
  asu sh -c "echo '{\"e\":2}' >> '$A'" && ok "$TU can append to the sappnd audit log" || ng "$TU cannot append"
  asu sh -c ": > '$A'" 2>/dev/null && ng "$TU truncated the sappnd log" || ok "$TU cannot truncate the sappnd log"
  asu rm -f "$A" 2>/dev/null; [ -e "$A" ] && ok "$TU cannot delete the sappnd log" || ng "$TU deleted the sappnd log"
  asu chflags nosappnd "$A" 2>/dev/null && ng "$TU cleared sappnd" || ok "$TU cannot clear sappnd (super-user flag)"
  ARGS="$ARGS --audit-sappnd"
fi
before="$(sha "$S")"
# shellcheck disable=SC2086
expect 0 "second run is idempotent" $ARGS
out_has "managed-settings unchanged on re-run" "unchanged: $S"
# shellcheck disable=SC2086
expect 0 "--check is clean" --check $ARGS
cp -R "$FX" "$W/poison"; printf '\nexit 0\n' >> "$W/poison/$(basename "$H")"
hbefore="$(sha "$H")"
expect 2 "re-apply from a poisoned source refused" --prefix "$P" --hooks-src "$W/poison" --hooks $IMM
[ "$(sha "$H")" = "$hbefore" ] && ok "deployed hook untouched" || ng "deployed hook changed"
[ "$(sha "$S")" = "$before" ] && ok "managed-settings untouched" || ng "managed-settings changed"
P2="$W/root2"
expect 2 "first deployment from a poisoned source refused" --prefix "$P2" --hooks-src "$W/poison" --hooks $IMM
[ ! -e "$P2/Library/Application Support/Kiro/managed-settings.json" ] && ok "validate-before-apply: nothing deployed" || ng "managed-settings was deployed despite the refusal"

echo
echo "RESULT: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
