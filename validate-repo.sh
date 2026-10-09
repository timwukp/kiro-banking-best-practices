#!/bin/bash
# Repository Validation Script
# v1.9 - October 2026
#
# Run it before opening a pull request; CI (.github/workflows/validate.yml) runs it too.
# READ-ONLY: it never creates, changes or deletes files and makes no network calls.
# Works with bash 3.2+ (macOS default) and BSD or GNU grep/sed/awk.
#
# Usage:  ./validate-repo.sh            (from any directory; it switches to the repo root)
# Exit:   1 if any ERROR was found, 0 otherwise. WARNINGS are reported but do not fail.

cd "$(dirname "$0")" || exit 1

ERRORS=0
WARNINGS=0

error() { echo "  ERROR: $1"; ERRORS=$((ERRORS + 1)); }
warn()  { echo "  WARNING: $1"; WARNINGS=$((WARNINGS + 1)); }
pass()  { echo "  PASS: $1"; }
indent() { sed 's/^/    /'; }

echo "================================================"
echo "  AWS Kiro in FSI Best Practices - Repo Validator"
echo "================================================"
echo ""

# ─── CHECK 1: Required files ─────────────────────────
echo "[1/8] Checking required files..."
required_files=(
    ".gitignore"
    "LICENSE"
    "README.md"
    "AGENTS.md"
    "QUICK-REFERENCE.md"
    "Kiro-Agentic-SDLC-Banking-Best-Practices.md"
    "Kiro-Banking-Best-Practices-Part2.md"
    "Banking-Skills-Development-Guide.md"
    "CONTRIBUTING.md"
    "CHANGELOG.md"
    "CLAUDE.md"
    "SECURITY.md"
    "managed-settings/README.md"
    "agent-hooks/README.md"
)

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        error "Required file missing: $file"
    else
        pass "$file exists"
    fi
done
echo ""

# ─── CHECK 2: No PDFs in git ─────────────────────────
echo "[2/8] Checking for PDF files in git tracking..."
PDFS="$(git ls-files 2>/dev/null | grep -iE '\.(pdf)$')"
if [ -n "$PDFS" ]; then
    error "PDF files found in git tracking:"
    echo "$PDFS" | indent
else
    pass "No PDF files tracked"
fi
echo ""

# ─── CHECK 3: No .kiro private config in git (skills + steering samples ARE allowed) ───
echo "[3/8] Checking for .kiro private config files in git tracking..."
KIRO_PRIVATE="$(git ls-files 2>/dev/null | grep -E '\.kiro/(specs|hooks|settings)/')"
if [ -n "$KIRO_PRIVATE" ]; then
    error ".kiro private config files found in git tracking:"
    echo "$KIRO_PRIVATE" | indent
else
    pass "No .kiro private config files tracked (skills + steering are allowed)"
fi
echo ""

# ─── CHECK 4: PII and secrets scanning ───────────────
# Scope: root *.md and *.sh, kiro-docs/, .kiro/, cdk/, agent-hooks/, managed-settings/, mdm/,
# security-tests/, diagrams/ and .github/. Build output and dependencies (node_modules/,
# cdk.out/, build/) and .git/ are skipped; binary files are skipped (-I).
# Documented exclusions (they document or assemble detection signatures on purpose):
#   .kiro/skills/pii-detection/   the PII skill, its reference patterns and its tests/fixtures
#   agent-hooks/tests/fixtures/   hook regression fixtures
# AWS key IDs are scanned everywhere; lines containing EXAMPLE/example are ignored
# (AKIAIOSFODNN7EXAMPLE is the AWS documentation placeholder).
echo "[4/8] Scanning for PII and secrets..."

SCAN_PATHS=()
for p in *.md *.sh kiro-docs .kiro cdk agent-hooks managed-settings mdm security-tests diagrams .github; do
    [ -e "$p" ] && SCAN_PATHS+=("$p")
done
GREP_EXCLUDES=(--exclude-dir=node_modules --exclude-dir=cdk.out --exclude-dir=build --exclude-dir=.git)
EXCLUDED_PATHS='^(\./)?(\.kiro/skills/pii-detection/|agent-hooks/tests/fixtures/)'

