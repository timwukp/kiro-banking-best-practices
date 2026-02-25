#!/bin/bash
# Repository Validation Script
# Run this before pushing to GitHub

echo "🔍 Validating repository for GitHub push..."
echo ""

# Check 1: Verify .gitignore exists
if [ ! -f .gitignore ]; then
    echo "❌ ERROR: .gitignore file not found"
    exit 1
fi
echo "✅ .gitignore exists"

# Check 2: Verify LICENSE exists
if [ ! -f LICENSE ]; then
    echo "❌ ERROR: LICENSE file not found"
    exit 1
fi
echo "✅ LICENSE exists (MIT License)"

# Check 3: Check for PDF files in git
if git ls-files | grep -E '\.(pdf|PDF)$' > /dev/null 2>&1; then
    echo "❌ ERROR: PDF files found in git tracking:"
    git ls-files | grep -E '\.(pdf|PDF)$'
    exit 1
fi
echo "✅ No PDF files tracked"

# Check 4: Check for .kiro folder in git
if git ls-files | grep '\.kiro/' > /dev/null 2>&1; then
    echo "❌ ERROR: .kiro folder files found in git tracking:"
    git ls-files | grep '\.kiro/'
    exit 1
fi
echo "✅ No .kiro folder tracked"

# Check 5: Scan for potential PII patterns
echo ""
echo "🔍 Scanning for potential PII..."

# Email addresses
if grep -r -E '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' *.md kiro-docs/ 2>/dev/null | grep -v 'example.com' | grep -v 'placeholder' > /dev/null; then
    echo "⚠️  WARNING: Potential email addresses found (excluding examples)"
    grep -r -E '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' *.md kiro-docs/ 2>/dev/null | grep -v 'example.com' | grep -v 'placeholder'
fi

# AWS Account IDs
if grep -r -E '[0-9]{12}' *.md kiro-docs/ 2>/dev/null | grep -v 'example' | grep -v 'placeholder' > /dev/null; then
    echo "⚠️  WARNING: Potential AWS account IDs found"
    grep -r -E '[0-9]{12}' *.md kiro-docs/ 2>/dev/null | grep -v 'example' | grep -v 'placeholder'
fi

echo "✅ PII scan complete"

# Check 6: Verify key files exist
echo ""
echo "🔍 Verifying key documentation files..."
required_files=(
    "README-Kiro-Banking-Best-Practices.md"
    "Kiro-Agentic-SDLC-Banking-Best-Practices.md"
    "CONTRIBUTING.md"
    "PREPARE_FOR_GITHUB.md"
)

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ ERROR: Required file missing: $file"
        exit 1
    fi
    echo "✅ $file exists"
done

echo ""
echo "✅ All validation checks passed!"
echo ""
echo "📋 Next steps:"
echo "1. Review the files to be committed: git status"
echo "2. Initialize git: git init"
echo "3. Add files: git add ."
echo "4. Commit: git commit -m 'Initial commit: AWS Kiro Banking Best Practices'"
echo "5. Follow instructions in PREPARE_FOR_GITHUB.md"
