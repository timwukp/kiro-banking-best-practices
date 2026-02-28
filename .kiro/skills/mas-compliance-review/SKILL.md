---
name: mas-compliance-review
description: Review code and infrastructure for MAS Technology Risk Management Guidelines compliance. Use when reviewing code for banking compliance, preparing for MAS audit, validating security controls, checking TRM alignment, or conducting compliance assessments for Singapore financial institutions.
metadata:
  author: Security Architecture Team
  version: 1.2.0
  mas_version: TRM_2021
  regulations: MAS TRM, PDPA, MAS AIRG, MAS Outsourcing Guidelines
---

# MAS Compliance Review Skill

## Purpose

Automated compliance checking against Singapore banking regulations for code and infrastructure in Kiro-assisted development environments.

## Activation Triggers

- "Review this code for MAS compliance"
- "Check MAS TRM requirements"
- "Validate banking security standards"
- "Prepare for MAS audit"
- "Is this code compliant with Singapore banking regulations?"

## Review Process

When activated, perform these checks in order:

### 1. Access Control (MAS TRM Section 9)

Check for:
- [ ] Multi-factor authentication implementation
- [ ] Privileged access management (no hardcoded admin credentials)
- [ ] Session timeout configuration (max 15 minutes for banking apps)
- [ ] Failed login lockout (max 3 attempts)
- [ ] Least privilege principle in IAM policies

**Fail patterns:**
```python
# FAIL: Hardcoded credentials
password = "admin123"
aws_key = "AKIA..."

# PASS: Use AWS Secrets Manager
import boto3
secret = boto3.client('secretsmanager').get_secret_value(SecretId='/banking/prod/api-key')
```

### 2. Cryptography (MAS TRM Section 10)

Check for:
- [ ] TLS 1.2 or higher for all connections (TLS 1.3 recommended)
- [ ] AWS KMS for data at rest encryption
- [ ] No use of deprecated algorithms (MD5, SHA-1, DES, RC4)
- [ ] Proper key rotation configuration
- [ ] No hardcoded encryption keys

**Fail patterns:**
```python
# FAIL: Unencrypted S3 bucket
s3.create_bucket(Bucket='banking-data')

# PASS: KMS-encrypted S3 bucket
s3.create_bucket(Bucket='banking-data',
    ServerSideEncryptionConfiguration={
        'Rules': [{'ApplyServerSideEncryptionByDefault': {
            'SSEAlgorithm': 'aws:kms',
            'KMSMasterKeyID': 'arn:aws:kms:ap-southeast-1:...'
        }}]
    })
```

### 3. Data Security (MAS TRM Section 11 + PDPA)

Check for:
- [ ] No PII in logs (NRIC, credit cards, bank accounts)
- [ ] Data encryption at rest and in transit
- [ ] Input validation on all user inputs
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (output encoding)
- [ ] PDPA data classification compliance

**Fail patterns:**
```python
# FAIL: PII in logs
logger.info(f"Processing NRIC: {nric}")

# PASS: Masked PII
logger.info(f"Processing NRIC: {nric[:2]}****{nric[-1]}")

# FAIL: SQL injection
query = f"SELECT * FROM accounts WHERE id = {user_input}"

# PASS: Parameterized query
cursor.execute("SELECT * FROM accounts WHERE id = %s", (user_input,))
```

### 4. Network Security (MAS TRM Section 11.2)

Check for:
- [ ] No public endpoints for internal services
- [ ] Security group rules follow least privilege
- [ ] VPC endpoint usage for AWS services
- [ ] No 0.0.0.0/0 ingress rules on sensitive ports

### 5. Audit Logging (MAS TRM Section 15)

Check for:
- [ ] All financial transactions logged
- [ ] CloudTrail enabled for AWS API calls
- [ ] Log integrity protection enabled
- [ ] Minimum 90-day retention for audit logs
- [ ] No sensitive data in log messages

### 6. AI Governance (MAS AIRG)

Check for:
- [ ] AI-generated code has human review gate
- [ ] No bias in decision-making logic (credit scoring, fees)
- [ ] Explainability for financial decisions
- [ ] Prompt logging enabled for audit trail

## Output Format

After review, produce a compliance report:

```markdown
# MAS Compliance Review Report
Date: {date}
Reviewer: Kiro (AI-assisted)
Project: {project_name}

## Summary
- Total Checks: {total}
- Passed: {passed}
- Failed: {failed}
- Warnings: {warnings}

## Critical Issues
{list issues with MAS TRM section references}

## Recommendations
{list remediation steps}

## Regulatory References
- MAS TRM Guidelines (January 2021)
- PDPA (2012, amended 2020)
- MAS Guidelines on AI Risk Management (2025)
```

## Escalation

For compliance violations:
1. Document in review report
2. Block deployment if critical
3. Notify Security Team
4. Report to MAS if material breach (within 24 hours)

## References

- See `references/mas-trm-quick-ref.md` for section-by-section TRM reference
- See `references/pdpa-checklist.md` for PDPA data protection checklist
