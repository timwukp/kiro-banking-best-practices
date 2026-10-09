---
name: mas-compliance-review
description: Review code and infrastructure for MAS Technology Risk Management Guidelines compliance. Use when reviewing code for banking compliance, preparing for MAS audit, validating security controls, checking TRM alignment, or conducting compliance assessments for Singapore financial institutions.
metadata:
  author: Security Architecture Team
  version: 1.2.0
  mas_version: TRM_2021
  regulations: MAS TRM, PDPA, MAS Guidelines on Artificial Intelligence Risk Management, MAS Outsourcing Guidelines
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
- [ ] Multi-factor authentication implementation (TRM 9.1; administrative accounts 9.2; customer authentication for online financial services 14.2)
- [ ] Privileged access management (no hardcoded admin credentials) (TRM 9.2)
- [ ] Session timeout configuration (example institutional policy, not prescribed by MAS TRM: max 15 minutes for banking apps)
- [ ] Failed login lockout (example institutional policy, not prescribed by MAS TRM: max 3 attempts)
- [ ] Least privilege principle in IAM policies (TRM 9.1)

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
- [ ] Proper key rotation configuration (TRM 10.2)
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

### 3. Data Security (MAS TRM 11.1 + PDPA) and Secure Coding (MAS TRM 6.1)

Check for:
- [ ] No PII in logs (NRIC, credit cards, bank accounts)
- [ ] Data encryption at rest and in transit
- [ ] Input validation on all user inputs (TRM 6.1)
- [ ] SQL injection prevention (parameterized queries) (TRM 6.1)
- [ ] XSS prevention (output encoding) (TRM 6.1)
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

### 5. Audit Logging (MAS TRM 12.2 Cyber Event Monitoring and Detection)

The logs also serve as evidence for the independent IT audit function (TRM 15.1).

Check for:
- [ ] All financial transactions logged
- [ ] CloudTrail enabled for AWS API calls
- [ ] Log integrity protection enabled
- [ ] Audit log retention defined (example institutional policy, not prescribed by MAS TRM: minimum 90 days)
- [ ] No sensitive data in log messages

### 6. AI Governance (MAS Guidelines on Artificial Intelligence Risk Management)

Check for:
- [ ] AI-generated code has human review gate (TRM 6.1, 6.3)
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
- MAS Guidelines on Artificial Intelligence Risk Management (published 7 Oct 2026, effective 7 Oct 2027)
```

## Escalation

For compliance violations:
1. Document in review report
2. Block deployment if critical
3. Notify Security Team
4. Notify MAS not later than 1 hour after discovery of a relevant incident (MAS Notice FSM-N05 para 7; root-cause and impact analysis report within 14 days, para 8)

## References

- See `references/mas-trm-quick-ref.md` for section-by-section TRM reference
- See `references/pdpa-checklist.md` for PDPA data protection checklist
