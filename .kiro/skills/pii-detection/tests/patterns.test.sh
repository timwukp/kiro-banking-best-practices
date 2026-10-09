#!/usr/bin/env bash
# patterns.test.sh - regression tests for the pii-detection skill's documented patterns.
#
#   bash .kiro/skills/pii-detection/tests/patterns.test.sh
#
# What it checks:
#   1. Every pattern in the ERE block of references/singapore-pii-patterns.md, run with
#      `grep -E` (BSD/macOS or GNU), against the positive and negative cases in
#      fixtures/pattern-cases.tsv.
#   2. The same cases against the PCRE block (run with perl, if installed; skipped otherwise).
#   3. Coverage: the ERE and PCRE blocks list the same ids, and every id has at least one
#      positive and one negative case.
#   4. Consistency: the pattern blocks in SKILL.md and in
#      mas-compliance-review/references/pdpa-checklist.md (if present) are identical to the
#      reference for every id they list.
#   5. NRIC/FIN checksum and Luhn checks for the documented example values, and the masking
#      standard (S1234567D -> S****567D). Old, inconsistent masks must not reappear.
#
# Needs bash 3.2+ (macOS default) and grep, awk, sort, cmp, seq, mktemp; perl is optional.
# Tested with BSD grep (macOS) and ugrep; GNU grep follows the same POSIX ERE rules.
# No network. Fixtures are fed to grep/perl as data only; nothing from them is executed.
# Prints PASS/FAIL/SKIP counts; exit status 1 if any check fails.

set -u
export LC_ALL=C   # keep [A-Z] ASCII-only in every grep implementation

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$HERE/.." && pwd)"
REF="$SKILL_DIR/references/singapore-pii-patterns.md"
SKILL_MD="$SKILL_DIR/SKILL.md"
PDPA="$SKILL_DIR/../mas-compliance-review/references/pdpa-checklist.md"
CASES="$HERE/fixtures/pattern-cases.tsv"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pii-pattern-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS + 1)); }
bad()  { FAIL=$((FAIL + 1)); echo "FAIL: $*"; }
skip() { SKIP=$((SKIP + 1)); echo "SKIP: $*"; }

for f in "$REF" "$SKILL_MD" "$CASES"; do
  [ -f "$f" ] || { echo "patterns.test: missing $f"; exit 1; }
done

# Token- and key-shaped values are assembled here at runtime, never committed.
AWS_EXAMPLE_KEY="AKIAIOSFODNN7EXAMPLE"            # AWS documentation example access key ID
ASIA_KEY="ASIA${AWS_EXAMPLE_KEY#AKIA}"             # same example in temporary-credential form
PEM="-----""BEGIN"
GHP="gh""p_"; GHO="gh""o_"; GHPAT="github""_pat_"
TOK36="$(printf 'aB3%.0s' $(seq 1 12))"            # 36 characters
TOK82="$(printf 'aB3_%.0s' $(seq 1 20))aB"         # 82 characters

expand() { # replace {{...}} placeholders in a fixture value
  local s="$1"
  s="${s//\{\{PEM\}\}/$PEM}"
  s="${s//\{\{GHPAT\}\}/$GHPAT}"
  s="${s//\{\{GHP\}\}/$GHP}"
  s="${s//\{\{GHO\}\}/$GHO}"
  s="${s//\{\{TOK36\}\}/$TOK36}"
  s="${s//\{\{TOK82\}\}/$TOK82}"
  s="${s//\{\{ASIA\}\}/$ASIA_KEY}"
  printf '%s' "$s"
}

