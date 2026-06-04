#!/usr/bin/env bash
# test-lockdown-macos.sh - OS-enforcement test for the macOS lockdown (chflags).
# Runs without root using user-immutable (uchg) in a temp dir; production uses schg as root.
# Verifies immutability (no modify/delete), append-only audit, and self-heal.

case "$(uname -s)" in Darwin) ;; *) echo "macOS only - skipping"; exit 0;; esac
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
ng() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

W="$(mktemp -d /tmp/kiro-mac.XXXXXX)"
export KIRO_SRC="$HERE" KIRO_DEST="$W/hooks" \
       KIRO_AGENT_SRC="$HERE/banking-secure.agent.json" KIRO_AGENT_DEST="$W/agents/banking-secure.json" \
       KIRO_AUDIT_LOG="$W/audit.jsonl"

bash "$HERE/mdm/lockdown-macos.sh" >/dev/null 2>&1 && ok "lockdown-macos.sh ran" || ng "lockdown-macos.sh failed"
H="$KIRO_DEST/destructive-fs-guard.sh"
[ -e "$H" ] && ok "lockdown deployed the hook" || ng "lockdown did NOT deploy the hook"

( echo x >> "$H" ) 2>/dev/null && ng "immutable hook was modifiable" || ok "immutable hook cannot be modified"
rm -f "$H" 2>/dev/null && ng "immutable hook was deletable" || ok "immutable hook cannot be deleted"
( echo '{"e":1}' >> "$KIRO_AUDIT_LOG" ) 2>/dev/null && ok "audit log accepts append" || ng "audit append failed"
( : > "$KIRO_AUDIT_LOG" ) 2>/dev/null && ng "append-only log was truncatable" || ok "audit log cannot be truncated"

chflags nouchg "$H" 2>/dev/null; rm -f "$H"
bash "$HERE/mdm/lockdown-macos.sh" >/dev/null 2>&1
[ -e "$H" ] && ok "self-heal restored the deleted hook" || ng "self-heal did NOT restore"

# cleanup (clear flags first, then remove)
chflags -R nouchg,nouappnd "$W" 2>/dev/null
rm -rf "$W"

echo
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
