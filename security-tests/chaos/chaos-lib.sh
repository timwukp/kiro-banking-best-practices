# shellcheck shell=bash
# chaos-lib.sh - shared helpers for run-chaos.sh and run-chaos-hardened.sh. Sourced, not executed.
#
# Scope reminder (printed by both harnesses): these harnesses exercise HOOK-LEVEL and OS-LEVEL
# controls only. They do not drive a real Kiro client, so they cannot show whether Kiro evaluates
# a managed-settings rule; verify that on a pilot machine (managed-settings/README.md, Validation).

CHAOS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHAOS_HOOKS_SRC="$CHAOS_REPO/agent-hooks"
CHAOS_MDM="$CHAOS_REPO/mdm/lockdown-linux.sh"
CHAOS_POLICY="$CHAOS_REPO/managed-settings/managed-settings.banking.json"
CHAOS_GUARDS="pii-guard.sh git-guard.sh destructive-fs-guard.sh"

S=""                       # sandbox directory (everything the harness creates lives here)
CHAOS_USER="${CHAOS_USER:-kirochaos}"
UHOME=""
CREATED_USER=0
MOUNTS=""
HOOKS_ONLY=0
LOG=""; PREV="GENESIS"
N=0; BLOCKED=0; BYPASSED=0; GAP=0; DETECTED=0; SANITY_FAIL=0
LAST_CMD=""; RC=0; HRC=0
BASH_BIN="$(command -v bash)"

say()  { printf '%s\n' "$*"; }
cdie() { printf '[chaos] ERROR: %s\n' "$*" >&2; exit 2; }

chaos_banner() { # chaos_banner <title>
  say "=== $1 ==="
  say "Scope: hook-level and OS-level controls only. This harness does NOT drive a real Kiro client;"
  say "managed-settings rules are evaluated only by Kiro and must be verified on a pilot machine."
  say ""
}

sha_stdin() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'; else shasum -a 256 | awk '{print $1}'; fi; }

# Full mode needs root on a disposable Linux VM and an explicit opt-in. It never touches an
# existing account: it aborts if CHAOS_USER exists, and deletes only the account it created.
chaos_require_system_mode() {
  [ "$(uname -s)" = Linux ] || cdie "full mode is Linux only (use --hooks-only on other systems)"
  [ "$(id -u)" -eq 0 ] || cdie "full mode must run as root on a throwaway VM (use --hooks-only otherwise)"
  if [ "${CHAOS_ALLOW_SYSTEM_CHANGES:-0}" != 1 ]; then
    cdie "refusing: full mode creates a local user account, writes under /var/tmp and may mount a tmpfs.
       Run it ONLY on a disposable VM, with CHAOS_ALLOW_SYSTEM_CHANGES=1. (--hooks-only needs neither.)"
  fi
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    local v; v="$(systemd-detect-virt 2>/dev/null)"
    if [ -z "$v" ] || [ "$v" = none ]; then
      [ "${CHAOS_ALLOW_BARE_METAL:-0}" = 1 ] || cdie "this host does not look like a VM (systemd-detect-virt: ${v:-none}); set CHAOS_ALLOW_BARE_METAL=1 only if it is disposable"
    fi
    say "[chaos] virtualization: $v"
  else
    say "[chaos] WARNING: systemd-detect-virt not found; cannot confirm that this host is a VM"
  fi
  printf '%s' "$CHAOS_USER" | grep -Eq '^[a-z_][a-z0-9_-]{2,30}$' || cdie "invalid CHAOS_USER: $CHAOS_USER"
  local t
  for t in useradd userdel runuser chattr lsattr jq; do
    command -v "$t" >/dev/null 2>&1 || cdie "required tool not found: $t"
  done
  if id "$CHAOS_USER" >/dev/null 2>&1; then
    cdie "user '$CHAOS_USER' already exists. This harness never reuses or deletes a pre-existing account; set CHAOS_USER to an unused name"
  fi
}

