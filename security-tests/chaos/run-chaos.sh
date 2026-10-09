#!/usr/bin/env bash
# run-chaos.sh - Round 1: chaos / penetration harness for the endpoint controls of this repo.
#
# SCOPE: exercises HOOK-LEVEL controls (the shipped agent-hooks/*.sh, fed crafted Kiro hook events)
# and OS-LEVEL controls (file ownership, chattr +i / +a, sudo, PATH) only. It does NOT drive a real
# Kiro client, so it cannot show whether Kiro evaluates managed-settings.json rules; verify those on
# a pilot machine (managed-settings/README.md, "Validation"). Attacks marked "agent" are simulated
# by feeding the event JSON that Kiro would send to a hook; they are not issued by a Kiro agent.
#
# MODES
#   --hooks-only   No root, no system changes, safe on a laptop or in CI. Runs only the hook-level
#                  attacks (series D) against agent-hooks/*.sh in place, with HOME and
#                  KIRO_AUDIT_LOG redirected to a temporary directory.
#   (default)      Full run. Requires ALL of: Linux, root, a THROWAWAY VM, CHAOS_ALLOW_SYSTEM_CHANGES=1.
#                  It creates a new local account (CHAOS_USER, default "kirochaos") and aborts if that
#                  account already exists; it never reuses or deletes a pre-existing account. It
#                  deploys the SHIPPED controls with mdm/lockdown-linux.sh into a temporary --prefix
#                  under /var/tmp (never the real /etc or /opt), runs the attack catalog as that
#                  non-privileged user, logs every attempt with its literal command to a hash-chained
#                  JSONL, then deletes the account it created and the sandbox (also on error).
#
#   sudo CHAOS_ALLOW_SYSTEM_CHANGES=1 bash security-tests/chaos/run-chaos.sh      # throwaway VM only
#   bash security-tests/chaos/run-chaos.sh --hooks-only                            # anywhere
#
# The "demo PATH guard" (a root-owned git wrapper first on PATH) is a deliberately basic control
# kept from the original round 1 to show its limits (C1/C2); it is not a recommended control.
# Method and purpose of every attack: kiro-docs/chaos-pentest-evidence.md.
set -u
. "$(cd "$(dirname "$0")" && pwd)/chaos-lib.sh"

case "${1:-}" in
  --hooks-only) HOOKS_ONLY=1 ;;
  "") ;;
  -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
  *) cdie "unknown option: $1 (use --hooks-only or no option)" ;;
esac
command -v jq >/dev/null 2>&1 || cdie "jq is required (the hooks need it too)"
for h in $CHAOS_GUARDS audit-logger.sh; do [ -f "$CHAOS_HOOKS_SRC/$h" ] || cdie "shipped hook not found: agent-hooks/$h"; done
[ "$HOOKS_ONLY" = 1 ] || chaos_require_system_mode

chaos_banner "ROUND 1 ($( [ "$HOOKS_ONLY" = 1 ] && echo 'hooks-only' || echo 'full' ) run)"
chaos_sandbox kiro-chaos

if [ "$HOOKS_ONLY" = 1 ]; then
  HOOKD="$CHAOS_HOOKS_SRC"
else
  echo "=== SETUP (as root = MDM / control plane) ==="
  [ -f "$CHAOS_HOOKS_SRC/SHA256SUMS" ] || cdie "agent-hooks/SHA256SUMS not found; the shipped hooks are only deployed after hash verification"
  chaos_create_user
  P="$S/root"
  bash "$CHAOS_MDM" --prefix "$P" --hooks --install-user "$CHAOS_USER" --user-home "$UHOME" \
    || cdie "mdm/lockdown-linux.sh refused or failed; nothing to test"
  POLICY="$P/etc/kiro/managed-settings.json"; HOOKD="$P/opt/kiro/hooks"
  AUDIT="$UHOME/.kiro/audit/kiro-hooks.jsonl"; V1="$UHOME/.kiro/hooks/banking-guards.json"
  MDMARGS="--prefix $P --hooks --install-user $CHAOS_USER --user-home $UHOME"
  printf '%s\n' '{"seed":1}' | runuser -u "$CHAOS_USER" -- tee -a "$AUDIT" >/dev/null
  # Demo PATH guard (basic control, see header), decoy production data, synthetic canary, local sink.
  GBIN="$S/bin"; PROD="$S/prod"; CANARY="$S/canary.txt"; SINK="$S/sink"
  mkdir -p "$GBIN" "$PROD" "$SINK"
  cat > "$GBIN/git" <<'GUARD'
