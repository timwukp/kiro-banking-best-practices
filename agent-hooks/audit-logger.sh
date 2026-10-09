#!/usr/bin/env bash
# audit-logger.sh - Kiro postToolUse hook (matcher "*"). Never blocks: always exits 0.
#
# Appends one hash-chained JSON line per tool call to
#   ${KIRO_AUDIT_LOG:-$HOME/.kiro/audit/kiro-hooks.jsonl}
# Fields: ts, event, session_id, tool_name, cwd, input_sha256, response_bytes,
#         prev_hash, hash   (hash = SHA-256 of prev_hash + the record without hash,
#                            record serialized with sorted keys: jq -cS)
# The raw tool input is never written (only its SHA-256), to keep PII and secrets
# out of the log. The file is only appended to, so it works with the append-only
# flags set by mdm/ (chattr +a / chflags uappnd or sappnd).
#
# Limits: the chain is tamper-EVIDENT against casual edits only. It has no secret
# key, so anyone who can rewrite the whole file can recompute it. The authoritative
# audit trail is Kiro prompt logging and user activity reports (S3, profile region)
# plus CloudTrail; ship this file to your SIEM as a supplementary signal.
#
# Verify a log:
#   prev=GENESIS; while IFS= read -r l; do
#     r=$(printf '%s' "$l" | jq -cS 'del(.hash)'); h=$(printf '%s' "$l" | jq -r .hash)
#     [ "$(printf '%s%s' "$prev" "$r" | shasum -a 256 | cut -d' ' -f1)" = "$h" ] || echo BROKEN; prev=$h
#   done < kiro-hooks.jsonl

set -u
umask 077

LOG="${KIRO_AUDIT_LOG:-$HOME/.kiro/audit/kiro-hooks.jsonl}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
INPUT="$(cat 2>/dev/null || true)"

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else sha256sum | cut -d' ' -f1; fi
}

if ! command -v jq >/dev/null 2>&1; then
  # Degraded mode: no JSON tooling, so record that a call happened without a chain.
  printf '{"ts":"%s","event":"audit-logger-degraded","note":"jq not found; record not captured"}\n' "$TS" >> "$LOG" 2>/dev/null || true
  exit 0
fi

PREV="GENESIS"
if [ -s "$LOG" ]; then
  PREV="$(tail -n 1 "$LOG" | jq -r '.hash // "GENESIS"' 2>/dev/null || echo GENESIS)"
  [ -n "$PREV" ] || PREV="GENESIS"
fi

INPUT_SHA="$(printf '%s' "$INPUT" | jq -cS '.tool_input // null' 2>/dev/null | sha256)" || INPUT_SHA="unparseable"

RECORD="$(printf '%s' "$INPUT" | jq -cS \
  --arg ts "$TS" --arg prev "$PREV" --arg isha "$INPUT_SHA" --arg sid "${KIRO_SESSION_ID:-}" '
  { ts: $ts,
    event: (.hook_event_name // "postToolUse"),
    session_id: (.session_id // (if $sid == "" then null else $sid end)),
    tool_name: (.tool_name // null),
    cwd: (.cwd // null),
    input_sha256: $isha,
    response_bytes: (if .tool_response == null then 0 else (.tool_response | tostring | length) end),
    prev_hash: $prev }' 2>/dev/null)" \
  || RECORD="$(jq -cnS --arg ts "$TS" --arg prev "$PREV" '{ts: $ts, event: "unparseable-input", prev_hash: $prev}')"

HASH="$(printf '%s%s' "$PREV" "$RECORD" | sha256)"
printf '%s\n' "$RECORD" | jq -c --arg h "$HASH" '. + {hash: $h}' >> "$LOG" 2>/dev/null || true
exit 0
