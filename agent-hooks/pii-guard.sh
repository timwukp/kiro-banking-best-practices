#!/usr/bin/env bash
# pii-guard.sh - Kiro preToolUse hook (matcher "*" / any tool).
#
# Blocks a tool call when its input contains secrets or Singapore personal data
# (PDPA; MAS TRM 11.1). Defense in depth only: the primary control is the admin
# policy in managed-settings/ (deny/ask rules enforced by the Kiro client).
#
# Contract (https://kiro.dev/docs/hooks/):
#   stdin  : JSON {"hook_event_name","cwd","session_id","tool_name","tool_input":{...}}
#   exit 0 : allow
#   exit 2 : block; the reason on stderr is returned to the model
# Kiro docs disagree on whether other non-zero exit codes block, so every failure
# path here (empty or invalid input, missing jq, internal error) exits 2.
#
# Patterns are intentionally broad: a false positive costs a retry, a false
# negative can leak data. Tune them per institution.

set -u
set -o pipefail

fail() { echo "pii-guard: BLOCKED - $1" >&2; exit 2; }
trap 'fail "internal error in guard (failing closed)"' ERR

command -v jq >/dev/null 2>&1 || fail "jq is required by this guard (failing closed)"

INPUT="$(cat)"
[ -n "$INPUT" ] || fail "empty hook input (failing closed)"
printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1 \
  || fail "hook input is not a JSON object (failing closed)"

# Scan every scalar value inside tool_input, decoded (so JSON escaping does not
# hide a value), one value per line.
PAYLOAD="$(printf '%s' "$INPUT" | jq -r '[(.tool_input // {}) | .. | scalars | tostring] | join("\n")')"
[ -n "$PAYLOAD" ] || exit 0

# Extended regular expressions, matched case-insensitively with grep -Eiq -e.
# The -e is required: some patterns start with characters grep would otherwise
# treat as options.
patterns=(
  'BEGIN [A-Z ]*PRIVATE KEY'                                        # PEM private keys (RSA, EC, OPENSSH, ENCRYPTED, PKCS#8)
  '(^|[^a-z0-9])(akia|asia)[a-z0-9]{16}([^a-z0-9]|$)'               # AWS access key IDs (long-term and temporary)
  'aws_secret_access_key[^a-z0-9]{0,4}[:=]'                         # AWS secret access key assignment
  '(^|[^a-z0-9])gh[pousr]_[a-z0-9]{30,}'                            # GitHub tokens
  'github_pat_[a-z0-9_]{20,}'                                       # GitHub fine-grained tokens
  'sk-ant-[a-z0-9_-]{20,}'                                          # Anthropic API keys
  '(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)[^a-z0-9[:space:]]{0,2}[[:space:]]*[:=][[:space:]]*[^[:space:],;}]{6,}'
  '(^|[^a-z0-9])[stfgm][0-9]{7}[a-z]([^a-z0-9]|$)'                  # Singapore NRIC / FIN (S, T, F, G, M series)
  '(^|[^0-9])[0-9]{4}([ .-]?[0-9]{4}){2}[ .-]?[0-9]{1,7}([^0-9]|$)' # payment card numbers (13-19 digits, optional separators)
  '(^|[^0-9])3[47][0-9]{2}[ .-]?[0-9]{6}[ .-]?[0-9]{5}([^0-9]|$)'   # American Express (4-6-5)
)

for p in "${patterns[@]}"; do
  if printf '%s\n' "$PAYLOAD" | grep -Eiq -e "$p"; then
    fail "tool input matches a secret or personal-data pattern (PDPA / MAS TRM 11.1). Remove or mask the value and retry."
  fi
done

exit 0
