#!/usr/bin/env bash
# lockdown-macos.sh - Reference MDM job (Jamf Pro / Kandji / Intune) for macOS Kiro clients
# (Kiro IDE 1.x, Kiro CLI 2.x). MAS TRM 9.1 (access), 11.1 (data), 11.3 (system security),
# 12.2 (monitoring). Last verified against kiro.dev docs: 2026-10-08.
#
# PRIMARY CONTROL (always):
#   Deploys the admin policy file to the OFFICIAL Kiro path
#   "/Library/Application Support/Kiro/managed-settings.json" (root:wheel 0644). As root the file
#   also gets the system-immutable flag (chflags schg). Whether root can clear schg depends on
#   kern.securelevel: at securelevel 0 root can run "chflags noschg"; at securelevel 1 or higher it
#   can only be cleared from single-user or Recovery mode, so later MDM updates of the file need
#   Recovery mode too. Use --no-system-immutable where that is not acceptable; root ownership and
#   mode 0644 already stop a developer without admin rights. Kiro enforcement is client-side: an
#   admin user can remove the file, so developers must not be local admins.
#
# OPTIONAL (defense in depth):
#   --hooks              verify agent-hooks/SHA256SUMS, then deploy the listed hook scripts to
#                        "/Library/Application Support/Kiro/hooks" (root:wheel 0755, schg).
#   --install-user USER  install the v1 hook file into ~USER/.kiro/hooks/ and the agent into
#                        ~USER/.kiro/agents/. Kiro loads agents only from ~/.kiro/agents and a
#                        trusted workspace's .kiro/agents (never from /Library or /opt), and global
#                        v1 hook files only from ~/.kiro/hooks. The shipped files reference
#                        /opt/kiro/hooks; the deployed copies are rewritten to the macOS hooks
#                        directory. These files are user-owned: the developer can edit or delete
#                        them (Kiro's hardcoded "always ask" rule only stops the AGENT from changing
#                        them silently). The guarantee comes from managed-settings, not from these
#                        files; --check reports their drift.
#   --audit-user USER    prepare ~USER/.kiro/audit/kiro-hooks.jsonl as a user-owned file (0600) with
#                        the append-only flag set by root. Default: the USER flag uappnd. While it is
#                        set, nothing can truncate, overwrite, rename or delete the file, but the
#                        OWNER (and any process running as the owner, including the agent's shell
#                        commands) can clear it with "chflags nouappnd", so it is NOT protection
#                        against the developer; it only stops accidental truncation. --audit-sappnd uses the super-user flag
#                        sappnd instead: the owner cannot clear it, and at kern.securelevel >= 1
#                        root cannot either without Recovery mode (log rotation then needs Recovery
#                        mode too). In both cases the user owns the directory and can rename it, so
#                        the local log is supplementary; Kiro prompt logging is the audit record.
#
# Order of work: EVERYTHING is validated first (policy JSON, SHA256SUMS, user hook files, user
# accounts); only then is anything installed. A refusal (exit 2) leaves the machine unchanged.
# Re-runnable (idempotent); --dry-run validates and plans without changes (no root needed);
# --check reports drift (exit 3) for the MDM detection step. No network calls are made.
#
# Exit codes: 0 ok | 1 usage/environment error | 2 validation refused | 3 drift (--check)
set -uo pipefail
umask 022

SELF="lockdown-macos"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

SETTINGS_SRC="${KIRO_MANAGED_SETTINGS_SRC:-$REPO_DIR/managed-settings/managed-settings.banking.json}"
HOOKS_SRC="${KIRO_HOOKS_SRC:-$REPO_DIR/agent-hooks}"
HOOKS_DIR="${KIRO_HOOKS_DEST:-/Library/Application Support/Kiro/hooks}"
MANIFEST_PIN="${KIRO_HOOKS_MANIFEST_SHA256:-}"
DEPLOY_HOOKS="${KIRO_DEPLOY_HOOKS:-0}"
INSTALL_USER="${KIRO_INSTALL_USER:-}"
USER_FILES="${KIRO_USER_FILES:-both}"
AUDIT_USER="${KIRO_AUDIT_USER:-}"
USER_HOME_OVERRIDE="${KIRO_USER_HOME:-}"          # test only
PREFIX="${KIRO_ROOT_PREFIX:-}"                    # test only
DRY_RUN="${KIRO_DRY_RUN:-0}"
STRICT="${KIRO_STRICT:-0}"
IMMUTABLE=1
CHECK_ONLY=0
AUDIT_FLAG="${KIRO_AUDIT_FLAG:-uappnd}"           # uappnd (default, owner can clear) | sappnd
REWRITE_OUT=""                                    # test only: copy rewritten user files here

