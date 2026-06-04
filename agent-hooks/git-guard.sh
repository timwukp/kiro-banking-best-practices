#!/usr/bin/env bash
# git-guard.sh - Kiro CLI preToolUse hook, matcher "shell" (MAS TRM 6/9).
#
# Contract: the hook JSON event arrives on STDIN. Exit 2 BLOCKS the tool call.
# Blocks force-push, push to a protected branch (main/master), and history-
# destructive operations. Normal commits and feature-branch pushes pass through.

INPUT="$(cat)"

# Extract the shell command from tool_input.command (jq if present, raw fallback).
CMD=""
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
fi
[ -z "${CMD:-}" ] && CMD="$INPUT"

block() {
  echo "git-guard: BLOCKED - $1. Use the approved branch/PR workflow (MAS TRM 6/9)." >&2
  exit 2
}

if printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+push.*(--force|--force-with-lease)'; then
  block "git force-push"
fi
if printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+push.*[[:space:]](main|master)([[:space:]":]|$)'; then
  block "git push to a protected branch (main/master)"
fi
if printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+reset[[:space:]]+--hard'; then
  block "git reset --hard"
fi
if printf '%s' "$CMD" | grep -Eq 'git[[:space:]]+clean[[:space:]]+-[A-Za-z]*f'; then
  block "git clean -f"
fi

exit 0
