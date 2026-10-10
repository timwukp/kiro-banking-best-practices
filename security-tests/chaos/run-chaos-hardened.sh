#!/usr/bin/env bash
# run-chaos-hardened.sh - Round 2: re-test the round-1 GAPs and the PR3 controls with the SHIPPED
# components: agent-hooks/*.sh (exactly as committed), managed-settings/managed-settings.banking.json
# and mdm/lockdown-linux.sh. Nothing in this round is simulated by a stand-in script.
#
# SCOPE: exercises HOOK-LEVEL and OS-LEVEL controls only. It does NOT drive a real Kiro client, so
# it does not show whether Kiro evaluates the managed-settings rules (deny/ask). For the policy file
# it tests what can be tested without Kiro: the MDM validator refuses bad policies, the deployed
# file is protected from the developer, and drift is detected. Verify rule evaluation on a pilot
# machine (managed-settings/README.md, "Validation").
#
# Two OS hardening measures are configured BY THIS HARNESS to show what they add; the repo does not
# ship them: a noexec tmpfs home (application-control stand-in for AppLocker/WDAC/fapolicyd/Santa)
# and a root-only 0600 sensitive file (least-privilege data access).
#
# MODES
#   --hooks-only   No root, no system changes, safe on a laptop or in CI: the hook series (H) and the
#                  MDM validator series (M1-M3, dry-run) against the files in the repo.
#   (default)      Full run. Requires ALL of: Linux, root, a THROWAWAY VM, CHAOS_ALLOW_SYSTEM_CHANGES=1.
#                  Creates a new account (CHAOS_USER, default "kirochaos"; aborts if it exists), mounts
#                  a tmpfs under /var/tmp, deploys into a temporary --prefix (never /etc or /opt), and
#                  removes the mount, the account it created and the sandbox on exit.
#
#   sudo CHAOS_ALLOW_SYSTEM_CHANGES=1 bash security-tests/chaos/run-chaos-hardened.sh   # throwaway VM only
#   bash security-tests/chaos/run-chaos-hardened.sh --hooks-only                        # anywhere
set -u
. "$(cd "$(dirname "$0")" && pwd)/chaos-lib.sh"

case "${1:-}" in
  --hooks-only) HOOKS_ONLY=1 ;;
  "") ;;
  -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
  *) cdie "unknown option: $1 (use --hooks-only or no option)" ;;
esac
command -v jq >/dev/null 2>&1 || cdie "jq is required (the hooks need it too)"
for h in $CHAOS_GUARDS audit-logger.sh; do [ -f "$CHAOS_HOOKS_SRC/$h" ] || cdie "shipped hook not found: agent-hooks/$h"; done
[ -f "$CHAOS_POLICY" ] || cdie "shipped policy not found: managed-settings/managed-settings.banking.json"
[ "$HOOKS_ONLY" = 1 ] || chaos_require_system_mode

chaos_banner "ROUND 2 - shipped controls ($( [ "$HOOKS_ONLY" = 1 ] && echo 'hooks-only' || echo 'full' ) run)"
chaos_sandbox kiro-chaos2

# --- M. Shipped policy and the MDM validator (dry-run: no root, no changes) ----------------------
echo "=== M. managed-settings.json through the shipped MDM job ==="
mdm_dry() { LAST_CMD="lockdown-linux.sh --dry-run $*"; bash "$CHAOS_MDM" --dry-run "$@" >/dev/null 2>&1; rc=$?; }
mdm_dry; sanity "shipped managed-settings.banking.json passes the MDM validator (rc=$rc)" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
jq '.rules += [{"capability":"shell","match":["*"],"effect":"allow"}]' "$CHAOS_POLICY" > "$S/allow.json"
mdm_dry --settings "$S/allow.json"; judge M1 mdm "deploy a policy with an \"allow\" rule (Kiro would reject the whole file)" BLOCKED "$([ "$rc" = 2 ] && echo 1 || echo 0)" "rc=$rc"
head -c 200 "$CHAOS_POLICY" > "$S/truncated.json"
mdm_dry --settings "$S/truncated.json"; judge M2 mdm "deploy a truncated (malformed) policy" BLOCKED "$([ "$rc" = 2 ] && echo 1 || echo 0)" "rc=$rc"
jq '.rules[0].effct = .rules[0].effect' "$CHAOS_POLICY" > "$S/unknown.json"
mdm_dry --settings "$S/unknown.json"; judge M3 mdm "deploy a policy with an unknown field" BLOCKED "$([ "$rc" = 2 ] && echo 1 || echo 0)" "rc=$rc"
if [ -f "$CHAOS_HOOKS_SRC/SHA256SUMS" ]; then
  mkdir -p "$S/poison"; cp -R "$CHAOS_HOOKS_SRC/." "$S/poison/"; printf '\nexit 0\n' >> "$S/poison/git-guard.sh"
  mdm_dry --hooks --hooks-src "$S/poison"; judge M4 mdm "deploy hooks from a tampered source (SHA256SUMS mismatch)" BLOCKED "$([ "$rc" = 2 ] && echo 1 || echo 0)" "rc=$rc"
