# Building Kiro Skills for Banking Developers
## MAS-Aligned Skills for Singapore Financial Institutions (banking reference examples)

> **Audience:** developers building Kiro Skills · **Purpose:** build MAS-aligned banking Skills (with working examples in `.kiro/skills/`) · **Prerequisites:** basic familiarity with Kiro Skills · ↩ [README](README.md)

---

## 1. Overview: Skills for Banking

Skills are portable instruction packages (the open Agent Skills format) that Kiro activates when a request matches the skill's `description`. At startup Kiro reads only each skill's `name` and `description`. It loads the full `SKILL.md` when a request matches, and loads files under `references/` only when `SKILL.md` tells it to.

For Singapore banking developers, skills give:
- **Repeatable workflows:** the same MAS TRM mapping, PII scan or secure code review every time the task comes up
- **Shared reference material** (TRM quick reference, PDPA checklist, PII patterns) that loads only when needed
- **Standard report formats** that reviewers can attach as review evidence
- **Security-first examples** (FAIL/PASS code) for common banking vulnerabilities

What skills are not:
- **Not always on.** A skill runs only when a request matches its description. Rules that must apply to every interaction (for example "never hardcode secrets" or "mask NRIC in output") belong in steering files with `inclusion: always`, such as `.kiro/steering/banking-standards.md`.
- **Not an enforcement control.** Skills and steering guide the agent. Controls that must hold are enforced by managed settings, hooks, branch protection and CI.

| Mechanism | When it applies | Use it for | Example in this repository |
|-----------|-----------------|------------|----------------------------|
| Skill | When a request matches the skill's `description` | Task workflows with checklists and references | `.kiro/skills/pii-detection/` |
| Steering, `inclusion: always` | Every interaction | Standards that always apply | `.kiro/steering/banking-standards.md` |
| Steering, `inclusion: fileMatch` | When the agent works on matching files | Rules for one kind of code | `.kiro/steering/fairness.md` |
| Managed settings, hooks, CI | Enforced by the client, the hooks or the pipeline | Controls that must not depend on the model | `managed-settings/`, `agent-hooks/`, `.github/workflows/validate.yml` |

---

## 2. Banking Skill Categories

### Shipped in this repository

| Skill | What it does | Version | Path |
|-------|--------------|---------|------|
| `mas-compliance-review` | Maps code, infrastructure-as-code and designs to MAS TRM sections, MAS notices and PDPA obligations | 1.3.0 | `.kiro/skills/mas-compliance-review/` |
| `pii-detection` | Finds, masks and redacts Singapore PII and secrets; its patterns are tested by `tests/patterns.test.sh` | 1.1.0 | `.kiro/skills/pii-detection/` |
| `banking-code-review` | Reviews application code and pull requests (secure coding, OWASP, approval criteria) | 1.1.0 | `.kiro/skills/banking-code-review/` |

The two review skills divide the work so that one, not both, activates for a request: `mas-compliance-review` covers regulatory and infrastructure mapping, and `banking-code-review` covers application code review. Each description ends with "Not for ... (use ...)" so that Kiro picks the right one, and each `SKILL.md` says when to use the other.

### Examples you could build (not shipped)

These are ideas for further skills. None of them exists in this repository.

| Category | Example skill (not shipped) | Purpose |
|----------|-----------------------------|---------|
| Compliance & security | `security-audit` | Banking-specific security scanning |
| Compliance & security | `encryption-validator` | Verify encryption standards (TLS 1.2+, KMS) |
| SDLC workflow | `deployment-approval` | Multi-stage approval workflow |
| SDLC workflow | `change-management` | MAS-aligned change procedures (TRM 7.5) |
| SDLC workflow | `incident-response` | Security incident handling (TRM 12.3) |
| Documentation | `mas-documentation` | Generate MAS-aligned documentation |
| Documentation | `audit-report` | Create audit trail reports |
| Documentation | `risk-assessment` | Generate risk assessment documents |
| Documentation | `compliance-checklist` | Generate compliance checklists |

---

## 3. Skill Structure for Banking

### Frontmatter

| Field | Required | Rules |
|-------|----------|-------|
| `name` | Yes | Must match the folder name; lowercase letters, numbers and hyphens; max 64 characters |
| `description` | Yes | What the skill does and when to use it; max 1024 characters. Kiro decides activation from `name` and `description` only, so trigger phrases belong here, not in the body |
| `license` | No | License name or bundled license file |
| `compatibility` | No | Environment requirements (tools, network access) |
| `metadata` | No | Key-value data such as author and version |

