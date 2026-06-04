#!/usr/bin/env bash
# lockdown-macos.sh - macOS reference for what an MDM (Jamf / Kandji / Intune) pushes and
# runs on each Kiro client. MAS TRM 9/11/12/15.
#
# Immutability via chflags: schg (system-immutable - the production setting, needs root and
# is only clearable in single-user mode) when run as root; uchg (user-immutable) otherwise.
# Audit log gets sappnd/uappnd (append-only). Idempotent: re-running RESTORES & RE-LOCKS
# (self-heal). Honest limit: same as Linux - anti-tamper, not secrecy.
set -u

SRC="${KIRO_SRC:?set KIRO_SRC to the canonical source dir, e.g. the repo agent-hooks directory}"
DEST="${KIRO_DEST:-/Library/Application Support/Kiro/hooks}"
AGENT_SRC="${KIRO_AGENT_SRC:-$SRC/banking-secure.agent.json}"
AGENT_DEST="${KIRO_AGENT_DEST:-/Library/Application Support/Kiro/agents/banking-secure.json}"
AUDIT="${KIRO_AUDIT_LOG:-/Library/Logs/Kiro/tool-use.jsonl}"

command -v chflags >/dev/null 2>&1 || { echo "lockdown-macos: chflags unavailable" >&2; exit 1; }
if [ "$(id -u)" -eq 0 ]; then IMM=schg; APP=sappnd
else IMM=uchg; APP=uappnd; echo "lockdown-macos: not root - using user flags ($IMM/$APP); production MDM applies schg/sappnd as root" >&2; fi

lock()   { chflags "$IMM" "$1" 2>/dev/null && echo "  immutable($IMM): $1"; }
unlock() { chflags "no$IMM" "$1" 2>/dev/null || true; }

mkdir -p "$DEST" "$(dirname "$AGENT_DEST")" "$(dirname "$AUDIT")"

for f in "$SRC"/*.sh; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  unlock "$DEST/$b"
  install -m 0755 "$f" "$DEST/$b"
  lock "$DEST/$b"
done

if [ -f "$AGENT_SRC" ]; then
  unlock "$AGENT_DEST"
  install -m 0644 "$AGENT_SRC" "$AGENT_DEST"
  lock "$AGENT_DEST"
fi

if [ ! -f "$AUDIT" ]; then : > "$AUDIT"; fi
chflags "$APP" "$AUDIT" 2>/dev/null && echo "  append-only($APP): $AUDIT"

echo "lockdown-macos: done. Re-run via the MDM schedule to self-heal."