scan() { # scan <ERE>: file:line:text for every match in SCAN_PATHS
    grep -r -n -I -E "${GREP_EXCLUDES[@]}" -e "$1" -- "${SCAN_PATHS[@]}" 2>/dev/null
}
not_excluded() { grep -v -E "$EXCLUDED_PATHS"; }

# AWS access key IDs
AKIA_HITS="$(scan 'AKIA[0-9A-Z]{16}' | grep -v 'EXAMPLE' | grep -v 'example')"
if [ -n "$AKIA_HITS" ]; then
    error "Potential real AWS access key found!"
    echo "$AKIA_HITS" | cut -d: -f1-2 | head -5 | indent
else
    pass "No real AWS access keys detected"
fi

# Private keys (any PEM private-key header: PKCS#8, RSA, EC, DSA, OPENSSH, ENCRYPTED, PGP)
KEY_HITS="$(scan '-----BEGIN[A-Z0-9 ]*PRIVATE KEY' | not_excluded)"
if [ -n "$KEY_HITS" ]; then
    error "Private key material found:"
    echo "$KEY_HITS" | cut -d: -f1-2 | head -5 | indent
else
    pass "No private key material detected"
fi

# Email addresses (warning). Ignored: example/placeholder/noreply addresses, badge URLs,
# credentials-in-URL samples (scheme://user:pass@host, not an email address) and the
# generated cdk/package-lock.json (third-party package metadata).
EMAIL_HITS="$(scan '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | not_excluded \
    | grep -v '^cdk/package-lock\.json:' | grep -v 'example\.com' | grep -v 'placeholder' \
    | grep -v 'noreply' | grep -v 'shields\.io' | grep -v -E '://[^[:space:]/@]*@')"
if [ -n "$EMAIL_HITS" ]; then
    warn "Potential email addresses found (verify they are placeholders):"
    echo "$EMAIL_HITS" | cut -c1-200 | head -5 | indent
else
    pass "No email addresses outside placeholders"
fi

# Singapore NRIC/FIN (warning). Ignored: lines that document a regex/pattern and the
# documented synthetic values with the digit sequence 1234567 (for example the S-series
# masking example used throughout the skills).
NRIC_HITS="$(scan '[STFGM][0-9]{7}[A-Z]' | not_excluded | grep -v 'regex' | grep -v 'pattern' \
    | grep -v '\\d' | sed -E 's/[STFGM]1234567[A-Z]/<synthetic>/g' | grep -E '[STFGM][0-9]{7}[A-Z]')"
if [ -n "$NRIC_HITS" ]; then
    warn "Potential NRIC/FIN found (verify these are synthetic examples only):"
    echo "$NRIC_HITS" | cut -c1-200 | head -5 | indent
else
    pass "No NRIC/FIN values other than documented synthetic examples"
fi

pass "PII/secrets scan complete (${#SCAN_PATHS[@]} paths)"
echo ""

# ─── CHECK 5: Broken internal links ──────────────────
# Every Markdown file in the repo (tracked plus untracked, not ignored). For each [text](target)
# and ![alt](target): skip URI schemes (http:, https:, mailto:, ...) and pure #anchors, strip
# #anchor and ?query, then resolve the target relative to the linking file's own directory
# (a leading / means the repo root, as on GitHub). Fenced code blocks and inline code spans
# are ignored. Anchors themselves are not checked.
echo "[5/8] Checking for broken internal markdown links..."

list_markdown() {
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git ls-files --cached --others --exclude-standard -- '*.md' 2>/dev/null | sort -u
    else
        find . -name '*.md' -not -path '*/node_modules/*' -not -path '*/cdk.out/*' \
            -not -path '*/build/*' -not -path './.git/*' | sed 's|^\./||' | sort
    fi
}

extract_links() { # extract_links <file>: one link target per line
    awk '/^[ \t]*(```|~~~)/ { fence = !fence; next } !fence { print }' "$1" \
        | sed -e 's/`[^`]*`//g' \
        | grep -o -E '[]][(][^)]*[)]' \
        | sed -e 's/^](//' -e 's/)$//' \
        | awk '{ print $1 }' \
        | sed -e 's/^<//' -e 's/>$//'
}