The frontmatter must be the first thing in the file, between two `---` lines, and must be valid YAML. Quote a value if it contains `: ` or ` #`, or starts with a YAML indicator such as `[`, `{`, `*`, `&`, `!`, `|`, `>`, `'`, `"`, `%` or `@`.

### Layout of the shipped skills

```
.kiro/skills/pii-detection/
├── SKILL.md                          # Required: frontmatter + instructions
├── references/
│   └── singapore-pii-patterns.md     # Loaded when SKILL.md points to it
└── tests/
    ├── patterns.test.sh              # Pattern regression test (bash + grep -E; perl optional)
    └── fixtures/
        └── pattern-cases.tsv         # Positive and negative cases

.kiro/skills/mas-compliance-review/
├── SKILL.md
└── references/
    ├── mas-trm-quick-ref.md
    └── pdpa-checklist.md

.kiro/skills/banking-code-review/
├── SKILL.md
└── references/
    ├── banking-security-checklist.md
    └── owasp-banking-top10.md
```

### Optional folders (illustrative)

The Agent Skills format also allows `scripts/` (executable helpers) and `assets/` (templates). No skill in this repository ships scripts or assets; the names below are illustrative only.

```
my-banking-skill/
├── SKILL.md
├── references/          # for example, a control matrix your team maintains
├── scripts/             # illustrative, not shipped: for example check_encryption.py
└── assets/              # illustrative, not shipped: for example audit-report-template.md
```

If you add scripts, review and test them like any other code: they run on developer machines with the developer's credentials.

---

## 4. Example: MAS Compliance Review Skill

### SKILL.md

Shortened from `.kiro/skills/mas-compliance-review/SKILL.md`; the shipped file has the full checklist and is the authoritative version.

````markdown
---
name: mas-compliance-review  # REQUIRED
description: Map code and infrastructure-as-code to MAS TRM sections, MAS notices and PDPA obligations. Use when asked to review code or infrastructure for MAS compliance, check MAS TRM requirements, or prepare for a MAS audit. Not for application code review (use banking-code-review) or PII scanning (use pii-detection).  # REQUIRED
license: MIT  # OPTIONAL
compatibility: Kiro IDE or Kiro CLI; no scripts or network access required  # OPTIONAL
metadata:  # OPTIONAL - All fields below are optional
  author: Security Architecture Team
  version: 1.3.0
  mas_version: TRM_2021
---

# MAS Compliance Review Skill

## Purpose
Map code, infrastructure-as-code and designs to the MAS Technology Risk Management Guidelines (January 2021), MAS notices and PDPA obligations for Singapore banking applications.

## Scope and related skills
- Application code review and pull request verdicts: use banking-code-review.
- PII and secret scanning: use pii-detection.

## Review Process

### 1. Access Control Validation (MAS Section 9)
- Multi-factor authentication (TRM 9.1; administrative accounts 9.2; customers 14.2)
- Privileged access management (TRM 9.2)
- Least privilege in IAM policies (TRM 9.1)
- Password policy (example institutional policy, not prescribed by MAS TRM)

### 2. Encryption Standards (MAS Section 10)
- TLS 1.2 or higher for data in transit (TLS 1.3 recommended) (TRM 10.1)
- AWS KMS customer-managed keys for data at rest, with rotation (TRM 10.2)
- No deprecated algorithms: MD5, SHA-1, DES, 3DES, RC4
- No hardcoded credentials or keys

### 3. Change Management (MAS Section 7.5)
- Change approval workflow (branch protection, required reviews)
- Segregation of duties (TRM 6.3)
- Rollback procedures
- Emergency change process

### 4. PII Detection (MAS Section 11.1)
- No NRIC/FIN, card or bank account numbers in code, logs or test data: run the pii-detection skill and cite its findings

## Compliance Matrix

| MAS Section | Control | Status | Evidence |
|-------------|---------|--------|----------|
| 9.1 | Access Control | {status} | {for example: IAM policies reviewed} |
| 10.1, 10.2 | Cryptography | {status} | {for example: TLS 1.2+ and KMS key rotation verified} |
| 11.1 | Data Security | {status} | {for example: PII scan clean} |
| 12.2 | Audit Logging (Cyber Event Monitoring and Detection) | {status} | {for example: CloudTrail enabled} |

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
```

## Remediation Guidance

### Critical: Hardcoded Credentials
```python
# FAIL - Hardcoded credential (this is the AWS documentation example key)
aws_access_key_id = "AKIAIOSFODNN7EXAMPLE"