chaos_cleanup() {
  set +e
  local m
  for m in $MOUNTS; do umount "$m" 2>/dev/null; done
  if [ -n "$S" ] && [ -d "$S" ] && command -v chattr >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
    find "$S" -xdev -exec chattr -ia {} + 2>/dev/null
  fi
  if [ "$CREATED_USER" = 1 ]; then
    pkill -u "$CHAOS_USER" 2>/dev/null
    userdel -r "$CHAOS_USER" 2>/dev/null || userdel "$CHAOS_USER" 2>/dev/null
    id "$CHAOS_USER" >/dev/null 2>&1 && say "[chaos] WARNING: could not delete the test user $CHAOS_USER" || say "[chaos] deleted the test user $CHAOS_USER (created by this run)"
  fi
  [ -n "$S" ] && rm -rf "$S"
}

chaos_sandbox() { # chaos_sandbox <prefix>
  if [ "$HOOKS_ONLY" = 1 ]; then S="$(mktemp -d "${TMPDIR:-/tmp}/$1.XXXXXX")"
  else S="$(mktemp -d "/var/tmp/$1.XXXXXX")"; fi
  [ -n "$S" ] && [ -d "$S" ] || cdie "cannot create a sandbox directory"
  trap chaos_cleanup EXIT
  trap 'exit 130' INT TERM
  chmod 0755 "$S"
  LOG="$S/results.jsonl"
}

chaos_create_user() {
  UHOME="$S/home-$CHAOS_USER"
  useradd -m -d "$UHOME" -s /bin/bash "$CHAOS_USER" || cdie "useradd failed"
  CREATED_USER=1
  chmod 0700 "$UHOME"
  say "[chaos] created test user $CHAOS_USER (home $UHOME); sudo check: $(runuser -u "$CHAOS_USER" -- sudo -n true 2>&1 | head -1) (non-zero = no sudo)"
}

# dev <command>: run an attack command as the non-privileged test user. Full mode only: attack
# commands are never run as the invoking user. Sets RC and LAST_CMD.
dev() {
  [ "$HOOKS_ONLY" = 1 ] && cdie "internal error: dev() is not available in --hooks-only mode"
  LAST_CMD="$1"
  runuser -u "$CHAOS_USER" -- env -i HOME="$UHOME" PATH="${DEV_PATH:-/usr/local/bin:/usr/bin:/bin}" LANG=C "$BASH_BIN" -c "cd \"\$HOME\" 2>/dev/null; $1" 2>&1; RC=$?
  return 0
}

# devo <command>: dev() with its output captured in OUT. Use this instead of OUT="$(dev ...)":
# a command substitution runs dev() in a subshell, which loses RC and LAST_CMD, so the evidence
# record would show the previous step's command.
devo() {
  dev "$1" > "$S/.dev-out"
  OUT="$(cat "$S/.dev-out")"
}

# sanity <description> <ok 0|1>: a non-attack check (for example "an allowed command still passes").
# Failures are reported separately from bypasses.
sanity() {
  if [ "$2" = 1 ]; then printf '  [OK      ] %s\n' "$1"; else printf '  [FAILED  ] %s\n' "$1"; SANITY_FAIL=$((SANITY_FAIL + 1)); fi
}

# hook <script path> <event json> [env assignments...]: feed one hook event on STDIN, as the test
# user in full mode. Sets HRC to the exit code (exit 2 means the hook blocked) and LAST_CMD.
hook() {
  local h="$1" ev="$2"; shift 2
  printf '%s' "$ev" > "$S/event.json"; chmod 0644 "$S/event.json"
  LAST_CMD="${*:+$* }bash $(basename "$h") <<< '$ev'"
  if [ "$HOOKS_ONLY" = 1 ]; then
    mkdir -p "$S/home"
    env HOME="$S/home" KIRO_AUDIT_LOG="$S/home/.kiro/audit/kiro-hooks.jsonl" "$@" "$BASH_BIN" "$h" < "$S/event.json" >/dev/null 2>&1
  else
    runuser -u "$CHAOS_USER" -- env -i HOME="$UHOME" PATH="${DEV_PATH:-/usr/local/bin:/usr/bin:/bin}" LANG=C "$@" "$BASH_BIN" "$h" < "$S/event.json" >/dev/null 2>&1
  fi
  HRC=$?
}

