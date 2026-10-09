#!/usr/bin/env bash
# lockdown-linux.sh - Reference MDM job for Linux / VDI Kiro clients (Kiro IDE 1.x, Kiro CLI 2.x).
# MAS TRM 9.1 (access), 11.1 (data), 11.3 (system security), 12.2 (monitoring).
# Last verified against kiro.dev docs: 2026-10-08.
#
# PRIMARY CONTROL (always):
#   Deploys the admin policy file to the OFFICIAL Kiro path /etc/kiro/managed-settings.json
#   (root:root 0644, chattr +i where the filesystem supports it). Kiro IDE and CLI both read this
#   file at start-up; admin rules may only use deny/ask, and deny wins over every other scope,
#   including --trust-all-tools and /tools trust-all. Enforcement is client-side: a user with
#   root on the machine can remove the file, so developers must not have root.
#
# OPTIONAL (defense in depth):
#   --hooks              verify agent-hooks/SHA256SUMS, then deploy the listed hook scripts to
#                        /opt/kiro/hooks (root:root 0755, chattr +i). Aborts on any mismatch.
#   --install-user USER  install the v1 hook file into ~USER/.kiro/hooks/ and the banking-secure
#                        agent into ~USER/.kiro/agents/. Kiro loads agents only from ~/.kiro/agents
#                        and a trusted workspace's .kiro/agents (never from /opt), and global v1
#                        hook files only from ~/.kiro/hooks. These locations are user-owned: the
#                        developer can edit or delete the files (Kiro's hardcoded "always ask" rule
#                        only stops the AGENT from changing them silently). The guarantee comes
#                        from managed-settings, not from these files; --check reports their drift.
#   --audit-user USER    prepare ~USER/.kiro/audit/kiro-hooks.jsonl as a user-owned file with
#                        chattr +a (set by root): the user can append but not truncate, overwrite or
#                        delete it, and cannot clear +a. The user still owns the directory and can
#                        rename it and start a new log, so this log is supplementary evidence only;
#                        Kiro prompt logging (server side) is the audit record.
#
# Order of work: EVERYTHING is validated first (policy JSON, SHA256SUMS, user hook files, user
# accounts); only then is anything installed. A refusal (exit 2) leaves the machine unchanged.
# Re-runnable (idempotent): unchanged files are left alone, changed or deleted files are restored
# and re-locked. Schedule it from the MDM agent, cron or a systemd timer. Use --check as the MDM
# "detection" step (exit 3 on drift). No network calls are made.
#
# Exit codes: 0 ok | 1 usage/environment error | 2 validation refused (JSON, policy, hashes) |
#             3 drift detected (--check only)
set -uo pipefail
umask 022

SELF="lockdown-linux"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------------------------------
# Configuration (flags override environment variables)
# ---------------------------------------------------------------------------------------------
SETTINGS_SRC="${KIRO_MANAGED_SETTINGS_SRC:-$REPO_DIR/managed-settings/managed-settings.banking.json}"
HOOKS_SRC="${KIRO_HOOKS_SRC:-$REPO_DIR/agent-hooks}"
MANIFEST_PIN="${KIRO_HOOKS_MANIFEST_SHA256:-}"   # optional out-of-band pin of SHA256SUMS itself
DEPLOY_HOOKS="${KIRO_DEPLOY_HOOKS:-0}"
INSTALL_USER="${KIRO_INSTALL_USER:-}"
USER_FILES="${KIRO_USER_FILES:-both}"             # both | hooks | agent
AUDIT_USER="${KIRO_AUDIT_USER:-}"
USER_HOME_OVERRIDE="${KIRO_USER_HOME:-}"          # test only
PREFIX="${KIRO_ROOT_PREFIX:-}"                    # test only: relocate every system path
DRY_RUN="${KIRO_DRY_RUN:-0}"
STRICT="${KIRO_STRICT:-0}"
IMMUTABLE=1
CHECK_ONLY=0