else
  echo "  (M4 skipped: agent-hooks/SHA256SUMS not present)"
fi

if [ "$HOOKS_ONLY" = 0 ]; then
  echo
  echo "=== SETUP (as root): shipped policy + hooks via mdm/lockdown-linux.sh, OS hardening ==="
  [ -f "$CHAOS_HOOKS_SRC/SHA256SUMS" ] || cdie "agent-hooks/SHA256SUMS not found; the shipped hooks are only deployed after hash verification"
  chaos_create_user
  mount -t tmpfs -o noexec,nosuid,nodev,size=64m,mode=0700 tmpfs "$UHOME" || cdie "cannot mount a noexec tmpfs on $UHOME"
  MOUNTS="$UHOME"; chown "$CHAOS_USER": "$UHOME"
  P="$S/root"
  MDMARGS="--prefix $P --hooks --install-user $CHAOS_USER --user-home $UHOME"
  MDMCHECK="--prefix $P --hooks"     # policy + hooks only: tmpfs may not support chattr +a on the log
  # shellcheck disable=SC2086
  bash "$CHAOS_MDM" $MDMARGS || cdie "mdm/lockdown-linux.sh refused or failed; nothing to test"
  POLICY="$P/etc/kiro/managed-settings.json"; HOOKD="$P/opt/kiro/hooks"
  AUDIT="$UHOME/.kiro/audit/kiro-hooks.jsonl"
  CANARY="$S/canary.txt"
  echo "card 4111 1111 1111 1111 NRIC S1234567D" > "$CANARY"; chown root:root "$CANARY"; chmod 0600 "$CANARY"

  echo
  echo "=== M (continued). Deployed policy vs the developer ==="
  dev "echo '{\"rules\":[]}' > '$POLICY'" >/dev/null; judge M5 human "overwrite the deployed policy" BLOCKED "$([ "$RC" -ne 0 ] && echo 1 || echo 0)" "rc=$RC"
  dev "rm -f '$POLICY'" >/dev/null; judge M6 human "delete the deployed policy" BLOCKED "$([ -f "$POLICY" ] && echo 1 || echo 0)" "exists=$([ -f "$POLICY" ] && echo yes || echo no)"
  dev "chattr -i '$POLICY'" >/dev/null; judge M7 human "clear chattr +i on the policy" BLOCKED "$([ "$RC" -ne 0 ] && echo 1 || echo 0)" "rc=$RC"
  dev "mv '$P/etc/kiro' '$P/etc/kiro.x'" >/dev/null; judge M8 human "move the policy directory away" BLOCKED "$([ -f "$POLICY" ] && echo 1 || echo 0)" "rc=$RC"
  # Administrator-level tamper is NOT prevented (client-side enforcement); it must be DETECTED.
  chattr -i "$POLICY"; printf ' ' >> "$POLICY"; LAST_CMD="(as root) chattr -i policy && append a byte"
  # shellcheck disable=SC2086
  bash "$CHAOS_MDM" --check $MDMCHECK >/dev/null 2>&1; crc=$?
  [ "$crc" = 3 ] && rec M9 root "admin-level edit of the policy is reported by --check" BLOCKED DETECTED "check rc=3" || rec M9 root "admin-level edit of the policy is reported by --check" BLOCKED BYPASSED "check rc=$crc"
  # shellcheck disable=SC2086
  bash "$CHAOS_MDM" $MDMARGS >/dev/null 2>&1; LAST_CMD="lockdown-linux.sh (re-run as root)"
  # shellcheck disable=SC2086
  bash "$CHAOS_MDM" --check $MDMCHECK >/dev/null 2>&1; crc=$?
  judge M10 mdm "re-run restores the policy (check clean afterwards)" BLOCKED "$([ "$crc" = 0 ] && echo 1 || echo 0)" "check rc=$crc"
else
  HOOKD="$CHAOS_HOOKS_SRC"
fi

# --- H. Shipped hooks: fail-closed behaviour and the review findings ------------------------------
echo
echo "=== H. Shipped hooks ($( [ "$HOOKS_ONLY" = 1 ] && echo 'repo copies' || echo 'deployed copies, as the test user' )) ==="
for g in $CHAOS_GUARDS; do
  hj "H1-${g%%-*}" "malformed event JSON -> $g fails closed" BLOCKED "$HOOKD/$g" '{"tool_input": {"command": '
  hj "H2-${g%%-*}" "empty STDIN -> $g fails closed" BLOCKED "$HOOKD/$g" ''
done
# H3: jq missing from PATH (an internal error) must block, not allow.
mkdir -p "$S/nojq"
for t in bash sh cat grep egrep sed awk tr head tail cut printf date mkdir dirname basename wc od env sha256sum shasum perl python3 base64 xxd; do
  p="$(command -v "$t" 2>/dev/null)" && [ -n "$p" ] && ln -sf "$p" "$S/nojq/$t"
