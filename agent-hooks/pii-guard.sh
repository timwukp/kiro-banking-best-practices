#!/usr/bin/env bash
# pii-guard.sh - Kiro CLI preToolUse hook (banking / PDPA + MAS TRM 11.1).
#
# Contract: the hook JSON event arrives on STDIN. Exit 2 BLOCKS the tool call
# (STDERR is returned to the model); exit 0 allows; any other code warns + allows.
# The whole tool_input payload is scanned, so this guard is tool-agnostic.
#
# Detection is intentionally broad (fail-safe): a false positive blocks a call,
# a false negative leaks data. Tune the patterns per institution.

INPUT="$(cat)"

patterns=(
  '[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}'                                   # 16-digit card (Visa/MC)
  '3[47][0-9]{2}[- ]?[0-9]{6}[- ]?[0-9]{5}'                                            # Amex (4-6-5)
  'AKIA[0-9A-Z]{16}'                                                                   # AWS access key id
  '-----BEGIN[A-Z ]*PRIVATE KEY-----'                                                  # PEM private key block
  '[STFG][0-9]{7}[A-Z]'                                                                # Singapore NRIC/FIN
  '(password|passwd|secret|api[_-]?key|access[_-]?token)[[:space:]]*[=:][[:space:]]*[^[:space:]]{6,}'
)

for p in "${patterns[@]}"; do
  if printf '%s' "$INPUT" | grep -Eq "$p"; then
    echo "pii-guard: BLOCKED - tool input matches a PII/secret pattern (PDPA / MAS TRM 11.1). Remove the sensitive value and retry." >&2
    exit 2
  fi
done

exit 0
