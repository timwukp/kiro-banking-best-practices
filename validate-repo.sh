#!/bin/bash
# Repository Validation Script
# Run this before pushing to GitHub
# Enhanced v1.2 - February 2026

ERRORS=0
WARNINGS=0

error() { echo "  ERROR: $1"; ERRORS=$((ERRORS + 1)); }
warn()  { echo "  WARNING: $1"; WARNINGS=$((WARNINGS + 1)); }
pass()  { echo "  PASS: $1"; }

echo "================================================"
echo "  Kiro Banking Best Practices - Repo Validator"
echo "================================================"
echo ""

# ─── CHECK 1: Required files ─────────────────────────
echo "[1/8] Checking required files..."
required_files=(
    ".gitignore"
    "LICENSE"
    "README.md"
    "README-Kiro-Banking-Best-Practices.md"
    "Kiro-Agentic-SDLC-Banking-Best-Practices.md"
    "Kiro-Banking-Best-Practices-Part2.md"
    "Banking-Skills-Development-Guide.md"
    "CONTRIBUTING.md"
    "CHANGELOG.md"
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
if git ls-files 2>/dev/null | grep -iE '\.(pdf)$' > /dev/null 2>&1; then
    error "PDF files found in git tracking:"
    git ls-files | grep -iE '\.(pdf)$' | while read -r f; do echo "    - $f"; done
else
    pass "No PDF files tracked"
fi
echo ""

# ─── CHECK 3: No .kiro folder in git ─────────────────
echo "[3/8] Checking for .kiro folder in git tracking..."
if git ls-files 2>/dev/null | grep '\.kiro/' > /dev/null 2>&1; then
    error ".kiro folder files found in git tracking:"
    git ls-files | grep '\.kiro/' | while read -r f; do echo "    - $f"; done
else
    pass "No .kiro folder tracked"
fi
echo ""

# ─── CHECK 4: PII and secrets scanning ───────────────
echo "[4/8] Scanning for PII and secrets..."

# Email addresses (excluding examples)
if grep -r -l -E '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' *.md kiro-docs/ 2>/dev/null | grep -v 'example.com' | grep -v 'placeholder' > /dev/null 2>&1; then
    FOUND=$(grep -r -n -E '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' *.md kiro-docs/ 2>/dev/null | grep -v 'example.com' | grep -v 'placeholder' | grep -v 'noreply' | grep -v 'shields.io' || true)
    if [ -n "$FOUND" ]; then
        warn "Potential email addresses found:"
        echo "$FOUND" | head -5 | while read -r line; do echo "    $line"; done
    fi
fi

# AWS Access Keys
if grep -r -n -E 'AKIA[0-9A-Z]{16}' *.md kiro-docs/ 2>/dev/null | grep -v 'EXAMPLE' | grep -v 'example' > /dev/null 2>&1; then
    error "Potential real AWS Access Key found!"
    grep -r -n -E 'AKIA[0-9A-Z]{16}' *.md kiro-docs/ 2>/dev/null | grep -v 'EXAMPLE' | grep -v 'example' | head -3
else
    pass "No real AWS access keys detected"
fi

# Private keys
if grep -r -l -E 'BEGIN (RSA |EC |DSA )?PRIVATE KEY' *.md kiro-docs/ 2>/dev/null; then
    error "Private key material found in documentation!"
else
    pass "No private key material detected"
fi

# Singapore NRIC patterns (real ones)
if grep -r -n -E '[STFG][0-9]{7}[A-Z]' *.md kiro-docs/ 2>/dev/null | grep -v 'regex' | grep -v 'pattern' | grep -v '\\d' > /dev/null 2>&1; then
    warn "Potential NRIC pattern found (verify these are examples only)"
fi

pass "PII/secrets scan complete"
echo ""

# ─── CHECK 5: Broken internal links ──────────────────
echo "[5/8] Checking for broken internal markdown links..."
BROKEN_LINKS=0
for md_file in *.md kiro-docs/*.md; do
    [ -f "$md_file" ] || continue
    # Extract markdown links [text](path) - only local files, not URLs
    grep -oE '\[([^]]*)\]\(([^)]*)\)' "$md_file" 2>/dev/null | \
        grep -oE '\(([^)]*)\)' | tr -d '()' | \
        grep -v '^http' | grep -v '^#' | grep -v '^mailto' | \
        sed 's/#.*//' | sort -u | while read -r link; do
            if [ -n "$link" ] && [ ! -f "$link" ] && [ ! -d "$link" ]; then
                warn "Broken link in $md_file -> $link"
                ((BROKEN_LINKS++)) || true
            fi
        done
done
if [ "$BROKEN_LINKS" -eq 0 ]; then
    pass "No broken internal links"
fi
echo ""

# ─── CHECK 6: TODO/FIXME scanning ────────────────────
echo "[6/8] Scanning for TODO/FIXME items..."
TODOS=$(grep -r -n -i -E '(TODO|FIXME|HACK|XXX|TEMP):' *.md kiro-docs/ 2>/dev/null || true)
if [ -n "$TODOS" ]; then
    warn "Found TODO/FIXME items:"
    echo "$TODOS" | while read -r line; do echo "    $line"; done
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
    echo "  ERRORS:   $ERRORS (must fix before push)"
    echo "  WARNINGS: $WARNINGS (review recommended)"
    echo ""
    echo "  RESULT: FAILED"
    exit 1
else
    echo "  ERRORS:   0"
    echo "  WARNINGS: $WARNINGS"
    echo ""
    echo "  RESULT: PASSED"
    echo ""
    echo "  Next steps:"
    echo "  1. Review any warnings above"
    echo "  2. git add -A && git status"
    echo "  3. git commit -m 'Your commit message'"
    echo "  4. git push origin main"
fi
