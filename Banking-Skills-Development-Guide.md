# Building Kiro Skills for Banking Developers
## MAS Compliance & Singapore Banking Best Practices

---

## 1. Overview: Skills for Banking

Skills are portable instruction packages that teach Kiro how to handle banking-specific workflows consistently. For Singapore banking developers, skills ensure:
- **MAS compliance** in every code generation
- **Security-first** development practices
- **Standardized workflows** across teams
- **Audit trail** for regulatory requirements

---

## 2. Banking Skill Categories

### Category 1: Compliance & Security Skills
**Purpose:** Automated MAS compliance checking and security validation

**Example Skills:**
- `mas-compliance-review` - Validate code against MAS TRM Guidelines
- `pii-detection` - Identify and flag PII in code/data
- `security-audit` - Banking-specific security scanning
- `encryption-validator` - Verify encryption standards (TLS 1.2+, KMS)

### Category 2: SDLC Workflow Skills
**Purpose:** Banking-specific development workflows

**Example Skills:**
- `banking-code-review` - Code review with banking standards
- `deployment-approval` - Multi-stage approval workflow
- `change-management` - MAS-compliant change procedures
- `incident-response` - Security incident handling

### Category 3: Documentation Skills
**Purpose:** Regulatory documentation generation

**Example Skills:**
- `mas-documentation` - Generate MAS-compliant docs
- `audit-report` - Create audit trail reports
- `risk-assessment` - Generate risk assessment docs
- `compliance-checklist` - Automated compliance validation

---

## 3. Skill Structure for Banking

### Minimal Banking Skill Template

```
mas-compliance-review/
├── SKILL.md                    # Required
├── scripts/
│   ├── check_encryption.py     # Verify encryption standards
│   ├── scan_pii.py             # PII detection
│   └── validate_mas.sh         # MAS compliance checks
├── references/
│   ├── mas-trm-guidelines.md   # MAS TRM reference
│   ├── security-standards.md   # Banking security standards
│   └── compliance-matrix.md    # Compliance mapping
└── assets/
    └── audit-template.md       # Audit report template
```

---

## 4. Example: MAS Compliance Review Skill

### SKILL.md

```markdown
---
name: mas-compliance-review  # REQUIRED
description: Review code for MAS Technology Risk Management Guidelines compliance. Use when reviewing code, preparing for deployment, or conducting security audits in Singapore banking applications.  # REQUIRED
license: Proprietary  # OPTIONAL
compatibility: Requires Python 3.9+, AWS CLI configured  # OPTIONAL
metadata:  # OPTIONAL - All fields below are optional
  author: Banking Security Team
  version: 1.0.0
  mas_version: TRM_2021
---

# MAS Compliance Review Skill

## Purpose
Automated compliance checking against MAS Technology Risk Management Guidelines (January 2021) for Singapore banking applications.

## Activation Triggers
- "Review this code for MAS compliance"
- "Check MAS TRM requirements"
- "Validate banking security standards"
- "Prepare for MAS audit"

## Review Process

### 1. Access Control Validation (MAS Section 9)
```bash
python scripts/check_access_control.py --path ./src
```

**Checks:**
- Multi-factor authentication implementation
- Privileged access management
- User access review procedures
- Password policy compliance

### 2. Encryption Standards (MAS Section 10)
```bash
python scripts/check_encryption.py --path ./src
```

**Validates:**
- TLS 1.2 or higher for data in transit (TLS 1.3 recommended)
- AWS KMS for data at rest
- No hardcoded credentials
- Proper key rotation

### 3. Change Management (MAS Section 7.5)
```bash
bash scripts/validate_change_mgmt.sh
```

**Verifies:**
- Change approval workflow
- Segregation of duties
- Rollback procedures
- Emergency change process

### 4. PII Detection (MAS Section 11)
```bash
python scripts/scan_pii.py --path ./src --output report.json
```

**Identifies:**
- NRIC numbers
- Credit card data
- Bank account numbers
- Personal information

## Compliance Matrix

| MAS Section | Control | Status | Evidence |
|-------------|---------|--------|----------|
| 9.1 | Access Control | ✓ | IAM policies reviewed |
| 10.1 | Encryption | ✓ | TLS 1.2+ + KMS verified |
| 11.1 | Data Security | ✓ | DLP policies active |
| 15.1 | Audit Logging | ✓ | CloudTrail enabled |

## Output Format

### Compliance Report
```markdown
# MAS Compliance Review Report
Date: {timestamp}
Reviewer: {user}
Project: {project_name}

