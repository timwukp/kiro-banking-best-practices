#!/usr/bin/env bash
# git-guard.sh - Kiro preToolUse hook for shell commands (matcher "execute_bash" / "shell").
#
# Blocks git operations that rewrite or delete shared history, or that push
# directly to a protected branch (MAS TRM 6.3 segregation of duties, 7.5 change
# management). Normal commits and feature-branch pushes pass through.
#
# Defense in depth only. Authoritative controls:
#   - managed-settings/ admin deny/ask rules (Kiro splits compound commands);
#   - server-side branch protection / rulesets on the Git host.
#
# Contract (https://kiro.dev/docs/hooks/):
#   stdin  : JSON {"hook_event_name","cwd","session_id","tool_name","tool_input":{"command":...}}
#   exit 0 : allow
#   exit 2 : block; the reason on stderr is returned to the model
# Every failure path (empty or invalid input, missing jq, internal error) exits 2.
# The inspected command is only parsed as text; it is never executed.

set -u
set -o pipefail

fail() { echo "git-guard: BLOCKED - $1. Use a feature branch and a pull request (MAS TRM 6.3 / 7.5)." >&2; exit 2; }
trap 'fail "internal error in guard (failing closed)"' ERR

command -v jq >/dev/null 2>&1 || fail "jq is required by this guard (failing closed)"

INPUT="$(cat)"
[ -n "$INPUT" ] || fail "empty hook input (failing closed)"
printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || fail "hook input is not a JSON object (failing closed)"

CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty | tostring')"
[ -n "$CMD" ] || exit 0   # not a shell command

# Normalize to one simple command per line:
#   1. unwrap "bash -c" / "sh -c" / "zsh -c" wrappers,
#   2. drop quotes and backslashes,
#   3. split on ; && || | newlines, $( ), backticks and parentheses.
normalize() {
  printf '%s\n' "$1" \
    | sed -E 's#(^|[;&|()[:space:]])(/usr/bin/|/bin/)?(ba|z|da|k)?sh[[:space:]]+-[A-Za-z]*c[[:space:]]+#\1 #g' \
    | tr -d "\"'\\\\" \
    | awk '{ gsub(/&&|\|\||[;|`()]|\$\(/, "\n"); print }'
}

REASON="$(normalize "$CMD" | awk '
function block(msg) { print msg; exit 0 }
{
  n = NF; i = 1
  # skip env assignments and transparent prefixes
  while (i <= n && ($i ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || $i == "env" || $i == "command" || $i == "exec" || $i == "nohup" || $i == "time" || $i == "sudo")) i++
  if (i > n) next
  cmd = $i; sub(/.*\//, "", cmd)
  if (cmd != "git") next
  i++
  # skip git global options (-C <dir>, -c <k=v>, --git-dir=..., --no-pager, ...)
  while (i <= n && substr($i, 1, 1) == "-") {
    if ($i == "-C" || $i == "-c" || $i == "--git-dir" || $i == "--work-tree" || $i == "--namespace") { i += 2 } else { i++ }
  }
  if (i > n) next
  op = $i; i++

  if (op == "push") {
    pos = 0
    for (; i <= n; i++) {
      a = $i
      if (a == "--") continue
      if (a ~ /^--(force|force-with-lease|force-if-includes|mirror|delete|prune)/) block("git push " a)
      if (a ~ /^-[A-Za-z]+$/ && a ~ /[fd]/) block("git push " a)
      if (substr(a, 1, 1) == "-") continue
      pos++
      if (pos == 1) continue                      # remote name
      if (substr(a, 1, 1) == "+") block("forced refspec " a)
      if (substr(a, 1, 1) == ":") block("branch deletion via refspec " a)
      dst = a; sub(/^.*:/, "", dst); sub(/^refs\/heads\//, "", dst)
      if (dst == "main" || dst == "master") block("direct push to protected branch " dst)
    }
  } else if (op == "reset") {
    for (; i <= n; i++) if ($i == "--hard") block("git reset --hard")
  } else if (op == "clean") {
    for (; i <= n; i++) if ($i == "--force" || ($i ~ /^-[A-Za-z]+$/ && $i ~ /f/)) block("git clean " $i)
  } else if (op == "branch") {
    del = 0; frc = 0; prot = 0
    for (; i <= n; i++) {
      if ($i ~ /^-[A-Za-z]+$/ && $i ~ /D/) block("git branch -D")
      if ($i == "-d" || $i == "--delete") del = 1
      if ($i == "-f" || $i == "--force") frc = 1
      if ($i == "main" || $i == "master") prot = 1
    }
    if (del && (frc || prot)) block("deletion of a protected or unmerged branch")
  } else if (op == "filter-branch" || op == "filter-repo") {
    block("git " op " (history rewrite)")
  } else if (op == "update-ref") {
    for (; i <= n; i++) if ($i == "-d" || $i == "--delete") block("git update-ref -d")
  } else if (op == "reflog") {
    for (; i <= n; i++) if ($i == "expire" || $i == "delete") block("git reflog " $i)
  } else if (op == "gc") {
    for (; i <= n; i++) if ($i ~ /^--prune=now/) block("git gc --prune=now")
  }
}')"

[ -z "$REASON" ] || fail "$REASON"
exit 0