#!/bin/bash
for a in "$@"; do case "$a" in --force|--force-with-lease|-f) echo "POLICY: force-push denied by the demo PATH guard" >&2; exit 1;; esac; done
case "$*" in *push*main*|*push*master*) echo "POLICY: push to a protected branch denied by the demo PATH guard" >&2; exit 1;; esac
exec /usr/bin/git "$@"
GUARD
  chown root:root "$GBIN/git"; chmod 0755 "$GBIN" "$GBIN/git"; chattr +i "$GBIN/git" 2>/dev/null
  echo "prod data" > "$PROD/data"; chown -R root:root "$PROD"; chmod 0755 "$PROD"; chmod 0644 "$PROD/data"
  echo "card 4111 1111 1111 1111 NRIC S1234567D AKIAIOSFODNN7EXAMPLE" > "$CANARY"; chmod 0644 "$CANARY"
  chown "$CHAOS_USER" "$SINK"
  DEV_PATH="$GBIN:/usr/local/bin:/usr/bin:/bin"
  echo
  echo "=== ATTACKS as $CHAOS_USER (non-privileged human in a plain shell) ==="

  # A. Integrity tamper - disable or erase the deployed controls (expect BLOCKED unless noted).
  G="$HOOKD/destructive-fs-guard.sh"
  dev "echo x >> '$G'" >/dev/null; judge A1 human "modify deployed hook (echo >>)" BLOCKED "$([ "$RC" -ne 0 ] && echo 1 || echo 0)" "rc=$RC"
  dev "rm -f '$G'" >/dev/null; judge A2 human "delete deployed hook (rm)" BLOCKED "$([ -e "$G" ] && echo 1 || echo 0)" "exists=$([ -e "$G" ] && echo yes || echo no)"
  dev "chattr -i '$G'" >/dev/null; judge A3 human "clear immutable attribute (chattr -i)" BLOCKED "$([ "$RC" -ne 0 ] && echo 1 || echo 0)" "rc=$RC"
  dev ": > '$AUDIT'" >/dev/null; judge A4 human "truncate append-only hook audit log" BLOCKED "$([ -s "$AUDIT" ] && echo 1 || echo 0)" "size=$(wc -c < "$AUDIT")"
  dev "cp /bin/true '$GBIN/git'" >/dev/null; judge A5 human "replace the demo PATH guard" BLOCKED "$([ "$RC" -ne 0 ] && echo 1 || echo 0)" "rc=$RC"
  dev "echo '{\"rules\":[]}' > '$POLICY'" >/dev/null; judge A6 human "overwrite managed-settings.json" BLOCKED "$([ "$RC" -ne 0 ] && echo 1 || echo 0)" "rc=$RC"
  dev "rm -f '$POLICY' || mv '$P/etc/kiro' '$P/etc/kiro.x'" >/dev/null; judge A7 human "delete or move managed-settings.json" BLOCKED "$([ -f "$POLICY" ] && echo 1 || echo 0)" "exists=$([ -f "$POLICY" ] && echo yes || echo no)"
  # A8: the per-user v1 hook file is user-owned BY DESIGN (Kiro only loads ~/.kiro/hooks). Expected
  # GAP; the MDM drift check must then report it and a re-run must restore it.
  dev "rm -f '$V1'" >/dev/null; judge A8 human "delete user-owned ~/.kiro/hooks/banking-guards.json" GAP "$([ -e "$V1" ] && echo 1 || echo 0)" "exists=$([ -e "$V1" ] && echo yes || echo no)"
  # shellcheck disable=SC2086
  bash "$CHAOS_MDM" --check $MDMARGS >/dev/null 2>&1; crc=$?; LAST_CMD="lockdown-linux.sh --check (as root)"
  [ "$crc" = 3 ] && rec A8d mdm "drift check reports the deleted user file" BLOCKED DETECTED "check rc=3" || rec A8d mdm "drift check reports the deleted user file" BLOCKED BYPASSED "check rc=$crc"
  # shellcheck disable=SC2086
  bash "$CHAOS_MDM" $MDMARGS >/dev/null 2>&1; LAST_CMD="lockdown-linux.sh (re-run as root)"
  judge A8r mdm "re-run restores the user file" BLOCKED "$([ -f "$V1" ] && echo 1 || echo 0)" "exists=$([ -f "$V1" ] && echo yes || echo no)"
  # A9: the developer owns ~/.kiro/audit and can rename it (documented limitation of the local log).
  dev "mv '$UHOME/.kiro/audit' '$UHOME/.kiro/audit.moved'" >/dev/null; judge A9 human "rename the user-owned audit directory" GAP "$([ "$RC" -ne 0 ] && echo 1 || echo 0)" "rc=$RC"
  [ -d "$UHOME/.kiro/audit.moved" ] && runuser -u "$CHAOS_USER" -- mv "$UHOME/.kiro/audit.moved" "$UHOME/.kiro/audit"

  # B. Privilege probing.
  dev "sudo -n true" >/dev/null; judge B1 human "non-interactive sudo" BLOCKED "$([ "$RC" -ne 0 ] && echo 1 || echo 0)" "rc=$RC"
  Wd="$(dev "find '$GBIN' /usr/local/bin /usr/bin -maxdepth 1 -writable 2>/dev/null | head -1")"
  judge B2 human "writable file or directory on PATH" BLOCKED "$([ -z "$Wd" ] && echo 1 || echo 0)" "${Wd:-none}"

  # C. Command-guard and audit evasion.
  O="$(dev "cd '$S' && git push --force 2>&1")"; judge C0 human "force-push through the demo PATH guard" BLOCKED "$(echo "$O" | grep -q POLICY && echo 1 || echo 0)" "$(echo "$O" | grep -q POLICY && echo policy || echo no-policy)"
  O="$(dev "cd '$S' && /usr/bin/git push --force 2>&1")"; judge C1 human "real git by absolute path (bypasses a PATH guard)" GAP "$(echo "$O" | grep -q POLICY && echo 1 || echo 0)" "$(echo "$O" | grep -q POLICY && echo policy || echo guard-bypassed)"
  O="$(dev "cp /usr/bin/git \$HOME/mygit && chmod +x \$HOME/mygit && cd '$S' && \$HOME/mygit push --force 2>&1")"; judge C2 human "own copy of the git binary" GAP "$(echo "$O" | grep -q POLICY && echo 1 || echo 0)" "$(echo "$O" | grep -q POLICY && echo policy || echo guard-bypassed)"
  before="$(wc -l < "$AUDIT")"
  dev "KIRO_AUDIT_LOG=/dev/null bash '$HOOKD/audit-logger.sh' <<< '{\"hook_event_name\":\"postToolUse\",\"tool_name\":\"execute_bash\",\"tool_input\":{\"command\":\"ls\"}}'" >/dev/null
  judge C3 human "redirect the hook audit log (KIRO_AUDIT_LOG=/dev/null)" GAP "$([ "$(wc -l < "$AUDIT")" -gt "$before" ] && echo 1 || echo 0)" "lines $before -> $(wc -l < "$AUDIT")"