# PASS - AWS Secrets Manager
import boto3
secrets = boto3.client('secretsmanager', region_name='ap-southeast-1')
api_key = secrets.get_secret_value(SecretId='/banking/prod/api-key')['SecretString']
```

### Critical: Data at rest not encrypted with a customer-managed key
Since 5 January 2023, S3 encrypts every new object with SSE-S3 by default, so the finding is not "unencrypted": it is that the institution's policy requires SSE-KMS with a customer-managed key.
```python
import boto3
s3 = boto3.client('s3', region_name='ap-southeast-1')

# FAIL (against a CMK policy) - relies on the default SSE-S3 encryption
s3.create_bucket(Bucket='banking-data',
                 CreateBucketConfiguration={'LocationConstraint': 'ap-southeast-1'})

# PASS - default encryption set to SSE-KMS with a customer-managed key
# (create_bucket has no encryption parameter; use put_bucket_encryption)
s3.create_bucket(Bucket='banking-data',
                 CreateBucketConfiguration={'LocationConstraint': 'ap-southeast-1'})
s3.put_bucket_encryption(
    Bucket='banking-data',
    ServerSideEncryptionConfiguration={
        'Rules': [{
            'ApplyServerSideEncryptionByDefault': {
                'SSEAlgorithm': 'aws:kms',
                'KMSMasterKeyID': 'arn:aws:kms:ap-southeast-1:111122223333:key/<key-id>'
            },
            'BucketKeyEnabled': True
        }]
    }
)
```

## References
- See `references/mas-trm-quick-ref.md` for the section-by-section TRM reference
- See `references/pdpa-checklist.md` for the PDPA data protection checklist

## Escalation
For compliance violations:
1. Document in audit report
2. Notify Security Team immediately
3. Block deployment if critical
4. Notify MAS not later than 1 hour after discovery of a relevant incident (MAS Notice FSM-N05 para 7; root-cause and impact analysis report within 14 days, para 8)
````

---

## 5. Example: PII Detection Skill

### SKILL.md (Compact)

Shortened from `.kiro/skills/pii-detection/SKILL.md`, which lists every pattern; `references/singapore-pii-patterns.md` adds the POSIX ERE forms, the context rules and the NRIC/FIN checksum.

````markdown
---
name: pii-detection  # REQUIRED
description: Detect, mask and redact Singapore personal data (PII) and secrets in code, configuration, logs and documentation. Use when asked to scan code for PII, find NRIC or FIN numbers, credit card or bank account numbers, mask or redact personal data, or find hardcoded secrets such as AWS keys before a commit.  # REQUIRED
metadata:  # OPTIONAL
  author: Data Protection Team
  version: 1.1.0
---

# PII Detection Skill

## Detection Patterns (PCRE; apply flags as engine options)

### Singapore-Specific PII
- **NRIC/FIN** (S, T, F, G and M series): `\b[STFGM]\d{7}[A-Z]\b`, then validate the check letter
- **Phone**: `(?<![\w+])(?:\+65[ -]?)?[3689]\d{3}[ -]?\d{4}\b`
- **Postal code**: 6 digits, only after "Singapore", "S(" or "postal"

### Financial PII
- **Credit card**: Visa (13, 16 or 19 digits), Mastercard (51-55 and 2221-2720), Amex (34/37); spaces or dashes allowed; then a Luhn check
- **Bank account**: 10-12 digits, only within 20 characters after "account", "acct" or "a/c" (high false-positive rate)
- **SWIFT/BIC**: Low severity (identifies a bank, not a person); only after "SWIFT" or "BIC"

### Secrets
- AWS access key IDs (`AKIA`, `ASIA`), AWS secret access key assignments, GitHub tokens, private key headers, password literals

## Testing
```bash
bash .kiro/skills/pii-detection/tests/patterns.test.sh
```

## Remediation
```python
# FAIL - PII in logs
logger.info(f"Processing NRIC: {nric}")