usage() {
  cat <<'EOF'
Usage: sudo lockdown-macos.sh [options]

  --dry-run              Validate JSON, policy and hashes, preview the rewritten hook commands
                         and print the planned actions. No system changes; no root needed.
  --check                Compare the deployed files with the sources; exit 3 on drift.
  --settings FILE        managed-settings source (default managed-settings/managed-settings.banking.json)
  --option-b             Shortcut for --settings managed-settings/managed-settings.option-b.json
  --hooks                Also deploy hash-verified hook scripts
  --hooks-src DIR        Hook source directory (default agent-hooks/)
  --hooks-dest DIR       Hook directory (default "/Library/Application Support/Kiro/hooks";
                         /opt/kiro/hooks is an option without spaces, see the docs)
  --manifest-sha256 HEX  Expected SHA-256 of SHA256SUMS (pin delivered out of band by the MDM)
  --install-user USER    Install the v1 hook file and the agent for USER (implies --hooks)
  --user-files WHICH     both | hooks | agent (default both)
  --audit-user USER      Prepare USER's append-only hook audit log (default: the install user)
  --audit-sappnd         Use the super-user flag sappnd on the audit log instead of uappnd
                         (owner cannot clear it; see the header for the securelevel caveat)
  --no-system-immutable  Do not set schg / uappnd / sappnd (alias: --no-immutable)
  --strict               Treat validation warnings (for example placeholder values) as errors
  --rewrite-out DIR      TEST ONLY: write the rewritten user JSON files to DIR (works in --dry-run)
  --user-home DIR        TEST ONLY: home directory to use for USER
  --prefix DIR           TEST ONLY: prepend DIR to every system path
  -h, --help             Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --check) CHECK_ONLY=1 ;;
    --settings) SETTINGS_SRC="${2:?--settings needs a file}"; shift ;;
    --option-b) SETTINGS_SRC="$REPO_DIR/managed-settings/managed-settings.option-b.json" ;;
    --hooks) DEPLOY_HOOKS=1 ;;
    --hooks-src) HOOKS_SRC="${2:?--hooks-src needs a directory}"; shift ;;
    --hooks-dest) HOOKS_DIR="${2:?--hooks-dest needs a directory}"; shift ;;
    --manifest-sha256) MANIFEST_PIN="${2:?--manifest-sha256 needs a hash}"; shift ;;
    --install-user) INSTALL_USER="${2:?--install-user needs a user}"; shift ;;
    --user-files) USER_FILES="${2:?--user-files needs both|hooks|agent}"; shift ;;
    --audit-user) AUDIT_USER="${2:?--audit-user needs a user}"; shift ;;
    --audit-sappnd) AUDIT_FLAG=sappnd ;;
    --no-system-immutable|--no-immutable) IMMUTABLE=0 ;;
    --strict) STRICT=1 ;;
    --rewrite-out) REWRITE_OUT="${2:?--rewrite-out needs a directory}"; shift ;;
    --user-home) USER_HOME_OVERRIDE="${2:?--user-home needs a directory}"; shift ;;
    --prefix) PREFIX="${2:?--prefix needs a directory}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[$SELF] ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