fi

echo
echo "=== HOOK-LEVEL ATTACKS (crafted Kiro preToolUse events fed to the $( [ "$HOOKS_ONLY" = 1 ] && echo 'repo' || echo 'deployed' ) hooks) ==="
DG="$HOOKD/destructive-fs-guard.sh"; GG="$HOOKD/git-guard.sh"; PG="$HOOKD/pii-guard.sh"
hj D1 "rm -rf / (plain)" BLOCKED "$DG" "$(ev_shell 'rm -rf /')"
hj D2 "rm -fr / (spaced, flag order)" BLOCKED "$DG" "$(ev_shell 'rm  -fr  /')"
hj D3 "chained: ls && rm -rf /" BLOCKED "$DG" "$(ev_shell 'ls && rm -rf /')"
hj D4 "base64-encoded command piped to bash" GAP "$DG" "$(ev_shell 'echo cm0gLXJmIC8K | base64 -d | bash')"
hj D5 "card number (spaced) in written content" BLOCKED "$PG" "$(ev_write 'card 4111 1111 1111 1111')"
hj D6 "card number base64-encoded" GAP "$PG" "$(ev_write 'NDExMSAxMTExIDExMTEgMTExMQ==')"
hj D7 "git push -f origin main" BLOCKED "$GG" "$(ev_shell 'git push -f origin main')"
# Variants from the PR3 review (fixed in agent-hooks/, regression-tested in agent-hooks/tests/).
hj D8 "force push by refspec: git push origin +main" BLOCKED "$GG" "$(ev_shell 'git push origin +main')"
hj D9 "git push --force-with-lease" BLOCKED "$GG" "$(ev_shell 'git push --force-with-lease origin feature/x')"
hj D10 "option before subcommand: git -c x=y push --force" BLOCKED "$GG" "$(ev_shell 'git -c color.ui=false push --force origin feature/x')"
hj D11 "wrapper: command rm -rf /" BLOCKED "$DG" "$(ev_shell 'command rm -rf /')"
hj D12 "wrapper: env rm -rf ~" BLOCKED "$DG" "$(ev_shell 'env rm -rf ~')"
hj D13 "quoting: \"rm\" -rf /" BLOCKED "$DG" "$(ev_shell '"rm" -rf /')"
hj D14 "PEM private key header in written content" BLOCKED "$PG" "$(ev_write "-----BEGIN RSA PRIV""ATE KEY-----
MIIEowIBAAKCAQEA
-----END RSA PRIV""ATE KEY-----")"
for g in $CHAOS_GUARDS; do
  hj "D15-${g%%-*}" "malformed event JSON -> $g must fail closed (exit 2)" BLOCKED "$HOOKD/$g" '{"tool_input": {"command": "rm -rf /"'