# PASS - Masked PII: first letter, four asterisks, last 3 digits and check letter
logger.info(f"Processing NRIC: {nric[0]}****{nric[-4:]}")
```
````

---

## 6. Example: Banking Code Review Skill

### SKILL.md (Compact)

Shortened from `.kiro/skills/banking-code-review/SKILL.md`.

````markdown
---
name: banking-code-review  # REQUIRED
description: Review application source code and pull requests against Singapore banking secure-coding standards. Use when asked to review a pull request, check whether code is ready for production, or do a security review of a change. Not for MAS TRM mapping of infrastructure (use mas-compliance-review).  # REQUIRED
---

# Banking Code Review Skill

## Review Checklist

### 1. Secure Coding (MAS Section 6.1)
- [ ] No hardcoded credentials
- [ ] TLS 1.2+ for all connections (TLS 1.3 recommended) (MAS Section 10.1)
- [ ] Input validation on all user inputs
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (output encoding)
- [ ] No deprecated crypto (MD5, SHA-1, DES, 3DES, RC4)

### 2. Access Control (MAS Section 9)
- [ ] MFA enforced for privileged operations
- [ ] Least privilege principle applied
- [ ] Session timeout configured (example institutional policy, not prescribed by MAS TRM: 15 minutes)
- [ ] Failed login attempt lockout (example institutional policy, not prescribed by MAS TRM: 3 attempts)

### 3. Data Protection (MAS Section 11.1)
- [ ] PII encrypted at rest (KMS)
- [ ] PII encrypted in transit (TLS 1.2+)
- [ ] Data retention policy enforced
- [ ] Secure deletion implemented

### 4. Audit & Logging (MAS Section 12.2)
- [ ] All financial transactions logged
- [ ] CloudTrail enabled
- [ ] Log integrity protected
- [ ] 90-day retention minimum (example institutional policy, not prescribed by MAS TRM)

### 5. Error Handling
- [ ] No sensitive data in error messages
- [ ] Proper exception handling
- [ ] Graceful degradation
- [ ] User-friendly error messages

## Common Banking Vulnerabilities

### SQL Injection
```python
# FAIL
query = f"SELECT * FROM accounts WHERE id = {user_input}"

# PASS
query = "SELECT * FROM accounts WHERE id = %s"
cursor.execute(query, (user_input,))
```

### Insecure Direct Object Reference
```python
# FAIL
account_id = request.GET['account_id']
account = Account.objects.get(id=account_id)

# PASS
account_id = request.GET['account_id']
account = Account.objects.get(id=account_id, user=request.user)
```

## Approval Criteria
Recommend approval only when:
- All security checks passed
- No critical vulnerabilities
- MAS TRM alignment checks passed (see the checklist above)
- PII detection scan clean

The verdict is a recommendation: the change still needs the human approvals required by branch protection. Never approve, merge or push to main on the user's behalf.
````

---

## 7. Deployment: Workspace vs Global

### Workspace Skills (Team-Wide)
**Location:** `.kiro/skills/`

**Use for:**
- Project-specific compliance requirements
- Team coding standards
- Banking application workflows

**Deployment:** through a pull request, like any other change:
```bash
git switch -c add-mas-compliance-skill
git add .kiro/skills/mas-compliance-review/
git commit -m "Add MAS compliance review skill"
git push -u origin add-mas-compliance-skill
# Open a pull request and merge it after the approvals required by branch protection
```

**Who gets the skill:**
- **Default agent (IDE and CLI):** loads workspace skills from `.kiro/skills/` once a team member pulls the change, provided the workspace is trusted. While a workspace is untrusted, Kiro does not load its skills, steering or custom agents.
- **Custom CLI agents:** do not load skills unless their `resources` include `skill://` URIs, for example `"skill://.kiro/skills/*/SKILL.md"`. The reference agent `agent-hooks/banking-secure.agent.json` does this. Kiro's documentation is inconsistent on whether custom agents inherit default resources, so list the `skill://` resources explicitly.
- **Name clashes:** a workspace skill overrides a global skill with the same name.

### Global Skills (Personal)
**Location:** `~/.kiro/skills/`

**Use for:**
- Personal code review preferences
- Individual productivity workflows
- Cross-project utilities

---

## 8. Integration with MCP Servers

### Combining Skills with MCP Tools

**Example (not shipped): AWS Documentation + MAS Compliance**

````markdown
---
name: aws-banking-deployment  # REQUIRED
description: Check AWS infrastructure changes against MAS-aligned deployment requirements before release. Use when preparing to deploy banking infrastructure to AWS.  # REQUIRED
---

