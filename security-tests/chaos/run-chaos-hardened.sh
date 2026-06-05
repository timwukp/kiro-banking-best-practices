#!/usr/bin/env bash
# run-chaos-hardened.sh - Round 2: re-test the GAPs from run-chaos.sh after adding STRONGER
# LOCAL (endpoint/MDM-layer) controls, to show which GAPs close locally and which remain
# residual (-> server-side / inherent). Run as ROOT on a sandbox host. Contained; auto-cleans.
#
# Hardened local controls added (all endpoint-layer):
#   - Application control: developer HOME on a noexec mount (own binaries cannot execute).
#   - Fixed/managed audit path (hook ignores KIRO_AUDIT_LOG).
#   - denyByDefault allow-list gate (only approved commands run; simulates Kiro toolsSettings).
#   - Least-privilege data access (sensitive file not readable by the developer).

set -u
[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }
command -v chattr >/dev/null 2>&1 || { echo "chattr required"; exit 1; }

S="$(mktemp -d /var/tmp/chaos2.XXXXXX)"
HOMEDIR="$S/devxhome"; AUDITFIX="$S/audit-fixed.jsonl"; CANARY="$S/canary.txt"
LOG="$S/results.jsonl"; CMDF="$S/.cmd"; PREV="GENESIS"
N=0; BLOCKED=0; GAP=0
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum|awk '{print $1}'; else shasum -a256|awk '{print $1}'; fi; }
san() { printf '%s' "$1" | tr -d '\n\r' | sed "s/\"/'/g" | cut -c1-160; }
rec() { N=$((N+1)); local ts body h; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  body="$(printf '{"n":%d,"id":"%s","control":"%s","cmd":"%s","baseline":"GAP","result":"%s","ts":"%s","prev":"%s"}' \
    "$N" "$1" "$2" "$(san "$(cat "$CMDF" 2>/dev/null)")" "$3" "$ts" "$PREV")"
  h="$(printf '%s' "$body"|sha)"; printf '%s hash=%s\n' "$body" "$h" >> "$LOG"; PREV="$h"
  case "$3" in BLOCKED) BLOCKED=$((BLOCKED+1));; GAP) GAP=$((GAP+1));; esac
  printf '  [%-8s] %-4s %s\n' "$3" "$1" "$2"; }
dev() { printf '%s' "$1" > "$CMDF"; su devx -c "HOME=$HOMEDIR; $1" 2>&1; }

echo "=== SETUP: non-privileged devx + hardened LOCAL controls ==="
chmod 0755 "$S"
id devx >/dev/null 2>&1 || useradd devx
mkdir -p "$HOMEDIR"; mount -t tmpfs -o noexec,nosuid,size=32m tmpfs "$HOMEDIR"; chown devx:devx "$HOMEDIR"
usermod -d "$HOMEDIR" devx 2>/dev/null

# Fixed/managed audit hook (ignores env; hardcoded path) -- the recommended fix for C3
cat > "$S/audit-fixed.sh" <<EOF
#!/bin/bash
A="$AUDITFIX"   # hardcoded; KIRO_AUDIT_LOG is ignored
printf '{"ts":"%s","tool":"shell"}\n' "\$(date -u +%FT%TZ)" >> "\$A"
EOF
chmod 0755 "$S/audit-fixed.sh"; chown root:root "$S/audit-fixed.sh"; chattr +i "$S/audit-fixed.sh" 2>/dev/null
: > "$AUDITFIX"; chown devx:devx "$AUDITFIX"; chmod 0644 "$AUDITFIX"; chattr +a "$AUDITFIX" 2>/dev/null

# Least-privilege sensitive data: NOT readable by the developer (the fix for E3)
echo "card 4111 1111 1111 1111 NRIC S1234567D" > "$CANARY"; chown root:root "$CANARY"; chmod 0600 "$CANARY"

# denyByDefault allow-list gate (simulates Kiro toolsSettings denyByDefault)
policy_allow() { case "$1" in "git status"|"git diff"|"ls"|"npm test"|"npm run build") return 0;; *) return 1;; esac; }

echo
echo "=== RE-TEST of GAPs under hardened LOCAL controls ==="

# C3 -> fixed audit path: env override must NOT redirect the audit
dev "KIRO_AUDIT_LOG=/dev/null bash $S/audit-fixed.sh" >/dev/null
L=$(wc -l < "$AUDITFIX"); [ "$L" -ge 1 ] && rec C3 "fixed/managed audit path (ignore env)" BLOCKED || rec C3 "fixed/managed audit path" GAP

# E3 -> least-privilege data: developer cannot read the sensitive file
printf '%s' "cat $CANARY" > "$CMDF"; out="$(dev "cat $CANARY" 2>&1)"; echo "$out" | grep -qi "permission denied" && rec E3 "least-privilege data (canary 0600 root)" BLOCKED || rec E3 "least-privilege data" GAP

# D4 -> denyByDefault allow-list: base64|bash is not on the allow-list
C='echo cm0gLXJmIC8K | base64 -d | bash'; printf '%s' "policy_allow: $C" > "$CMDF"
policy_allow "$C" && rec D4 "denyByDefault allow-list (base64|bash)" GAP || rec D4 "denyByDefault allow-list (base64|bash not allowed)" BLOCKED
# sanity: an allow-listed command passes
printf '%s' "policy_allow: git status" > "$CMDF"; policy_allow "git status" && rec D4b "denyByDefault allows approved cmd (git status)" BLOCKED || rec D4b "denyByDefault wrongly blocks approved cmd" GAP

# C2 -> application control (noexec HOME): own binary cannot execute
out="$(dev 'cp /usr/bin/git $HOME/mygit && chmod +x $HOME/mygit && $HOME/mygit --version' 2>&1)"
echo "$out" | grep -qiE "permission denied|cannot execute|not permitted" && rec C2 "app-control: noexec HOME blocks own binary" BLOCKED || rec C2 "app-control: noexec HOME" GAP

# C1 -> approved system binary still executes (local app-control does NOT gate approved binaries)
out="$(dev '/usr/bin/git --version' 2>&1)"; echo "$out" | grep -qi "git version" && rec C1 "approved binary runs -> force-push authority must be server-side" GAP || rec C1 "approved binary blocked" BLOCKED

# D6 -> obfuscated PII content remains undetected by signature hooks (inherent limit)
printf '%s' "base64 PII content (no signature match)" > "$CMDF"; rec D6 "obfuscated PII content (inherent detection limit)" GAP

echo
echo "=== HARDENED RESULT LOG (hash-chained) ==="; cat "$LOG"
echo
echo "=== SUMMARY (round 2: GAPs re-tested under hardened LOCAL controls) ==="
echo "re-tested=$N  CLOSED_LOCALLY(BLOCKED)=$BLOCKED  RESIDUAL(GAP)=$GAP"

echo
echo "=== CLEANUP ==="
chattr -ia "$AUDITFIX" "$S/audit-fixed.sh" 2>/dev/null
umount "$HOMEDIR" 2>/dev/null
usermod -d /home/devx devx 2>/dev/null
userdel devx 2>/dev/null
rm -rf "$S"
echo "cleanup done"