case "$HOOKS_DIR" in /*) ;; *) echo "[$SELF] ERROR: --hooks-dest must be an absolute path" >&2; exit 1 ;; esac
case "$HOOKS_DIR" in *'"'*|*"'"*|*'\'*|*'$'*|*'`'*) echo "[$SELF] ERROR: --hooks-dest must not contain quotes, backslashes, \$ or backticks" >&2; exit 1 ;; esac
case "$AUDIT_FLAG" in uappnd|sappnd) ;; *) echo "[$SELF] ERROR: KIRO_AUDIT_FLAG must be uappnd or sappnd" >&2; exit 1 ;; esac
SETTINGS_DIR="$PREFIX/Library/Application Support/Kiro"
SETTINGS_DEST="$SETTINGS_DIR/managed-settings.json"
HOOKS_DEST="$PREFIX$HOOKS_DIR"
HOOK_CMD_PREFIX="/opt/kiro/hooks"                 # path referenced by the shipped JSON
AUDIT_REL=".kiro/audit/kiro-hooks.jsonl"
AGENT_SRC_NAME="banking-secure.agent.json"
V1_SRC_NAME="hooks/banking-guards.json"

WARNINGS=0
DRIFT=0
STAGE=""
DEPLOYABLE=""

log()  { printf '[%s] %s\n' "$SELF" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$SELF" "$*" >&2; WARNINGS=$((WARNINGS + 1)); }
die()  { local rc="$1"; shift; printf '[%s] ERROR: %s\n' "$SELF" "$*" >&2; exit "$rc"; }
drift() { printf '[%s] DRIFT: %s\n' "$SELF" "$*"; DRIFT=$((DRIFT + 1)); }
plan() { log "[dry-run] would $*"; }
run() {
  local desc="$1"; shift
  if [ "$DRY_RUN" = 1 ]; then plan "$desc"; return 0; fi
  "$@" || die 1 "failed to $desc"
}
cleanup() { [ -n "$STAGE" ] && [ -d "$STAGE" ] && rm -rf "$STAGE"; }
trap cleanup EXIT

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'; fi
}
owner_mode() { stat -f '%Su %Lp' "$1" 2>/dev/null; }
file_flags() { stat -f '%Sf' "$1" 2>/dev/null; }
has_flag() { file_flags "$1" | tr ',' '\n' | grep -qx "$2"; }
valid_username() { printf '%s' "$1" | grep -Eq '^[A-Za-z_][A-Za-z0-9_.-]{0,31}$'; }

user_home() {
  local u="$1" h=""
  if [ -n "$USER_HOME_OVERRIDE" ]; then printf '%s' "$USER_HOME_OVERRIDE"; return 0; fi
  [ -z "$PREFIX" ] || die 1 "--prefix is test-only and requires --user-home for user operations"
  h="$(dscl . -read "/Users/$u" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p')"
  [ -n "$h" ] || die 1 "user '$u' not found (dscl)"
  printf '%s' "$h"
}

# Writes into a user-owned directory are made with the user's privileges (no root symlink tricks).
as_user() {
  local u="$1"; shift
  if [ "$(id -un)" = "$u" ]; then "$@"; return $?; fi
  sudo -n -u "$u" -- "$@"
}

securelevel() { sysctl -n kern.securelevel 2>/dev/null || echo unknown; }

set_flag() { # set_flag <flag> <file>; never fatal
  [ "$IMMUTABLE" = 1 ] || return 0
  [ "$(id -u)" -eq 0 ] || { warn "not root: cannot set $1 on $2"; return 0; }
  chflags "$1" "$2" 2>/dev/null || warn "chflags $1 failed for $2; relying on ownership and mode"
}
clear_schg() { # clear_schg <file>: needed before an update; fails at securelevel >= 1
  has_flag "$1" schg || return 0
  chflags noschg "$1" 2>/dev/null && return 0
  die 1 "cannot clear schg on $1 (kern.securelevel=$(securelevel)); boot to Recovery or single-user mode to update it"
}

# ---------------------------------------------------------------------------------------------
# Validation (identical rules to lockdown-linux.sh)
# ---------------------------------------------------------------------------------------------
check_encoding() {
  local head
  head="$(LC_ALL=C od -An -tx1 -N3 "$1" | tr -d ' \n')"
  case "$head" in
    efbbbf*) die 2 "$2 starts with a UTF-8 BOM; Kiro requires UTF-8 without BOM" ;;
    fffe*|feff*) die 2 "$2 is UTF-16; Kiro requires UTF-8 without BOM" ;;
  esac
}

# jq program: one line per finding, prefixed ERROR: or WARN:. Mirrors the documented
# managed-settings validation (https://kiro.dev/docs/enterprise/governance/permissions/).
JQ_VALIDATE='
def err(m): "ERROR: " + m;
def warn(m): "WARN: " + m;
def member(xs): . as $x | (xs | map(. == $x) | any);
def caps: ["fs_read","fs_write","shell","web_fetch","web_search","mcp","subagent","skill","power",
           "context","diagnostics","sandbox_network","all","builtin","filesystem","signin_method"];
def signin_values: ["*","idc","external_idp","builder_id","google","github","social"];
def setting_keys: ["idc_start_url","idc_region","external_idp_domain","external_idp_start_url",
                   "external_idp_region","signin_help_url"];
if type != "object" then err("top level must be a JSON object")
else
  ( (keys - ["rules","settings"])[] | err("unknown top-level field \"" + . + "\" (Kiro rejects the whole file)") ),
  ( if has("rules") | not then err("\"rules\" is required (use [] when only settings are set)")
    elif (.rules | type) != "array" then err("\"rules\" must be an array")
    else
      ( .rules | to_entries[] | .key as $i | .value as $r |
        if ($r | type) != "object" then err("rules[\($i)] must be an object")
        else
          ( (($r | keys) - ["capability","match","exclude","effect"])[] | err("rules[\($i)]: unknown field \"\(.)\" (Kiro rejects the whole file)") ),
          ( if ($r.capability | type) != "string" then err("rules[\($i)]: \"capability\" (string) is required")
            elif ($r.capability | member(caps) | not) then warn("rules[\($i)]: unknown capability \"\($r.capability)\" (Kiro skips it)")
            else empty end ),
          ( if ($r.effect | type) != "string" then err("rules[\($i)]: \"effect\" is required")
            elif $r.effect == "allow" then err("rules[\($i)]: effect \"allow\" is not permitted in managed-settings (Kiro rejects the whole file and denies all tool calls)")
            elif ($r.effect | member(["deny","ask"]) | not) then err("rules[\($i)]: effect must be deny or ask, got \"\($r.effect)\"")
            else empty end ),
          ( ("match","exclude") as $k |
            if ($r | has($k)) and ((($r[$k] | type) != "array") or ([$r[$k][] | type] | any(. != "string")))
            then err("rules[\($i)]: \"\($k)\" must be an array of strings") else empty end ),
          ( if $r.capability == "signin_method" then
              ( if $r.effect != "deny" then warn("rules[\($i)]: signin_method rules must use deny (Kiro ignores others)") else empty end ),
              ( if ((($r.match // []) | length) + (($r.exclude // []) | length)) > 16
                then err("rules[\($i)]: signin_method allows at most 16 entries across match and exclude") else empty end ),
              ( (($r.match // []) + ($r.exclude // []))[] | strings | select(member(signin_values) | not)
                | warn("rules[\($i)]: unknown signin_method value \"\(.)\" (values are case-sensitive)") )
            else empty end )
        end )
    end ),
  ( if has("settings") then
      if (.settings | type) != "object" then err("\"settings\" must be an object")
      else
        ( .settings | to_entries[] |
          if (.key | member(setting_keys) | not) then warn("settings.\(.key): unknown key (Kiro ignores it)")
          elif (.value | type) != "string" then err("settings.\(.key) must be a string")
          elif .key == "signin_help_url" and ((.value | test("^https://")) | not) then err("settings.signin_help_url must be an https:// URL")
          elif .key == "signin_help_url" and ((.value | length) > 2048) then err("settings.signin_help_url exceeds 2048 characters")
          elif (.key | test("_url$")) and ((.value | test("^https://")) | not) then warn("settings.\(.key) is not an https:// URL")
          else empty end ),
        ( [.settings[] | strings | select(test("REPLACE|CHANGE-?ME|xxxx|example\\.|my-org|[<>]"; "i"))]
          | if length > 0 then warn("settings contain placeholder values; set your organisation values before production") else empty end )
      end
    else empty end )
end'

validate_settings() { # validate_settings <staged file> <display name>
  local f="$1" name="${2:-$1}" out line errs=0
  [ -f "$f" ] || die 2 "managed-settings source not found: $f"
  check_encoding "$f" "$name"
  jq empty "$f" 2>/dev/null || die 2 "$name is not valid JSON (Kiro would reject it and deny every tool call)"
  out="$(jq -r "$JQ_VALIDATE" "$f" 2>&1)" || die 2 "jq validation program failed: $out"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      ERROR:*) printf '[%s] %s\n' "$SELF" "$line" >&2; errs=$((errs + 1)) ;;
      WARN:*)  warn "${line#WARN: }"; [ "$STRICT" = 1 ] && errs=$((errs + 1)) ;;
    esac
  done <<EOF
$out
EOF
  [ "$errs" -eq 0 ] || die 2 "refusing to deploy $name: $errs problem(s) found"
  log "validated $name: $(jq '.rules | length' "$f") rule(s), no allow effects, sha256=$(sha256_of "$f")"
}

stage_hooks() {
  local man="$HOOKS_SRC/SHA256SUMS" line name pin
  [ -f "$man" ] || die 2 "hook manifest not found: $man (hooks are never deployed without it)"
  mkdir -p "$STAGE/hooks" || die 1 "cannot create stage directory"
  cp "$man" "$STAGE/hooks/SHA256SUMS" || die 1 "cannot stage $man"
  if [ -n "$MANIFEST_PIN" ]; then
    pin="$(sha256_of "$STAGE/hooks/SHA256SUMS")"
    [ "$pin" = "$MANIFEST_PIN" ] || die 2 "SHA256SUMS hash $pin does not match the pinned value $MANIFEST_PIN"
    log "SHA256SUMS matches the pinned hash"
  else
    warn "no --manifest-sha256 pin: SHA256SUMS is trusted as delivered (protect the source package)"
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    printf '%s\n' "$line" | grep -Eq '^[0-9a-f]{64} [ *][A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?$' \
      || die 2 "malformed SHA256SUMS line: $line"
    name="$(printf '%s' "$line" | sed -E 's/^[0-9a-f]{64} [ *]//')"
    case "$name" in *..*|.*) die 2 "unsafe file name in SHA256SUMS: $name" ;; esac
    [ -f "$HOOKS_SRC/$name" ] || die 2 "file listed in SHA256SUMS is missing: $name"
    mkdir -p "$STAGE/hooks/$(dirname "$name")"
    cp "$HOOKS_SRC/$name" "$STAGE/hooks/$name" || die 1 "cannot stage $name"
    case "$name" in */*) ;; *.sh) DEPLOYABLE="${DEPLOYABLE}${name}