# AWS Banking Deployment Skill

## Pre-Deployment Checks

1. **Use the AWS Documentation MCP server** to confirm current service behaviour:
   ```text
   Search AWS documentation for "VPC interface endpoints PrivateLink"
   ```

2. **Run the CDK checks** (CDK Nag AwsSolutionsChecks runs during synth):
   ```bash
   cd cdk && npm test && npx cdk synth
   ```

3. **Verify encryption keys**:
   ```bash
   aws kms describe-key --key-id <key-id>
   aws kms get-key-rotation-status --key-id <key-id>
   ```

## Deployment Workflow
1. Map the change to MAS TRM sections (mas-compliance-review skill)
2. Review AWS best practices via MCP
3. Deploy to staging through the pipeline
4. Run security scans in CI
5. Release to production after human approval (TRM 7.5, 7.6)
````

---

## 9. Testing Banking Skills

### Automated pattern tests

```bash
bash .kiro/skills/pii-detection/tests/patterns.test.sh
```

The test runs every documented PII and secret pattern against positive and negative fixtures (the ERE forms with `grep -E`, the PCRE forms with `perl` when installed), checks that the pattern blocks in the skill files match the reference, and checks the NRIC/FIN checksum, the Luhn check and the masking standard. It prints PASS/FAIL counts and exits non-zero on failure.

### Prompt smoke tests

Skills are instructions for a model, so results vary between runs and models. Use these prompts as manual smoke tests: check that the expected skill activates (Kiro CLI shows `[skill: <name> activated]`) and review the output.

```bash
# Test 1: Detect hardcoded credentials (AWS documentation example key)
echo 'aws_access_key_id = "AKIAIOSFODNN7EXAMPLE"' > test.py
kiro-cli chat "Review test.py for MAS compliance"
# Expected: mas-compliance-review activates; FAIL - hardcoded credential

# Test 2: Encryption with a customer-managed key
cat > test_s3.py << 'EOF'
import boto3
s3 = boto3.client('s3', region_name='ap-southeast-1')
s3.create_bucket(Bucket='test',
                 CreateBucketConfiguration={'LocationConstraint': 'ap-southeast-1'})
s3.put_bucket_encryption(
    Bucket='test',
    ServerSideEncryptionConfiguration={
        'Rules': [{'ApplyServerSideEncryptionByDefault': {
            'SSEAlgorithm': 'aws:kms',
            'KMSMasterKeyID': 'arn:aws:kms:ap-southeast-1:111122223333:key/<key-id>'}}]
    })
EOF
kiro-cli chat "Review test_s3.py for MAS compliance"
# Expected: PASS - SSE-KMS with a customer-managed key

# Test 3: PII detection
echo 'nric = "S1234567D"' > test_pii.py
kiro-cli chat "Scan test_pii.py for PII"
# Expected: pii-detection activates; Critical - NRIC, reported masked

# Test 4: Skill routing
kiro-cli chat "Review this pull request for banking standards"
# Expected: banking-code-review activates, not mas-compliance-review
```

---

## 10. Skill Governance

### Approval Workflow

```mermaid
graph TD
    A[Developer Creates Skill] --> B[Security Review]
    B --> C[Compliance Review]
    C --> D[Management Approval]
    D --> E[Merge to .kiro/skills/ via pull request]
    E --> F[Team Access]
```

### Skill Registry

Only these three skills ship in this repository. Add a row when you add a skill, and keep the version in step with `metadata.version`.

| Skill Name | Owner (`metadata.author`) | MAS Section | Version | Status | Last Updated |
|------------|---------------------------|-------------|---------|--------|--------------|
| mas-compliance-review | Security Architecture Team | All (mapping) | 1.3.0 | Shipped (sample) | 2026-10 |
| pii-detection | Data Protection Team | 11.1 | 1.1.0 | Shipped (sample) | 2026-10 |
| banking-code-review | Development Standards Team | 6.1, 9, 10, 11, 12.2 | 1.1.0 | Shipped (sample) | 2026-10 |

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
Kiro activates a skill from its `name` and `description` only. Put the trigger phrases in the description, keep it within 1024 characters, and say what the skill is not for, so that skills with neighbouring scopes do not both activate. A body section such as "Activation Triggers" does not affect activation.