usage() {
  cat <<'EOF'
Usage: sudo lockdown-linux.sh [options]

  --dry-run              Validate JSON, policy and hashes and print the planned actions.
                         Makes no system changes; does not need root (safe for CI).
  --check                Compare the deployed files with the sources; exit 3 on drift.
  --settings FILE        managed-settings source (default managed-settings/managed-settings.banking.json)
  --option-b             Shortcut for --settings managed-settings/managed-settings.option-b.json
  --hooks                Also deploy hash-verified hook scripts to /opt/kiro/hooks
  --hooks-src DIR        Hook source directory (default agent-hooks/)
  --manifest-sha256 HEX  Expected SHA-256 of SHA256SUMS (pin delivered out of band by the MDM)
  --install-user USER    Install the v1 hook file and the agent for USER (implies --hooks)
  --user-files WHICH     both | hooks | agent (default both)
  --audit-user USER      Prepare USER's append-only hook audit log (default: the install user)
  --no-immutable         Do not set chattr +i / +a (use on filesystems without attribute support,
                         such as tmpfs, overlay or NFS; --check then skips the attribute checks)
  --strict               Treat validation warnings (for example placeholder values) as errors
  --user-home DIR        TEST ONLY: home directory to use for USER
  --prefix DIR           TEST ONLY: prepend DIR to every system path
  -h, --help             Show this help

Environment equivalents: KIRO_MANAGED_SETTINGS_SRC, KIRO_HOOKS_SRC, KIRO_HOOKS_MANIFEST_SHA256,
KIRO_DEPLOY_HOOKS=1, KIRO_INSTALL_USER, KIRO_USER_FILES, KIRO_AUDIT_USER, KIRO_DRY_RUN=1,
KIRO_STRICT=1, KIRO_USER_HOME, KIRO_ROOT_PREFIX.
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
    --manifest-sha256) MANIFEST_PIN="${2:?--manifest-sha256 needs a hash}"; shift ;;
    --install-user) INSTALL_USER="${2:?--install-user needs a user}"; shift ;;
    --user-files) USER_FILES="${2:?--user-files needs both|hooks|agent}"; shift ;;
    --audit-user) AUDIT_USER="${2:?--audit-user needs a user}"; shift ;;
    --no-immutable) IMMUTABLE=0 ;;
    --strict) STRICT=1 ;;
    --user-home) USER_HOME_OVERRIDE="${2:?--user-home needs a directory}"; shift ;;
    --prefix) PREFIX="${2:?--prefix needs a directory}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[$SELF] ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

# Official Kiro path (https://kiro.dev/docs/enterprise/governance/permissions/) and repo layout.
SETTINGS_DIR="$PREFIX/etc/kiro"
SETTINGS_DEST="$SETTINGS_DIR/managed-settings.json"
HOOKS_BASE="$PREFIX/opt/kiro"
HOOKS_DEST="$HOOKS_BASE/hooks"
HOOK_CMD_PREFIX="/opt/kiro/hooks"                 # path referenced by the shipped hook/agent JSON
AUDIT_REL=".kiro/audit/kiro-hooks.jsonl"          # matches the audit-logger.sh default
AGENT_SRC_NAME="banking-secure.agent.json"
V1_SRC_NAME="hooks/banking-guards.json"

WARNINGS=0
DRIFT=0
STAGE=""
DEPLOYABLE=""                                     # newline-separated hook script names

# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------
log()  { printf '[%s] %s\n' "$SELF" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$SELF" "$*" >&2; WARNINGS=$((WARNINGS + 1)); }
die()  { local rc="$1"; shift; printf '[%s] ERROR: %s\n' "$SELF" "$*" >&2; exit "$rc"; }
drift() { printf '[%s] DRIFT: %s\n' "$SELF" "$*"; DRIFT=$((DRIFT + 1)); }
plan() { log "[dry-run] would $*"; }

# run <description> <command...> : executes, or only prints the plan in --dry-run.
run() {
  local desc="$1"; shift
  if [ "$DRY_RUN" = 1 ]; then plan "$desc"; return 0; fi
  "$@" || die 1 "failed to $desc"
}

cleanup() { [ -n "$STAGE" ] && [ -d "$STAGE" ] && rm -rf "$STAGE"; }
trap cleanup EXIT

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

valid_username() { printf '%s' "$1" | grep -Eq '^[a-z_][a-z0-9_.-]{0,31}$'; }

user_home() {
  local u="$1" h=""
  if [ -n "$USER_HOME_OVERRIDE" ]; then printf '%s' "$USER_HOME_OVERRIDE"; return 0; fi
  [ -z "$PREFIX" ] || die 1 "--prefix is test-only and requires --user-home for user operations"
  if command -v getent >/dev/null 2>&1; then h="$(getent passwd "$u" | cut -d: -f6)"; fi
  [ -n "$h" ] || die 1 "user '$u' not found (getent passwd)"
  printf '%s' "$h"
}

# as_user <user> <command...>: run a command with the user's privileges (no root writes into a
# user-owned directory, which avoids symlink tricks). Root only; skipped in --dry-run.
as_user() {
  local u="$1"; shift
  if [ "$(id -un)" = "$u" ]; then "$@"; return $?; fi
  if command -v runuser >/dev/null 2>&1; then runuser -u "$u" -- "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo -n -u "$u" -- "$@"
  else die 1 "need runuser or sudo to act as $u"; fi
}

has_attr() { # has_attr <file> <letter> : true if lsattr shows the attribute
  command -v lsattr >/dev/null 2>&1 || return 1
  lsattr -d -- "$1" 2>/dev/null | awk '{print $1}' | grep -q "$2"
}
set_attr() { # set_attr <+i|+a|-i|-a> <file>; never fatal (tmpfs/overlay/NFS have no attributes)
  [ "$IMMUTABLE" = 1 ] || return 0
  if ! command -v chattr >/dev/null 2>&1; then warn "chattr not found (install e2fsprogs); $2 relies on ownership and mode only"; return 0; fi
  chattr "$1" -- "$2" 2>/dev/null || { case "$1" in +*) warn "chattr $1 not supported for $2 (filesystem?); relying on ownership and mode";; esac; }
}