" ;; esac
  done < "$STAGE/hooks/SHA256SUMS"
  [ -n "$DEPLOYABLE" ] || die 2 "SHA256SUMS lists no hook scripts (*.sh)"
  ( cd "$STAGE/hooks" && shasum -a 256 -c SHA256SUMS ) || die 2 "hook hash verification FAILED - aborting, nothing deployed"
  log "hook hashes verified: $(printf '%s' "$DEPLOYABLE" | grep -c .) script(s)"
}

in_deployable() { printf '%s' "$DEPLOYABLE" | grep -qx -- "$1"; }

hook_commands() { jq -r '(.hooks // empty) | .. | objects | select(has("command")) | .command | strings' "$1"; }

# Every hook command must point to a hash-verified script under /opt/kiro/hooks (optionally run
# through "bash", "/bin/bash" or "/usr/bin/env bash").
validate_hook_json() { # validate_hook_json <staged file>
  local f="$1" cmd n=0 script
  jq empty "$f" 2>/dev/null || die 2 "$f is not valid JSON"
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    n=$((n + 1))
    script="$(printf '%s' "$cmd" | sed -nE "s#^((/usr/bin/env |/bin/)?bash )?${HOOK_CMD_PREFIX}/([A-Za-z0-9._-]+\.sh)( .*)?\$#\3#p")"
    [ -n "$script" ] || die 2 "$(basename "$f"): hook command is not under $HOOK_CMD_PREFIX: $cmd"
    in_deployable "$script" || die 2 "$(basename "$f"): hook command references $script, which is not in SHA256SUMS"
  done <<EOF
$(hook_commands "$f")
EOF
  [ "$n" -gt 0 ] || warn "$(basename "$f") contains no hook commands"
  log "validated $(basename "$f"): $n hook command(s), all hash-pinned"
}

