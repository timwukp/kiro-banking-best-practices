#!/usr/bin/env bash
# test-lockdown.sh - Root-required OS-enforcement test for MDM lockdown.
# Run on a Linux box (e.g. via SSM on the EC2). NOT part of CI (needs root + chattr).
# Verifies: immutability (no modify/delete), append-only audit, self-heal, and the
# destructive-fs-guard hook. Uses a temp dir on a disk filesystem (chattr needs ext4/xfs).

HERE="$(cd "$(dirname "$0")/.." && pwd)"   # agent-hooks/
PASS=0; FAIL=0
ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
ng() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
[ "$(id -u)" -eq 0 ] || { echo "must run as root (sudo)"; exit 1; }

W="$(mktemp -d -p /var/tmp kiro-lock.XXXXXX)"
export KIRO_SRC="$HERE" KIRO_DEST="$W/hooks" \
       KIRO_AGENT_SRC="$HERE/banking-secure.agent.json" KIRO_AGENT_DEST="$W/agents/banking-secure.json" \
       KIRO_AUDIT_LOG="$W/audit.jsonl"

echo "== apply lockdown =="
bash "$HERE/mdm/lockdown-linux.sh" >/dev/null 2>&1 && ok "lockdown-linux.sh ran" || ng "lockdown-linux.sh failed"
H="$KIRO_DEST/destructive-fs-guard.sh"
[ -e "$H" ] && ok "lockdown deployed the hook" || ng "lockdown did NOT deploy the hook"

echo "== immutability =="
( echo x >> "$H" ) 2>/dev/null && ng "immutable hook was modifiable" || ok "immutable hook cannot be modified"
rm -f "$H" 2>/dev/null && ng "immutable hook was deletable" || ok "immutable hook cannot be deleted (even by root)"

echo "== append-only audit =="
( echo '{"e":1}' >> "$KIRO_AUDIT_LOG" ) 2>/dev/null && ok "audit log accepts append" || ng "audit append failed"
( : > "$KIRO_AUDIT_LOG" ) 2>/dev/null && ng "append-only log was truncatable" || ok "audit log cannot be truncated"

echo "== self-heal =="
chattr -i "$H" 2>/dev/null; rm -f "$H"
[ -e "$H" ] && ng "self-heal setup (delete) failed" || true
bash "$HERE/mdm/lockdown-linux.sh" >/dev/null 2>&1
[ -e "$H" ] && ok "self-heal restored the deleted hook" || ng "self-heal did NOT restore"

echo "== destructive-fs-guard =="
ev() { printf '{"hook_event_name":"preToolUse","tool_name":"shell","tool_input":{"command":%s}}' "$1"; }
ev '"rm -rf /"'       | bash "$HERE/destructive-fs-guard.sh" 2>/dev/null && ng "should block rm -rf /"       || ok "blocks rm -rf /"
ev '"rm -rf .git"'    | bash "$HERE/destructive-fs-guard.sh" 2>/dev/null && ng "should block rm -rf .git"    || ok "blocks rm -rf .git"
ev '"find . -delete"' | bash "$HERE/destructive-fs-guard.sh" 2>/dev/null && ng "should block find -delete"   || ok "blocks find -delete"
ev '"rm -rf ./build"' | bash "$HERE/destructive-fs-guard.sh" 2>/dev/null && ok "allows scoped rm -rf ./build" || ng "false positive on ./build"

# cleanup (remove immutable/append-only flags first)
chattr -ia "$KIRO_AUDIT_LOG" 2>/dev/null
find "$W" -exec chattr -i {} \; 2>/dev/null
rm -rf "$W"

echo
echo "RESULT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