# ---------------------------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------------------------
check_encoding() { # refuse a UTF-8 BOM or UTF-16 (Kiro requires UTF-8 without BOM)
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

# Copy the manifest and the files it lists into a private stage directory, then verify there
# (verifying the staged copy closes the window between check and install).
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
  if command -v sha256sum >/dev/null 2>&1; then
    ( cd "$STAGE/hooks" && sha256sum -c SHA256SUMS ) || die 2 "hook hash verification FAILED - aborting, nothing deployed"
  else
    ( cd "$STAGE/hooks" && shasum -a 256 -c SHA256SUMS ) || die 2 "hook hash verification FAILED - aborting, nothing deployed"
  fi
  log "hook hashes verified: $(printf '%s' "$DEPLOYABLE" | grep -c .) script(s)"
}

in_deployable() { printf '%s' "$DEPLOYABLE" | grep -qx -- "$1"; }

# Every hook command in a user JSON file must point to a hash-verified script under /opt/kiro/hooks
# (optionally run through "bash", "/bin/bash" or "/usr/bin/env bash").
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
$(jq -r '(.hooks // empty) | .. | objects | select(has("command")) | .command | strings' "$f")
EOF
  [ "$n" -gt 0 ] || warn "$(basename "$f") contains no hook commands"
  log "validated $(basename "$f"): $n hook command(s), all hash-pinned"
}

stage_user_files() {
  local src
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
  done
}

# ---------------------------------------------------------------------------------------------
# Deployment primitives
# ---------------------------------------------------------------------------------------------
ensure_root_dir() { # ensure_root_dir <dir>
  local d="$1"
  if [ "$CHECK_ONLY" = 1 ]; then
    [ -d "$d" ] || { drift "missing directory $d"; return 0; }
    [ "$(stat -c '%U %a' "$d")" = "root 755" ] || drift "$d is $(stat -c '%U %a' "$d"), expected root 755"
    return 0
  fi
  [ ! -L "$d" ] || die 1 "refusing to use $d: it is a symlink"
  run "ensure directory $d (root:root 0755)" mkroot_dir "$d"
}
mkroot_dir() { install -d -m 0755 "$1" && chown root:root "$1" && chmod 0755 "$1"; }