# Rewrite /opt/kiro/hooks/<script> to the macOS hook directory in a staged copy. The default
# directory contains a space, so the path is wrapped in double quotes: this assumes Kiro passes
# the hook command to a shell (the official examples, such as "npx tsc --noEmit", are shell
# command lines). Verify on your Kiro version; if quoting is not honoured use --hooks-dest
# /opt/kiro/hooks, which needs no rewrite.
rewrite_hook_json() { # rewrite_hook_json <in> <out>
  local in="$1" out="$2" q="" cmd rest
  case "$HOOKS_DIR" in *" "*) q='"' ;; esac
  jq --arg d "$HOOKS_DIR" --arg q "$q" '
    if has("hooks") then
      .hooks |= walk(if type == "object" and has("command") and (.command | type) == "string"
                     then .command |= sub("^(?<p>((/usr/bin/env |/bin/)?bash )?)/opt/kiro/hooks/(?<n>[A-Za-z0-9._-]+)";
                                          "\(.p)\($q)\($d)/\(.n)\($q)")
                     else . end)
    else . end' "$in" > "$out" || die 2 "cannot rewrite hook paths in $(basename "$in")"
  jq empty "$out" 2>/dev/null || die 2 "rewritten $(basename "$in") is not valid JSON"
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    rest="${cmd#/usr/bin/env bash }"; rest="${rest#/bin/bash }"; rest="${rest#bash }"
    case "$rest" in
      "$q$HOOKS_DIR/"*) ;;
      *) die 2 "rewritten $(basename "$in") still has a hook command outside $HOOKS_DIR: $cmd" ;;
    esac
  done <<EOF