## Summary
- Total Checks: {total}
- Passed: {passed}
- Failed: {failed}
- Warnings: {warnings}

## Critical Issues
{list_of_critical_issues}

## Recommendations
{list_of_recommendations}

## Audit Trail
{cloudtrail_logs}
```

## Remediation Guidance

### Critical: Hardcoded Credentials
```python
# ❌ FAIL - Hardcoded credential
aws_secret = "AKIAIOSFODNN7EXAMPLE"

# ✅ PASS - AWS Secrets Manager
import boto3
secret = boto3.client('secretsmanager').get_secret_value(
    SecretId='/banking/prod/api-key'
)
```

### Critical: Missing Encryption
```python
# ❌ FAIL - Unencrypted S3 bucket
s3.create_bucket(Bucket='banking-data')

# ✅ PASS - Encrypted with KMS
s3.create_bucket(
    Bucket='banking-data',
    ServerSideEncryptionConfiguration={
        'Rules': [{
            'ApplyServerSideEncryptionByDefault': {
                'SSEAlgorithm': 'aws:kms',
                'KMSMasterKeyID': 'arn:aws:kms:...'
            }
        }]
    }
)
```

## References
- See `references/mas-trm-guidelines.md` for full MAS TRM Guidelines
- See `references/security-standards.md` for banking security standards
- See `references/compliance-matrix.md` for detailed compliance mapping

## Escalation
For compliance violations:
1. Document in audit report
2. Notify Security Team immediately
3. Block deployment if critical
4. Report to MAS if material breach (within 24 hours)
```

---

## 5. Example: PII Detection Skill

### SKILL.md (Compact)