done
chmod 0755 "$S/nojq"
for g in $CHAOS_GUARDS; do
  hj "H3-${g%%-*}" "jq missing from PATH -> $g fails closed" BLOCKED "$HOOKD/$g" "$(ev_shell 'git status')" PATH="$S/nojq"
done
GG="$HOOKD/git-guard.sh"; DG="$HOOKD/destructive-fs-guard.sh"; PG="$HOOKD/pii-guard.sh"
hj H4 "force push by refspec (git push origin +main)" BLOCKED "$GG" "$(ev_shell 'git push origin +main')"
hj H5 "force push with combined flags (git push -uf origin x)" BLOCKED "$GG" "$(ev_shell 'git push -uf origin feature/x')"
hj H6 "option before subcommand (git -c x=y push --force)" BLOCKED "$GG" "$(ev_shell 'git -c color.ui=false push --force origin feature/x')"
hj H7 "wrapper (command rm -rf /)" BLOCKED "$DG" "$(ev_shell 'command rm -rf /')"
hj H8 "nested shell (bash -c \"rm -rf /\")" BLOCKED "$DG" "$(ev_shell 'bash -c "rm -rf /"')"
hj H9 "PEM private key header in written content" BLOCKED "$PG" "$(ev_write "-----BEGIN OPENSSH PRIV""ATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAA
-----END OPENSSH PRIV""ATE KEY-----")"
# Allowed operations must still pass (a guard that blocks everything is not a usable control).
for pair in "git-guard.sh|git status" "git-guard.sh|git push origin feature/x" "destructive-fs-guard.sh|rm -rf ./build"; do
  g="${pair%%|*}"; c="${pair#*|}"
  hook "$HOOKD/$g" "$(ev_shell "$c")"
  sanity "allowed command still passes: $c ($g, exit $HRC)" "$([ "$HRC" = 0 ] && echo 1 || echo 0)"
done
hook "$PG" "$(ev_write 'def add(a, b): return a + b')"
sanity "clean code passes pii-guard (exit $HRC)" "$([ "$HRC" = 0 ] && echo 1 || echo 0)"

# --- Re-test of the round-1 GAPs with shipped components / real OS controls -----------------------
echo
echo "=== R. Round-1 GAPs re-tested ==="
hj D4 "base64-encoded command piped to bash (shipped destructive-fs-guard)" GAP "$DG" "$(ev_shell 'echo cm0gLXJmIC8K | base64 -d | bash')"
hj D6 "base64-encoded card number (shipped pii-guard)" GAP "$PG" "$(ev_write 'NDExMSAxMTExIDExMTEgMTExMQ==')"
if [ "$HOOKS_ONLY" = 0 ]; then
  before="$(wc -l < "$AUDIT" 2>/dev/null || echo 0)"
  dev "KIRO_AUDIT_LOG=/dev/null bash '$HOOKD/audit-logger.sh' <<< '{\"hook_event_name\":\"postToolUse\",\"tool_name\":\"execute_bash\",\"tool_input\":{\"command\":\"ls\"}}'" >/dev/null
  judge C3 human "redirect the shipped audit-logger (KIRO_AUDIT_LOG=/dev/null)" GAP "$([ "$(wc -l < "$AUDIT")" -gt "$before" ] && echo 1 || echo 0)" "lines $before -> $(wc -l < "$AUDIT")"
  if lsattr -d "$AUDIT" 2>/dev/null | awk '{print $1}' | grep -q a; then
    dev ": > '$AUDIT'" >/dev/null; judge C3b human "truncate the append-only hook log (chattr +a set by the MDM job)" BLOCKED "$([ "$RC" -ne 0 ] && echo 1 || echo 0)" "rc=$RC"
  else
    echo "  (C3b skipped: the tmpfs home does not support chattr +a on this kernel; round 1 tests A4 on /var/tmp)"
  fi
  devo 'cp /usr/bin/git $HOME/mygit && chmod +x $HOME/mygit && $HOME/mygit --version'; O="$OUT"
  judge C2 human "run an own copy of git from a noexec home (harness OS hardening)" BLOCKED "$(echo "$O" | grep -qiE 'permission denied|cannot execute|not permitted' && echo 1 || echo 0)" "$(echo "$O" | head -1)"
  devo '/usr/bin/git --version'; O="$OUT"
  judge C1 human "approved system binary still runs (force-push must be stopped server-side)" GAP "$(echo "$O" | grep -qi 'git version' && echo 0 || echo 1)" "$(echo "$O" | head -1)"
  dev "cat '$CANARY'" >/dev/null; judge E3 human "read a root-only 0600 sensitive file (harness OS hardening)" BLOCKED "$([ "$RC" -ne 0 ] && echo 1 || echo 0)" "rc=$RC"
fi

chaos_summary
echo
echo "Not covered here (needs a Kiro client or server-side systems): whether Kiro evaluates the policy"
echo "rules, Git server branch protection, IAM, egress filtering, Kiro prompt logging."
echo
echo "=== CLEANUP ==="

# Exit status: 0 only when nothing was bypassed and every sanity check passed.
[ "$BYPASSED" -eq 0 ] && [ "$SANITY_FAIL" -eq 0 ]