$(hook_commands "$out")
EOF
  log "rewrote hook commands in $(basename "$in") -> $q$HOOKS_DIR/<script>$q"
}

stage_user_files() {
  local src
  mkdir -p "$STAGE/user"
  for src in "$AGENT_SRC_NAME" "$V1_SRC_NAME"; do
    case "$USER_FILES:$src" in hooks:"$AGENT_SRC_NAME"|agent:"$V1_SRC_NAME") continue ;; esac
    [ -f "$HOOKS_SRC/$src" ] || die 2 "user file not found: $HOOKS_SRC/$src"
    if [ -f "$STAGE/hooks/$src" ]; then
      log "$src is covered by SHA256SUMS"
    else
      mkdir -p "$STAGE/hooks/$(dirname "$src")"
      cp "$HOOKS_SRC/$src" "$STAGE/hooks/$src" || die 1 "cannot stage $src"
      log "$src is not listed in SHA256SUMS; validating its structure instead"
    fi
    validate_hook_json "$STAGE/hooks/$src"
    rewrite_hook_json "$STAGE/hooks/$src" "$STAGE/user/$(basename "$src")"
    if [ -n "$REWRITE_OUT" ]; then
      mkdir -p "$REWRITE_OUT" && cp "$STAGE/user/$(basename "$src")" "$REWRITE_OUT/" || die 1 "cannot write $REWRITE_OUT"
    fi
  done
}

# ---------------------------------------------------------------------------------------------
# Deployment primitives
# ---------------------------------------------------------------------------------------------
ensure_root_dir() {
  local d="$1"
  if [ "$CHECK_ONLY" = 1 ]; then
    [ -d "$d" ] || { drift "missing directory $d"; return 0; }
    [ "$(owner_mode "$d")" = "root 755" ] || drift "$d is $(owner_mode "$d"), expected root 755"
    return 0
  fi
  [ ! -L "$d" ] || die 1 "refusing to use $d: it is a symlink"
  run "ensure directory $d (root:wheel 0755)" mkroot_dir "$d"
}
mkroot_dir() { mkdir -p "$1" && chown root:wheel "$1" && chmod 0755 "$1"; }

install_root_file() { # install_root_file <staged src> <dest> <mode>
  local src="$1" dst="$2" mode="$3" want have tmp
  want="$(sha256_of "$src")"
  have=""; [ -f "$dst" ] && have="$(sha256_of "$dst")"
  if [ "$CHECK_ONLY" = 1 ]; then
    [ -f "$dst" ] || { drift "missing $dst"; return 0; }
    [ "$have" = "$want" ] || drift "$dst content differs (sha256 $have, expected $want)"
    [ "$(owner_mode "$dst")" = "root ${mode#0}" ] || drift "$dst is $(owner_mode "$dst"), expected root ${mode#0}"
    [ "$IMMUTABLE" = 0 ] || has_flag "$dst" schg || drift "$dst does not have the schg flag"
    return 0
  fi
  if [ "$have" = "$want" ] && [ "$(owner_mode "$dst")" = "root ${mode#0}" ]; then
    log "unchanged: $dst (sha256=$want)"
    [ "$DRY_RUN" = 1 ] || has_flag "$dst" schg || set_flag schg "$dst"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then plan "install $dst (root:wheel $mode, sha256=$want)$( [ "$IMMUTABLE" = 1 ] && echo ', then chflags schg')"; return 0; fi
  [ -e "$dst" ] && clear_schg "$dst"
  tmp="$(dirname "$dst")/.$(basename "$dst").new.$$"
  install -o root -g wheel -m "$mode" "$src" "$tmp" || die 1 "cannot write $tmp"
  mv -f "$tmp" "$dst" || { rm -f "$tmp"; die 1 "cannot replace $dst"; }
  set_flag schg "$dst"
  log "installed: $dst (sha256=$want)"
}

