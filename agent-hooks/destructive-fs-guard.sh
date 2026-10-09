#!/usr/bin/env bash
# destructive-fs-guard.sh - Kiro preToolUse hook for shell commands (matcher "execute_bash" / "shell").
#
# Blocks bulk or irreversible deletion of the workspace, the home directory, the
# repository history (.git) or system paths, and raw writes to disk devices
# (MAS TRM 11.3 system security). Ordinary scoped deletes (rm -rf ./build) pass.
#
# Defense in depth, not a sandbox. The primary control is managed-settings/
# (admin deny/ask rules); VDI images and OS permissions are further layers.
#
# Contract (https://kiro.dev/docs/hooks/):
#   stdin  : JSON {"hook_event_name","cwd","session_id","tool_name","tool_input":{"command":...}}
#   exit 0 : allow
#   exit 2 : block; the reason on stderr is returned to the model
# Every failure path (empty or invalid input, missing jq, internal error) exits 2.
# The inspected command is only parsed as text; it is never executed.

set -u
set -o pipefail

fail() { echo "destructive-fs-guard: BLOCKED - $1. Use a narrowly scoped path (MAS TRM 11.3)." >&2; exit 2; }
trap 'fail "internal error in guard (failing closed)"' ERR

command -v jq >/dev/null 2>&1 || fail "jq is required by this guard (failing closed)"

INPUT="$(cat)"
[ -n "$INPUT" ] || fail "empty hook input (failing closed)"
printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || fail "hook input is not a JSON object (failing closed)"

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty | tostring')"
[ -n "$CMD" ] || exit 0   # not a shell command

# Same normalization as git-guard.sh: unwrap "sh -c" wrappers, drop quotes and
# backslashes, one simple command per line.
normalize() {
  printf '%s\n' "$1" \
    | sed -E 's#(^|[;&|()[:space:]])(/usr/bin/|/bin/)?(ba|z|da|k)?sh[[:space:]]+-[A-Za-z]*c[[:space:]]+#\1 #g' \
    | tr -d "\"'\\\\" \
    | awk '{ gsub(/&&|\|\||[;|`()]|\$\(/, "\n"); print }'
}

REASON="$(normalize "$CMD" | awk '
function block(msg) { print msg; exit 0 }
function protected_path(t) {
  if (t == "/" || t == "/*" || t == "*" || t == "." || t == "./" || t == "./*") return 1
  if (t == "~" || t == "~/" || t == "~/*") return 1
  if (t ~ /^\$\{?HOME\}?\/?\*?$/) return 1
  if (t ~ /^(\.\.\/?)+\*?$/) return 1
  if (t ~ /^\/(bin|boot|dev|etc|home|lib|lib64|opt|proc|root|run|sbin|srv|sys|usr|var|Users|System|Library|Applications|private|Volumes)\/?\*?$/) return 1
  if (t ~ /(^|\/)\.git\/?$/) return 1
  return 0
}
{
  n = NF; i = 1
  while (i <= n && ($i ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || $i == "env" || $i == "command" || $i == "exec" || $i == "nohup" || $i == "time" || $i == "sudo" || $i == "xargs")) i++
  if (i > n) next
  cmd = $i; sub(/.*\//, "", cmd); i++

  if (cmd == "rm") {
    rec = 0; endopt = 0
    for (j = i; j <= n; j++) {
      a = $j
      if (endopt) continue
      if (a == "--") { endopt = 1; continue }
      if (a == "--no-preserve-root") block("rm --no-preserve-root")
      if (a == "--recursive" || a ~ /^-[A-Za-z]*[rR][A-Za-z]*$/) rec = 1
    }
    if (!rec) next
    endopt = 0
    for (j = i; j <= n; j++) {
      a = $j
      if (!endopt && a == "--") { endopt = 1; continue }
      if (!endopt && substr(a, 1, 1) == "-") continue
      if (protected_path(a)) block("recursive delete of a protected path (" a ")")
    }
  } else if (cmd == "mv") {
    for (j = i; j <= n; j++) {
      if (substr($j, 1, 1) == "-") continue
      if ($j ~ /(^|\/)\.git\/?$/) block("moving the .git directory")
      break
    }
  } else if (cmd == "find") {
    for (j = i; j <= n; j++) {
      if ($j == "-delete") block("find ... -delete")
      if (($j == "-exec" || $j == "-execdir" || $j == "-ok") && j < n) {
        x = $(j + 1); sub(/.*\//, "", x)
        if (x == "rm" || x == "shred") block("find ... " $j " " x)
      }
    }
  } else if (cmd ~ /^mkfs/) {
    block("filesystem format (" cmd ")")
  } else if (cmd == "dd") {
    for (j = i; j <= n; j++)
      if ($j ~ /^of=\/dev\// && $j !~ /^of=\/dev\/(null|zero|stdout|stderr|tty|fd\/)/) block("dd to a device (" $j ")")
  }
}')"

[ -z "$REASON" ] || fail "$REASON"
exit 0