```text
# GOOD - specific triggers, and a boundary with the neighbouring skill
description: Review application source code and pull requests against Singapore banking secure-coding standards. Use when asked to review a pull request, check whether code is ready for production, or do a security review of a change. Not for MAS TRM mapping of infrastructure (use mas-compliance-review).

# BAD - vague triggers that overlap with every other review skill
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
- [ ] Run `bash .kiro/skills/pii-detection/tests/patterns.test.sh` and the prompt smoke tests in section 9
- [ ] Update compliance matrix
- [ ] Verify MCP integrations
- [ ] Check for deprecated APIs
- [ ] Update documentation

### Incident Response
If skill fails to detect compliance issue:
1. Document the gap
2. Update detection logic
3. Add test case (for pii-detection, a line in `tests/fixtures/pattern-cases.tsv`)
4. Notify all users
5. Update skill version

---

## 13. Advanced: Skill Composition

### Combining Multiple Skills

Kiro does not run skills in sequence on its own. It activates a skill when a request matches the skill's description, so a request normally activates the one skill that fits it best. To combine skills:
- ask for each step explicitly ("scan the changed files for PII, then review this PR for banking standards"); or
- write an orchestrating skill (example below, not shipped) whose instructions tell the agent to read and follow the other skills' `SKILL.md` files in order;
- and enforce pass/fail gates in CI and branch protection: a skill can report a blocker, but it cannot block a merge.

````markdown
---
name: banking-release-review  # REQUIRED
description: Run the full pre-merge review of a banking change, covering a PII and secret scan, an application code review and MAS TRM mapping. Use when asked for a full pre-release or pre-merge review of a banking change.  # REQUIRED
---

# Banking Release Review (example, not shipped)

## Workflow
1. Scan the changed files for PII and secrets, following `.kiro/skills/pii-detection/SKILL.md`
2. Review the application code, following `.kiro/skills/banking-code-review/SKILL.md`
3. Map infrastructure changes and findings to MAS TRM sections, following `.kiro/skills/mas-compliance-review/SKILL.md`
4. Combine the findings into one report, by severity

## Gates
Report any critical finding as a blocker and recommend REQUEST_CHANGES. The merge itself is blocked by CI checks and branch protection, not by this skill.
````

---

## Appendix A: MAS TRM Sections Reference

| Section | Topic | Skill Coverage |
|---------|-------|----------------|
| 5.4 | System Development Life Cycle and Security-By-Design | mas-compliance-review (design and IaC); banking-code-review (application code) |
| 6.1 | Secure Coding, Source Code Review and Application Security Testing | banking-code-review |
| 7.5 | Change Management | None shipped: enforce with branch protection and CI (`change-management` is an example you could build) |
| 9 | Access Control | mas-compliance-review (IAM and IaC); banking-code-review (application authentication and authorization) |
| 10 | Cryptography | mas-compliance-review (KMS and TLS configuration); banking-code-review (cryptography in code) |
| 11 | Data and Infrastructure Security | pii-detection (11.1 PII and secrets); mas-compliance-review (11.1 encryption, 11.2 network) |
| 12.2 | Cyber Event Monitoring and Detection (audit logging; evidence for the 15.1 IT audit function) | mas-compliance-review (CloudTrail and log infrastructure); banking-code-review (application audit logging) |

---

## Appendix B: Skill Templates

### Quick Start Template

The folder name must match `name`. The placeholders are inside quoted strings, so the frontmatter parses as YAML.

````bash
# Create a new banking skill (add scripts/ only if you ship reviewed, tested scripts)
mkdir -p .kiro/skills/my-banking-skill/references
cat > .kiro/skills/my-banking-skill/SKILL.md << 'EOF'
---
name: my-banking-skill
description: "<What the skill does>. Use when <the requests that should trigger it>. Not for <out-of-scope work> (use <other-skill>)."
metadata:
  author: "<your team>"
  version: 1.0.0
  mas_section: "<MAS TRM section, for example 11.1>"
---

# My Banking Skill

## Purpose
<Clear purpose statement>

## Checks
- [ ] Check 1
- [ ] Check 2

## Usage
```bash
<command to run, if any>
```

## References
- MAS TRM Guidelines Section <X>
EOF
````

---

**Document Complete:** Banking developers now have guidance for building MAS-aligned Kiro Skills with security-first practices. Each institution remains responsible for its own compliance assessment.