install_user_file() { # install_user_file <user> <home> <staged src> <relative dest>
  local u="$1" h="$2" src="$3" rel="$4" dst want have
  dst="$h/$rel"; want="$(sha256_of "$src")"
  have=""; [ -f "$dst" ] && have="$(sha256_of "$dst" 2>/dev/null)"
  if [ "$CHECK_ONLY" = 1 ]; then
    [ "$have" = "$want" ] || drift "$dst missing or modified (user-owned; restored on the next run)"
    return 0
  fi
  if [ "$have" = "$want" ]; then log "unchanged: $dst"; return 0; fi
  if [ "$DRY_RUN" = 1 ]; then plan "write $dst as user $u (0644, sha256=$want) - user-owned, not tamper-resistant"; return 0; fi
  as_user "$u" sh -c 'umask 022; mkdir -p "$(dirname "$1")" && cat > "$1.new.$$" && mv -f "$1.new.$$" "$1"' sh "$dst" < "$src" \
    || die 1 "cannot write $dst as $u"
  log "installed for $u: $dst (sha256=$want)"
}

prepare_audit() { # prepare_audit <user> <home>
  local u="$1" h="$2" f info
  f="$h/$AUDIT_REL"
  if [ "$CHECK_ONLY" = 1 ]; then
    [ -f "$f" ] || { drift "audit log $f missing"; return 0; }
    [ "$IMMUTABLE" = 0 ] || has_flag "$f" "$AUDIT_FLAG" || drift "audit log $f does not have the $AUDIT_FLAG flag"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    if [ "$AUDIT_FLAG" = sappnd ]; then
      plan "create $f as user $u (0600) if absent, then (root) chflags sappnd: $u can append but cannot truncate, delete or clear the flag (the parent directory stays user-owned)"
    else
      plan "create $f as user $u (0600) if absent, then (root) chflags uappnd: blocks truncation, overwrite and deletion while set, but the OWNER can clear it (chflags nouappnd) - not protection against $u"
    fi
    return 0
  fi
  as_user "$u" sh -c 'umask 077; mkdir -p "$(dirname "$1")" && : >> "$1"' sh "$f" || die 1 "cannot create $f as $u"
  [ ! -L "$h/.kiro" ] && [ ! -L "$h/.kiro/audit" ] && [ ! -L "$f" ] && [ -f "$f" ] \
    || die 1 "refusing to set flags on $f: symlink or not a regular file"
  info="$(stat -f '%Su %l' "$f")"
  [ "$info" = "$u 1" ] || die 1 "refusing to set flags on $f: owner/link count is '$info', expected '$u 1'"
  # -h: if the path were swapped for a symlink after the check, flag the link, not its target.
  if has_flag "$f" "$AUDIT_FLAG"; then log "unchanged: $f ($AUDIT_FLAG)"
  elif [ "$IMMUTABLE" = 1 ]; then
    if chflags -h "$AUDIT_FLAG" "$f" 2>/dev/null; then
      log "append-only ($AUDIT_FLAG): $f"
      [ "$AUDIT_FLAG" = sappnd ] || log "note: uappnd is a user flag; $u can clear it. Use --audit-sappnd for a flag the owner cannot clear"
    else
      warn "chflags $AUDIT_FLAG failed for $f"
    fi
  fi
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------
case "$USER_FILES" in both|hooks|agent) ;; *) die 1 "--user-files must be both, hooks or agent" ;; esac
[ -n "$INSTALL_USER" ] && DEPLOY_HOOKS=1
[ -z "$AUDIT_USER" ] && [ -n "$INSTALL_USER" ] && AUDIT_USER="$INSTALL_USER"
for u in "$INSTALL_USER" "$AUDIT_USER"; do
  [ -z "$u" ] || valid_username "$u" || die 1 "invalid user name: $u"
done
[ -z "$REWRITE_OUT" ] || [ -n "$INSTALL_USER" ] || die 1 "--rewrite-out needs --install-user"

if [ "$DRY_RUN" = 1 ]; then
  log "DRY RUN - validation and planning only; no system changes"
