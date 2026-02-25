# Prepare Repository for GitHub

## Step 1: Initialize Git Repository

```bash
git init
git add .gitignore LICENSE CONTRIBUTING.md README-Kiro-Banking-Best-Practices.md
git add *.md kiro-docs/
git commit -m "Initial commit: AWS Kiro Banking Best Practices documentation"
```

## Step 2: Verify No Excluded Files

```bash
# Check what will be committed
git status

# Verify no PDFs or .kiro files
git ls-files | grep -E '\.(pdf|PDF)$|\.kiro/'
# Should return nothing
```

## Step 3: Create GitHub Repository

1. Go to GitHub and create a new repository
2. Do NOT initialize with README (we already have one)

## Step 4: Push to GitHub

```bash
# Add remote (replace with your repository URL)
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git

# Push to GitHub
git branch -M main
git push -u origin main
```

## Verification Checklist

- [ ] `.gitignore` excludes PDFs and `.kiro/` folder
- [ ] LICENSE file is present (MIT License)
- [ ] No PII or customer data in any files
- [ ] Only markdown and code files are tracked
- [ ] CONTRIBUTING.md explains contribution guidelines
- [ ] All placeholder data is generic

## Files Included

- All `.md` files (documentation)
- `kiro-docs/` folder (technical references)
- `LICENSE` (MIT License)
- `.gitignore` (exclusion rules)
- `CONTRIBUTING.md` (contribution guidelines)

## Files Excluded

- All `.pdf` files (regulatory documents)
- `.kiro/` folder (local configuration)
- System files (`.DS_Store`, etc.)
