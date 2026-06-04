#!/usr/bin/env bash
# audit-logger.sh - Kiro CLI postToolUse hook (MAS TRM 12/15).
#
# Appends a SHA-256 hash-chained (tamper-evident) JSONL record per tool call.
# The CloudWatch agent on the VDI tails $KIRO_AUDIT_LOG to ship records to
# CloudWatch Logs (Layer 5). postToolUse cannot block (the tool already ran);
# a write failure exits non-zero so the gap surfaces as a warning (fail-loud).

INPUT="$(cat)"
LOG="${KIRO_AUDIT_LOG:-$HOME/.kiro/audit/tool-use.jsonl}"
STATE="${KIRO_AUDIT_STATE:-$HOME/.kiro/audit/.chain-head}"
mkdir -p "$(dirname "$LOG")" "$(dirname "$STATE")" 2>/dev/null

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}';
  else shasum -a 256 | awk '{print $1}'; fi
}

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TOOL="unknown"
if command -v jq >/dev/null 2>&1; then
  TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)"
fi

PREV="$(cat "$STATE" 2>/dev/null || echo GENESIS)"
BODY="{\"ts\":\"$TS\",\"session\":\"${KIRO_SESSION_ID:-unknown}\",\"tool\":\"$TOOL\",\"prev\":\"$PREV\"}"
HASH="$(printf '%s' "$BODY" | sha256)"

if ! printf '%s hash=%s\n' "$BODY" "$HASH" >> "$LOG" 2>/dev/null; then
  echo "audit-logger: WARNING - failed to write audit log at $LOG" >&2
  exit 1
fi
printf '%s' "$HASH" > "$STATE" 2>/dev/null || true

exit 0