SCHEME_RE='^[A-Za-z][A-Za-z0-9+.-]*:'
BROKEN_LINKS=0
LINK_COUNT=0
MD_COUNT=0
while IFS= read -r md_file; do
    [ -f "$md_file" ] || continue
    case "$md_file" in */node_modules/*|cdk/cdk.out/*|cdk/build/*) continue ;; esac
    MD_COUNT=$((MD_COUNT + 1))
    md_dir="$(dirname "$md_file")"
    while IFS= read -r link; do
        [ -n "$link" ] || continue
        case "$link" in \#*) continue ;; esac
        [[ "$link" =~ $SCHEME_RE ]] && continue
        target="${link%%#*}"
        target="${target%%\?*}"
        [ -n "$target" ] || continue
        target="${target//\%20/ }"
        case "$target" in
            /*) resolved=".$target" ;;
            *)  resolved="$md_dir/$target" ;;
        esac
        LINK_COUNT=$((LINK_COUNT + 1))
        if [ ! -e "$resolved" ]; then
            warn "Broken link in $md_file -> $link"
            BROKEN_LINKS=$((BROKEN_LINKS + 1))
        fi
    done < <(extract_links "$md_file" | sort -u)
done < <(list_markdown)
if [ "$BROKEN_LINKS" -eq 0 ]; then
    pass "No broken internal links ($LINK_COUNT local links in $MD_COUNT Markdown files)"
else
    echo "  -> $BROKEN_LINKS broken internal link(s) ($LINK_COUNT local links in $MD_COUNT Markdown files)"
fi
echo ""

# ─── CHECK 6: TODO/FIXME scanning ────────────────────
echo "[6/8] Scanning for TODO/FIXME items..."
TODOS=$(grep -r -n -i -E '(TODO|FIXME|HACK|XXX|TEMP):' *.md kiro-docs/ 2>/dev/null || true)
if [ -n "$TODOS" ]; then
    warn "Found TODO/FIXME items:"
    echo "$TODOS" | indent
else
    pass "No TODO/FIXME items found"
fi
echo ""

# ─── CHECK 7: Large files ────────────────────────────
echo "[7/8] Checking for large tracked files (>1MB)..."
LARGE_FILES=0
while IFS= read -r f; do
    if [ -f "$f" ]; then
        SIZE=$(wc -c < "$f" 2>/dev/null || echo 0)
        if [ "$SIZE" -gt 1048576 ]; then
            warn "Large file tracked: $f ($(( SIZE / 1024 ))KB)"
            LARGE_FILES=$((LARGE_FILES + 1))
        fi
    fi
done < <(git ls-files 2>/dev/null)
if [ "$LARGE_FILES" -eq 0 ]; then
    pass "No oversized tracked files"
fi
echo ""

# ─── CHECK 8: Markdown structure ─────────────────────
echo "[8/8] Validating markdown structure..."
for md_file in *.md; do
    [ -f "$md_file" ] || continue
    # Check for H1 heading
    if ! head -5 "$md_file" | grep -qE '^# ' 2>/dev/null; then
        warn "$md_file missing H1 heading in first 5 lines"
    fi
done
pass "Markdown structure check complete"
echo ""

# ─── SUMMARY ─────────────────────────────────────────
echo "================================================"
echo "  VALIDATION SUMMARY"
echo "================================================"
echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "  ERRORS:   $ERRORS (must be fixed before opening a pull request)"
    echo "  WARNINGS: $WARNINGS (review recommended; broken links: $BROKEN_LINKS)"
    echo ""
    echo "  RESULT: FAILED"
    exit 1
else
    echo "  ERRORS:   0"
    echo "  WARNINGS: $WARNINGS (broken links: $BROKEN_LINKS)"
    echo ""
    echo "  RESULT: PASSED"
    echo ""
    echo "  Next steps (pull-request flow; never push directly to main):"
    echo "  1. Review any warnings above"
    echo "  2. Work on a feature branch:  git switch -c <type>/<short-description>"
    echo "  3. Stage and commit only the files you changed, then: git push -u origin <branch>"
    echo "  4. Open a pull request against main; the CI workflow must pass"
    echo "  5. A maintainer reviews and merges the pull request"
fi
