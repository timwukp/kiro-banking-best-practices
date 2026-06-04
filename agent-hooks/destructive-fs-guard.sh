#!/usr/bin/env bash
# destructive-fs-guard.sh - Kiro CLI preToolUse hook, matcher "shell" (MAS TRM 9/11).
#
# Guards against accidental or malicious destruction of the repo/workspace by the agent.
# Contract: the hook JSON event arrives on STDIN; exit 2 BLOCKS the tool call.
# Note: this stops destruction *via the agent*. OS-level immutability (see
# mdm/lockdown-linux.sh) protects the managed control files from any user.

INPUT="$(cat)"
CMD=""
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
fi
[ -z "${CMD:-}" ] && CMD="$INPUT"

block() { echo "destructive-fs-guard: BLOCKED - $1. Use a narrowly scoped path (MAS TRM 9/11)." >&2; exit 2; }

# 1. Recursive force-delete of a top-level / home / current-tree root (e.g. rm -rf / ~ . *)
if printf '%s' "$CMD" | grep -Eq 'rm[[:space:]]+((-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+|-[a-zA-Z]*[fF][a-zA-Z]*[[:space:]]+|--recursive[[:space:]]+|--force[[:space:]]+)){1,}(/|/\*|~|~/|~/\*|\.|\./|\.\.|\*|\$HOME|\$HOME/\*?)([[:space:]]|$)'; then
  block "recursive force-delete of a root / home / workspace path"
fi
# 2. Deleting a .git directory
if printf '%s' "$CMD" | grep -Eq 'rm[[:space:]].*[[:space:]/]\.git([[:space:]]|/|$)'; then
  block "deletion of a .git directory"
fi
# 3. Bulk find -delete
if printf '%s' "$CMD" | grep -Eq 'find[[:space:]].*-delete'; then
  block "bulk 'find ... -delete'"
fi
# 4. Disk-destroying commands
if printf '%s' "$CMD" | grep -Eq '(mkfs([.][a-z0-9]+)?[[:space:]]|dd[[:space:]]+.*of=/dev/)'; then
  block "disk-destroying command (mkfs/dd to a device)"
fi

exit 0