# install_root_file <staged src> <dest> <mode>: idempotent, atomic, re-locks.
install_root_file() {
  local src="$1" dst="$2" mode="$3" want have tmp
  want="$(sha256_of "$src")"
  have=""; [ -f "$dst" ] && have="$(sha256_of "$dst")"
  if [ "$CHECK_ONLY" = 1 ]; then
    [ -f "$dst" ] || { drift "missing $dst"; return 0; }
    [ "$have" = "$want" ] || drift "$dst content differs (sha256 $have, expected $want)"
    [ "$(stat -c '%U %a' "$dst")" = "root ${mode#0}" ] || drift "$dst is $(stat -c '%U %a' "$dst"), expected root ${mode#0}"
    [ "$IMMUTABLE" = 0 ] || has_attr "$dst" i || drift "$dst is not immutable (chattr +i)"
    return 0
  fi
  if [ "$have" = "$want" ] && [ "$(stat -c '%U %a' "$dst" 2>/dev/null)" = "root ${mode#0}" ]; then
    log "unchanged: $dst (sha256=$want)"
    [ "$DRY_RUN" = 1 ] || has_attr "$dst" i || set_attr +i "$dst"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then plan "install $dst (root:root $mode, sha256=$want)$( [ "$IMMUTABLE" = 1 ] && echo ', then chattr +i')"; return 0; fi
  [ -e "$dst" ] && set_attr -i "$dst"
  tmp="$(dirname "$dst")/.$(basename "$dst").new.$$"
  install -o root -g root -m "$mode" "$src" "$tmp" || die 1 "cannot write $tmp"
  mv -f "$tmp" "$dst" || { rm -f "$tmp"; die 1 "cannot replace $dst (immutable flag still set?)"; }
  set_attr +i "$dst"
  log "installed: $dst (sha256=$want)"
}

# install_user_file <user> <home> <staged src> <relative dest>: written WITH THE USER'S PRIVILEGES.
install_user_file() {
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
    [ "$IMMUTABLE" = 0 ] || has_attr "$f" a || drift "audit log $f is not append-only (chattr +a)"
    return 0
  fi
  if [ "$DRY_RUN" = 1 ]; then
    plan "create $f as user $u (0600) if absent, then (root) chattr +a: $u can append but not truncate, overwrite, rename or delete the file (the parent directory stays user-owned; supplementary evidence only)"
    return 0
  fi
  as_user "$u" sh -c 'umask 077; mkdir -p "$(dirname "$1")" && : >> "$1"' sh "$f" || die 1 "cannot create $f as $u"
  # Root acts on a path inside a user-owned directory: refuse symlinks, foreign owners and hard
  # links. A residual race remains; run this at provisioning time or while the user is logged out.
  [ ! -L "$h/.kiro" ] && [ ! -L "$h/.kiro/audit" ] && [ ! -L "$f" ] && [ -f "$f" ] \
    || die 1 "refusing to set attributes on $f: symlink or not a regular file"
  info="$(stat -c '%U %h' -- "$f")"
  [ "$info" = "$u 1" ] || die 1 "refusing to set attributes on $f: owner/link count is '$info', expected '$u 1'"
  if has_attr "$f" a; then log "unchanged: $f (append-only)"; else set_attr +a "$f"; has_attr "$f" a && log "append-only: $f"; fi
}

# ---------------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------------
case "$USER_FILES" in both|hooks|agent) ;; *) die 1 "--user-files must be both, hooks or agent" ;; esac
[ -n "$INSTALL_USER" ] && DEPLOY_HOOKS=1                 # user files are useless without the scripts
[ -z "$AUDIT_USER" ] && [ -n "$INSTALL_USER" ] && AUDIT_USER="$INSTALL_USER"
for u in "$INSTALL_USER" "$AUDIT_USER"; do
  [ -z "$u" ] || valid_username "$u" || die 1 "invalid user name: $u"
done

if [ "$DRY_RUN" = 1 ]; then
  log "DRY RUN - validation and planning only; no system changes"
elif [ "$CHECK_ONLY" = 1 ]; then
  log "CHECK - comparing deployed files with sources; no changes"
else
  [ "$(uname -s)" = "Linux" ] || die 1 "this script targets Linux (use lockdown-macos.sh / lockdown-windows.ps1)"
  [ "$(id -u)" -eq 0 ] || die 1 "must run as root (use --dry-run for a non-root validation)"
fi
[ -z "$PREFIX" ] || warn "TEST MODE: system paths are relocated under $PREFIX"
command -v jq >/dev/null 2>&1 || die 1 "jq is required (validation here and the hook scripts at runtime)"

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
  ensure_root_dir "$HOOKS_BASE"
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
  case "$USER_FILES" in both|hooks) install_user_file "$INSTALL_USER" "$UHOME" "$STAGE/hooks/$V1_SRC_NAME" ".kiro/hooks/banking-guards.json" ;; esac
  case "$USER_FILES" in both|agent) install_user_file "$INSTALL_USER" "$UHOME" "$STAGE/hooks/$AGENT_SRC_NAME" ".kiro/agents/banking-secure.json" ;; esac
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