extract_block() { # file kind(pcre|ere) -> "id flags pattern" lines between the markers
  awk -v s="<!-- pii-patterns:$2:start -->" -v e="<!-- pii-patterns:$2:end -->" '
    $0 == s { on = 1; next }
    $0 == e { on = 0 }
    on && !/^```/ && !/^#/ && NF { print }
  ' "$1"
}

get_entry() { # block-file id -> sets FLAGS and PAT; returns 1 if the id is absent
  local id f p
  while read -r id f p; do
    if [ "$id" = "$2" ]; then FLAGS="$f"; PAT="$p"; return 0; fi
  done < "$1"
  return 1
}

ere_match() { # flags pattern input -> 0 match, 1 no match, 2 error
  # The pattern is passed with POSIX -f (a pattern file), not -e: some grep implementations
  # (for example ugrep) parse an argument starting with "---" as an option even after -e.
  local opt="-Eq"
  [ "$1" = "i" ] && opt="-Eqi"
  printf '%s\n' "$2" > "$WORK/pattern"
  printf '%s\n' "$3" | grep "$opt" -f "$WORK/pattern" 2>/dev/null
}

pcre_match() { # flags pattern input -> 0 match, 1 no match, other = error
  P_FLAGS="$1" P_PAT="$2" P_IN="$3" perl -e '
    my $re = $ENV{P_FLAGS} eq "i" ? qr/$ENV{P_PAT}/i : qr/$ENV{P_PAT}/;
    exit($ENV{P_IN} =~ $re ? 0 : 1);' 2>/dev/null
}

extract_block "$REF" ere  > "$WORK/ere"
extract_block "$REF" pcre > "$WORK/pcre"
[ -s "$WORK/ere" ]  || { echo "patterns.test: no ERE block found in $REF"; exit 1; }
[ -s "$WORK/pcre" ] || { echo "patterns.test: no PCRE block found in $REF"; exit 1; }

echo "== coverage"
awk '{print $1}' "$WORK/ere"  | sort > "$WORK/ere.ids"
awk '{print $1}' "$WORK/pcre" | sort > "$WORK/pcre.ids"
if cmp -s "$WORK/ere.ids" "$WORK/pcre.ids"; then ok; else bad "ERE and PCRE blocks list different ids"; fi
while read -r id; do
  if awk -F'\t' -v id="$id" '$1 == "match" && $2 == id {f=1} END {exit !f}' "$CASES"; then ok; else bad "$id: no positive fixture"; fi
  if awk -F'\t' -v id="$id" '$1 == "nomatch" && $2 == id {f=1} END {exit !f}' "$CASES"; then ok; else bad "$id: no negative fixture"; fi
done < "$WORK/ere.ids"

HAVE_PERL=0
command -v perl >/dev/null 2>&1 && HAVE_PERL=1

echo "== fixtures (ERE with grep -E; PCRE with perl)"
[ "$HAVE_PERL" = 1 ] || skip "perl not found: PCRE patterns not executed"
while IFS=$'\t' read -r expect id input; do
  case "$expect" in ''|\#*) continue ;; esac
  case "$expect" in match) want=0 ;; nomatch) want=1 ;; *) bad "bad expect value '$expect' for $id"; continue ;; esac
  value="$(expand "$input")"
  for kind in ere pcre; do
    [ "$kind" = pcre ] && [ "$HAVE_PERL" = 0 ] && continue
    if ! get_entry "$WORK/$kind" "$id"; then bad "$kind: unknown pattern id '$id'"; continue; fi
    if [ "$kind" = ere ]; then ere_match "$FLAGS" "$PAT" "$value"; else pcre_match "$FLAGS" "$PAT" "$value"; fi
    rc=$?
    if [ "$rc" -gt 1 ]; then bad "$kind $id: pattern error (rc=$rc)"
    elif [ "$rc" = "$want" ]; then ok
    else bad "$kind $id: expected $expect for: $input"
    fi
  done
done < "$CASES"

echo "== consistency with SKILL.md and pdpa-checklist.md"
check_copy() { # file label
  local n=0 id f p
  extract_block "$1" pcre > "$WORK/copy"
  if [ ! -s "$WORK/copy" ]; then bad "$2: no pii-patterns:pcre block"; return; fi
  while read -r id f p; do
    n=$((n + 1))
    if ! get_entry "$WORK/pcre" "$id"; then bad "$2: id '$id' not in the reference"; continue; fi
    if [ "$f" = "$FLAGS" ] && [ "$p" = "$PAT" ]; then ok; else bad "$2: '$id' differs from the reference"; fi
  done < "$WORK/copy"
  [ "$n" -gt 0 ] || bad "$2: empty pattern block"
}
check_copy "$SKILL_MD" "SKILL.md"
if [ -f "$PDPA" ]; then check_copy "$PDPA" "pdpa-checklist.md"; else skip "pdpa-checklist.md not present"; fi

echo "== NRIC/FIN checksum"
nric_ok() { # S1234567D -> 0 if the check letter is valid
  local id="$1" p d sum=0 i r table letter
  p="${id:0:1}"; d="${id:1:7}"
  case "$d" in *[!0-9]*|'') return 1 ;; esac
  [ "${#d}" -eq 7 ] || return 1
  set -- 2 7 6 5 4 3 2
  for i in 0 1 2 3 4 5 6; do sum=$((sum + ${d:$i:1} * $1)); shift; done
  case "$p" in T|G) sum=$((sum + 4)) ;; M) sum=$((sum + 3)) ;; esac
  r=$((sum % 11))
  case "$p" in
    S|T) table="JZIHGFEDCBA"; letter="${table:$r:1}" ;;
    F|G) table="XWUTRQPNMLK"; letter="${table:$r:1}" ;;
    M)   table="KLJNPQRTUWX"; letter="${table:$((10 - r)):1}" ;;   # M table is indexed [10 - r]
    *)   return 1 ;;
  esac
  [ "${id:8:1}" = "$letter" ]
}
for v in S1234567D T1234567J F1234567N G1234567X M1234567K; do
  if nric_ok "$v"; then ok; else bad "checksum: $v should be valid"; fi
done
for v in S1234567A T1234567D F1234567X G1234567N M1234567X; do
  if nric_ok "$v"; then bad "checksum: $v should be invalid"; else ok; fi
done

echo "== Luhn"
luhn_ok() { # card number with optional spaces/dashes -> 0 if Luhn-valid
  local n="${1//[ -]/}" sum=0 i digit pos=0
  case "$n" in *[!0-9]*|'') return 1 ;; esac
  i=${#n}
  while [ "$i" -gt 0 ]; do
    i=$((i - 1)); digit=${n:$i:1}
    if [ $((pos % 2)) -eq 1 ]; then digit=$((digit * 2)); [ "$digit" -gt 9 ] && digit=$((digit - 9)); fi
    sum=$((sum + digit)); pos=$((pos + 1))
  done
  [ $((sum % 10)) -eq 0 ]
}
for v in 4111111111111111 4222222222222 4111111111111111110 5555555555554444 5105105105105100 \
         2223003122003222 2221000000000009 2720999999999996 378282246310005 371449635398431; do
  if luhn_ok "$v"; then ok; else bad "luhn: $v should be valid"; fi
done
for v in 4111111111111112 5555555555554445 378282246310006; do
  if luhn_ok "$v"; then bad "luhn: $v should be invalid"; else ok; fi
done

echo "== masking standard"
mask_nric() { printf '%s****%s' "${1:0:1}" "${1: -4}"; }
[ "$(mask_nric S1234567D)" = 'S****567D' ] && ok || bad "mask_nric S1234567D"
[ "$(mask_nric M1234567K)" = 'M****567K' ] && ok || bad "mask_nric M1234567K"
if grep -q -F 'S****567D' "$SKILL_MD" "$REF"; then ok; else bad "masking standard S****567D not documented"; fi
for old in 'S1****D' 'S*****7D' "{nric[:2]}****{nric[-1]}" "'*' * 5"; do
  if grep -r -q -F --exclude=patterns.test.sh -- "$old" "$SKILL_DIR/.." 2>/dev/null; then bad "old mask '$old' still present under .kiro/skills"; else ok; fi
done

echo
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