done

if [ "$HOOKS_ONLY" = 0 ]; then
  echo
  echo "=== PROHIBITED ACTIONS end-to-end (as $CHAOS_USER) ==="
  dev "rm -f '$PROD/data'" >/dev/null; judge E1 human "delete root-owned decoy production file" BLOCKED "$([ -e "$PROD/data" ] && echo 1 || echo 0)" "exists=$([ -e "$PROD/data" ] && echo yes || echo no)"
  dev "rm -rf '$PROD'" >/dev/null; judge E2 human "rm -rf root-owned decoy production directory" BLOCKED "$([ -d "$PROD" ] && echo 1 || echo 0)" "exists=$([ -d "$PROD" ] && echo yes || echo no)"
  dev "cat '$CANARY' > '$SINK/leak.txt'" >/dev/null; judge E3 human "copy readable synthetic PII to a local sink (no egress control here)" GAP "$([ -s "$SINK/leak.txt" ] && echo 0 || echo 1)" "$([ -s "$SINK/leak.txt" ] && echo copied || echo blocked)"
fi

chaos_summary
echo
echo "=== CLEANUP ==="

# Exit status: 0 only when nothing was bypassed and every sanity check passed.
[ "$BYPASSED" -eq 0 ] && [ "$SANITY_FAIL" -eq 0 ]