# Event builders (Kiro hook STDIN schema: hook_event_name, cwd, session_id, tool_name, tool_input).
ev_shell() { jq -cn --arg c "$1" '{hook_event_name:"preToolUse", cwd:"/workspace", session_id:"chaos", tool_name:"execute_bash", tool_input:{command:$c}}'; }
ev_write() { jq -cn --arg c "$1" '{hook_event_name:"preToolUse", cwd:"/workspace", session_id:"chaos", tool_name:"fs_write", tool_input:{path:"notes.txt", content:$c}}'; }

# rec <id> <actor> <technique> <expected BLOCKED|GAP> <result> <actual>
rec() {
  N=$((N + 1))
  local body h
  body="$(jq -cn --argjson n "$N" --arg id "$1" --arg actor "$2" --arg tech "$3" --arg cmd "$(printf '%s' "$LAST_CMD" | tr -d '\r' | sed 's/PRIVATE KEY/PRIVATE-KEY-REDACTED/g' | head -c 300)" \
    --arg exp "$4" --arg res "$5" --arg act "$6" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg prev "$PREV" \
    '{n:$n, id:$id, actor:$actor, technique:$tech, cmd:$cmd, expected:$exp, result:$res, actual:$act, ts:$ts, prev:$prev}')"
  h="$(printf '%s' "$body" | sha_stdin)"
  printf '%s hash=%s\n' "$body" "$h" >> "$LOG"
  PREV="$h"
  case "$5" in BLOCKED) BLOCKED=$((BLOCKED + 1)) ;; BYPASSED) BYPASSED=$((BYPASSED + 1)) ;; GAP) GAP=$((GAP + 1)) ;; DETECTED) DETECTED=$((DETECTED + 1)) ;; esac
  printf '  [%-8s] %-5s %-4s %s (%s)\n' "$5" "$2" "$1" "$3" "$6"
}

# judge <id> <actor> <technique> <expected> <held 0|1> <actual>: held=1 -> BLOCKED; otherwise GAP
# when the gap is expected, BYPASSED (an unexpected control failure) when it is not.
judge() {
  local res
  if [ "$5" = 1 ]; then res=BLOCKED; elif [ "$4" = GAP ]; then res=GAP; else res=BYPASSED; fi
  rec "$1" "$2" "$3" "$4" "$res" "$6"
}

# hj <id> <technique> <expected> <hook script> <event> [env...]: run a hook event and judge exit 2.
hj() {
  local id="$1" tech="$2" exp="$3" h="$4" ev="$5"; shift 5
  hook "$h" "$ev" "$@"
  [ "$HRC" = 2 ] && judge "$id" agent "$tech" "$exp" 1 "exit 2" || judge "$id" agent "$tech" "$exp" 0 "exit $HRC"
}

chaos_summary() {
  say ""
  say "=== RESULT LOG (hash-chained JSONL; the literal command of each attempt is in \"cmd\") ==="
  cat "$LOG"
  say ""
  say "=== SUMMARY ==="
  say "total=$N BLOCKED=$BLOCKED DETECTED=$DETECTED GAP=$GAP BYPASSED=$BYPASSED sanity-failures=$SANITY_FAIL"
  say "(BYPASSED = unexpected control failure to fix; GAP = documented limitation covered by another"
  say " layer; DETECTED = change not prevented but caught by the MDM drift check)"
  [ "$BYPASSED" -eq 0 ] && say "RESULT: no unexpected bypass" || say "RESULT: $BYPASSED unexpected bypass(es) to fix"
  [ "$SANITY_FAIL" -eq 0 ] || say "RESULT: $SANITY_FAIL sanity check(s) failed (for example a false positive on an allowed command)"
  if [ -n "${CHAOS_KEEP_LOG:-}" ]; then cp "$LOG" "$CHAOS_KEEP_LOG" && say "log copied to $CHAOS_KEEP_LOG"; fi
}
