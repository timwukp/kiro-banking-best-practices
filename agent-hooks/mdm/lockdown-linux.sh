#!/usr/bin/env bash
# lockdown-linux.sh - Reference for what an MDM (Intune / Jamf / Workspace ONE / Kandji)
# pushes to and runs on each Linux / VDI Kiro client. MAS TRM 9/11/12/15.
#
# Deploys the canonical GLOBAL control files (security hooks + locked agent) to a
# root-owned path and makes them tamper-proof:
#   - hooks/agent  -> chattr +i (immutable: no modify, no delete, even by root until -i)
#   - audit log    -> chattr +a (append-only: cannot be truncated/rewritten)
# IDEMPOTENT: re-running RESTORES and RE-LOCKS any removed/edited file. Scheduling this
# (cron / systemd timer / the MDM agent's periodic re-apply) gives self-healing.
#
# Requires root. Honest limit: kiro-cli runs as the developer, so the same user can READ
# these files. This provides anti-tamper / anti-delete / anti-bypass + self-healing, NOT
# secrecy. "Executable only by the agent / unreadable by humans" needs a separate service
# account or brokered exec, which Kiro CLI does not natively provide.
set -u

SRC="${KIRO_SRC:?set KIRO_SRC to the canonical source dir, e.g. the repo agent-hooks directory}"
DEST="${KIRO_DEST:-/opt/kiro/hooks}"
AGENT_SRC="${KIRO_AGENT_SRC:-$SRC/banking-secure.agent.json}"
AGENT_DEST="${KIRO_AGENT_DEST:-/opt/kiro/agents/banking-secure.json}"
AUDIT="${KIRO_AUDIT_LOG:-/var/log/kiro/tool-use.jsonl}"

[ "$(id -u)" -eq 0 ] || { echo "lockdown-linux: must run as root" >&2; exit 1; }
command -v chattr >/dev/null 2>&1 || { echo "lockdown-linux: chattr unavailable (install e2fsprogs)" >&2; exit 1; }

lock()   { chattr +i "$1" 2>/dev/null && echo "  immutable: $1"; }
unlock() { chattr -i "$1" 2>/dev/null || true; }

install -d -o root -g root -m 0755 "$DEST" "$(dirname "$AGENT_DEST")" "$(dirname "$AUDIT")"

# Deploy + lock each guardrail hook (unlock first so a re-run can refresh = self-heal).
for f in "$SRC"/*.sh; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  unlock "$DEST/$b"
  install -o root -g root -m 0755 "$f" "$DEST/$b"
  lock "$DEST/$b"
done

# Deploy + lock the locked agent config.
if [ -f "$AGENT_SRC" ]; then
  unlock "$AGENT_DEST"
  install -o root -g root -m 0644 "$AGENT_SRC" "$AGENT_DEST"
  lock "$AGENT_DEST"
fi

# Append-only, tamper-evident audit log.
if [ ! -f "$AUDIT" ]; then : > "$AUDIT"; chown root:root "$AUDIT"; chmod 0644 "$AUDIT"; fi
chattr +a "$AUDIT" 2>/dev/null && echo "  append-only: $AUDIT"

echo "lockdown-linux: done. Re-run via the MDM schedule / cron to self-heal."