elif [ "$CHECK_ONLY" = 1 ]; then
  log "CHECK - comparing deployed files with sources; no changes"
else
  [ "$(uname -s)" = "Darwin" ] || die 1 "this script targets macOS (use lockdown-linux.sh / lockdown-windows.ps1)"
  [ "$(id -u)" -eq 0 ] || die 1 "must run as root (use --dry-run for a non-root validation)"
  log "kern.securelevel=$(securelevel)$( [ "$IMMUTABLE" = 1 ] && echo ' (at 1 or higher, schg/sappnd can only be cleared from Recovery or single-user mode)')"
fi
[ -z "$PREFIX" ] || warn "TEST MODE: system paths are relocated under $PREFIX"
command -v jq >/dev/null 2>&1 || die 1 "jq is required (ships with macOS 15 and later as /usr/bin/jq; the hook scripts need it at runtime)"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/kiro-mdm.XXXXXX")" || die 1 "cannot create a stage directory"
chmod 0700 "$STAGE"

# Phase 1 - validate everything. Nothing is changed until all checks pass.
cp "$SETTINGS_SRC" "$STAGE/managed-settings.json" 2>/dev/null || die 2 "managed-settings source not found: $SETTINGS_SRC"
validate_settings "$STAGE/managed-settings.json" "$SETTINGS_SRC"
[ "$DEPLOY_HOOKS" = 1 ] && stage_hooks
UHOME=""; AHOME=""
if [ -n "$INSTALL_USER" ]; then
  stage_user_files
  UHOME="$(user_home "$INSTALL_USER")" || exit 1
fi
if [ -n "$AUDIT_USER" ]; then
  AHOME="$(user_home "$AUDIT_USER")" || exit 1
fi
log "all validation passed$( [ "$DRY_RUN" = 1 ] && echo '; planned actions follow' )"

# Phase 2 - apply.
# 1. Admin policy (primary control).
ensure_root_dir "$SETTINGS_DIR"
install_root_file "$STAGE/managed-settings.json" "$SETTINGS_DEST" 0644
[ "$DRY_RUN" = 1 ] || [ "$CHECK_ONLY" = 1 ] || log "restart Kiro (IDE and CLI) to apply the new policy"

# 2. Hook scripts (optional).
if [ "$DEPLOY_HOOKS" = 1 ]; then
  ensure_root_dir "$(dirname "$HOOKS_DEST")"
  ensure_root_dir "$HOOKS_DEST"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    install_root_file "$STAGE/hooks/$s" "$HOOKS_DEST/$s" 0755
  done <<EOF
$DEPLOYABLE
EOF
  if [ -d "$HOOKS_DEST" ]; then
    for f in "$HOOKS_DEST"/*; do
      [ -e "$f" ] || continue
      in_deployable "$(basename "$f")" || warn "unexpected file in $HOOKS_DEST (not in SHA256SUMS): $(basename "$f")"
    done
  fi
fi

# 3. Per-user files (optional; user-owned, convenience only).
if [ -n "$INSTALL_USER" ]; then
  case "$USER_FILES" in both|hooks) install_user_file "$INSTALL_USER" "$UHOME" "$STAGE/user/banking-guards.json" ".kiro/hooks/banking-guards.json" ;; esac
  case "$USER_FILES" in both|agent) install_user_file "$INSTALL_USER" "$UHOME" "$STAGE/user/$AGENT_SRC_NAME" ".kiro/agents/banking-secure.json" ;; esac
  [ "$USER_FILES" = both ] && log "note: CLI sessions using banking-secure may run the guards twice (agent hooks + global v1 hooks)"
  log "note: the files in ~$INSTALL_USER/.kiro are user-owned convenience copies; the enforced policy is $SETTINGS_DEST"
fi

# 4. Append-only hook audit log (optional; supplementary to Kiro prompt logging).
if [ -n "$AUDIT_USER" ]; then
  prepare_audit "$AUDIT_USER" "$AHOME"
fi

if [ "$CHECK_ONLY" = 1 ]; then
  [ "$DRIFT" -eq 0 ] && { log "compliant: no drift"; exit 0; }
  log "drift detected: $DRIFT item(s); re-run without --check to restore"
  exit 3
fi
log "done ($WARNINGS warning(s)). Managed settings: $SETTINGS_DEST$( [ "$DEPLOY_HOOKS" = 1 ] && echo "; hooks: $HOOKS_DEST")"
exit 0