```markdown
---
name: pii-detection  # REQUIRED
description: Detect and flag Personally Identifiable Information (PII) in code, data, and documentation. Use when reviewing code, scanning data files, or preparing for compliance audits.  # REQUIRED
metadata:  # OPTIONAL
  author: Data Protection Team
  version: 1.0.0
---

# PII Detection Skill

## Detection Patterns

### Singapore-Specific PII
- **NRIC**: `[STFG]\d{7}[A-Z]`
- **FIN**: `[FG]\d{7}[A-Z]`
- **Phone**: `[689]\d{7}`
- **Postal Code**: `\d{6}`

### Financial PII
- **Credit Card**: Luhn algorithm validation
- **Bank Account**: `\d{10,12}`
- **SWIFT/BIC**: `[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?`

## Usage
```bash
python scripts/scan_pii.py --path ./src --types nric,credit_card,bank_account
```

## Remediation
```python
# ❌ FAIL - PII in logs
logger.info(f"Processing NRIC: {nric}")

# ✅ PASS - Masked PII
logger.info(f"Processing NRIC: {nric[:2]}****{nric[-1]}")
```
```

---

## 6. Example: Banking Code Review Skill

### SKILL.md (Compact)

```markdown
---
name: banking-code-review  # REQUIRED
description: Conduct code reviews following Singapore banking security standards and MAS guidelines. Use when reviewing pull requests, preparing for deployment, or conducting security audits.  # REQUIRED
---

# Banking Code Review Skill

## Review Checklist

### 1. Security (MAS Section 10)
- [ ] No hardcoded credentials
- [ ] TLS 1.2+ for all connections (TLS 1.3 recommended)
- [ ] Input validation on all user inputs
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (output encoding)

### 2. Access Control (MAS Section 9)
- [ ] MFA enforced for privileged operations
- [ ] Least privilege principle applied
- [ ] Session timeout configured (15 minutes)
- [ ] Failed login attempt lockout (3 attempts)

### 3. Data Protection (MAS Section 11)
- [ ] PII encrypted at rest (KMS)
- [ ] PII encrypted in transit (TLS 1.2+)
- [ ] Data retention policy enforced
- [ ] Secure deletion implemented

### 4. Audit & Logging (MAS Section 15)
- [ ] All financial transactions logged
- [ ] CloudTrail enabled
- [ ] Log integrity protected
- [ ] 90-day retention minimum

### 5. Error Handling
- [ ] No sensitive data in error messages
- [ ] Proper exception handling
- [ ] Graceful degradation
- [ ] User-friendly error messages

## Common Banking Vulnerabilities

### SQL Injection
```python
# ❌ FAIL
query = f"SELECT * FROM accounts WHERE id = {user_input}"

# ✅ PASS
query = "SELECT * FROM accounts WHERE id = %s"
cursor.execute(query, (user_input,))
```

### Insecure Direct Object Reference
```python
# ❌ FAIL
account_id = request.GET['account_id']
account = Account.objects.get(id=account_id)

# ✅ PASS
account_id = request.GET['account_id']
account = Account.objects.get(id=account_id, user=request.user)
```

## Approval Criteria
- All security checks passed
- No critical vulnerabilities
- MAS compliance validated
- Code review approved by 2+ reviewers
```

---

## 7. Deployment: Workspace vs Global

### Workspace Skills (Team-Wide)
**Location:** `.kiro/skills/`

**Use for:**
- Project-specific compliance requirements
- Team coding standards
- Banking application workflows

**Deployment:**
```bash
# Commit to repository
git add .kiro/skills/
git commit -m "Add MAS compliance review skill"
git push

# All team members get the skill automatically
```

### Global Skills (Personal)
**Location:** `~/.kiro/skills/`

**Use for:**
- Personal code review preferences
- Individual productivity workflows
- Cross-project utilities

---

## 8. Integration with MCP Servers

### Combining Skills with MCP Tools

**Example: AWS Documentation + MAS Compliance**

```markdown
---
name: aws-banking-deployment  # REQUIRED
description: Deploy AWS infrastructure following MAS compliance requirements. Use when deploying banking applications to AWS.  # REQUIRED
---

# AWS Banking Deployment Skill

## Pre-Deployment Checks

1. **Use AWS Documentation MCP** to verify best practices:
```
Search AWS documentation for "VPC PrivateLink banking"
```

2. **Run MAS compliance checks**:
```bash
python scripts/validate_mas.py --service vpc
```

3. **Verify encryption**:
```bash
aws kms describe-key --key-id {key-id}
```

## Deployment Workflow
1. Validate MAS compliance
2. Review AWS best practices via MCP
3. Deploy to staging
4. Run security scan
5. Approve for production
```

---

## 9. Testing Banking Skills

### Test Cases

```bash
# Test 1: Detect hardcoded credentials
echo 'aws_key = "AKIAIOSFODNN7EXAMPLE"' > test.py
kiro-cli chat "Review test.py for MAS compliance"
# Expected: FAIL - Hardcoded credential detected

# Test 2: Validate encryption
cat > test_s3.py << EOF
s3.create_bucket(Bucket='test', 
    ServerSideEncryptionConfiguration={
        'Rules': [{'ApplyServerSideEncryptionByDefault': 
            {'SSEAlgorithm': 'aws:kms'}}]
    })
EOF
kiro-cli chat "Review test_s3.py for MAS compliance"
# Expected: PASS - Encryption validated

# Test 3: PII detection
echo 'nric = "S1234567D"' > test_pii.py
kiro-cli chat "Scan test_pii.py for PII"
# Expected: WARNING - NRIC detected
```

---

## 10. Skill Governance

### Approval Workflow

```mermaid
graph TD
    A[Developer Creates Skill] --> B[Security Review]
    B --> C[Compliance Review]
    C --> D[Management Approval]
    D --> E[Deploy to .kiro/skills/]
    E --> F[Team Access]
```

### Skill Registry

| Skill Name | Owner | MAS Section | Status | Last Updated |
|------------|-------|-------------|--------|--------------|
| mas-compliance-review | Security Team | All | Active | 2026-02-25 |
| pii-detection | Data Protection | 11.1 | Active | 2026-02-20 |
| banking-code-review | Dev Team | 9, 10, 11 | Active | 2026-02-15 |
| deployment-approval | DevOps | 7.5 | Active | 2026-02-10 |

---

## 11. Best Practices for Banking Skills

### 1. Security-First Design
- Never log sensitive data
- Validate all inputs
- Use parameterized queries
- Encrypt PII at rest and in transit

### 2. MAS Compliance
- Reference specific MAS sections
- Include audit trail generation
- Document all security controls
- Maintain compliance matrix

### 3. Clear Activation Triggers
```markdown
# ✅ GOOD - Specific triggers
description: Review code for MAS TRM compliance. Use when reviewing pull requests, preparing for deployment, conducting security audits, or validating banking security standards.

# ❌ BAD - Vague triggers
description: Helps with code review.
```

### 4. Comprehensive Documentation
- Include remediation examples
- Reference MAS guidelines
- Provide escalation procedures
- Document all checks performed

### 5. Version Control
- Track skill versions
- Document changes
- Maintain backward compatibility
- Test before deployment

---

## 12. Skill Maintenance

### Monthly Review Checklist
- [ ] Update MAS guideline references
- [ ] Review security patterns
- [ ] Test all validation scripts
- [ ] Update compliance matrix
- [ ] Verify MCP integrations
- [ ] Check for deprecated APIs
- [ ] Update documentation

### Incident Response
If skill fails to detect compliance issue:
1. Document the gap
2. Update detection logic
3. Add test case
4. Notify all users
5. Update skill version

---

## 13. Advanced: Skill Composition

### Combining Multiple Skills

```markdown
---
name: banking-deployment-pipeline  # REQUIRED
description: Complete banking deployment pipeline with MAS compliance, security scanning, and approval workflow.  # REQUIRED
---

# Banking Deployment Pipeline

## Workflow

1. **Code Review** (banking-code-review skill)
2. **MAS Compliance** (mas-compliance-review skill)
3. **PII Scan** (pii-detection skill)
4. **Security Audit** (security-audit skill)
5. **Deployment Approval** (deployment-approval skill)

## Execution
All skills run automatically in sequence. Pipeline fails if any skill reports critical issues.
```

---

## Appendix A: MAS TRM Sections Reference

| Section | Topic | Skill Coverage |
|---------|-------|----------------|
| 5 | System Development | banking-code-review |
| 7.5 | Change Management | deployment-approval |
| 9 | Access Control | mas-compliance-review |
| 10 | Encryption | encryption-validator |
| 11 | Data Security | pii-detection |
| 15 | Audit Logging | audit-report |

---

## Appendix B: Skill Templates

### Quick Start Template
```bash
# Create new banking skill
mkdir -p .kiro/skills/my-banking-skill/{scripts,references,assets}
cat > .kiro/skills/my-banking-skill/SKILL.md << 'EOF'
---
name: my-banking-skill  # REQUIRED
description: [What it does]. Use when [specific triggers].  # REQUIRED
metadata:  # OPTIONAL - All fields below are optional
  author: [Your Team]
  version: 1.0.0
  mas_section: [MAS Section]
---

# My Banking Skill

## Purpose
[Clear purpose statement]

## Checks
- [ ] Check 1
- [ ] Check 2

## Usage
```bash
[command to run]
```

## References
- MAS TRM Guidelines Section [X]
EOF
```

---

**Document Complete:** Banking developers now have comprehensive guidance for building MAS-compliant Kiro Skills with security-first practices and regulatory compliance built-in.
