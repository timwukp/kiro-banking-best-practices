---
name: mas-compliance-review
description: Map code, infrastructure-as-code (AWS CDK, CloudFormation, Terraform) and system designs to Singapore regulatory requirements, namely MAS Technology Risk Management (TRM) Guidelines sections, MAS Notices FSM-N05 and FSM-N06, PDPA obligations and the MAS Guidelines on Artificial Intelligence Risk Management. Use when asked to review this code or infrastructure for MAS compliance, check MAS TRM requirements, map controls or findings to TRM sections, validate banking security standards against MAS, review a CDK or Terraform stack for MAS alignment, check PDPA data protection or cross-border transfer obligations, prepare for a MAS audit or inspection, produce compliance evidence, or answer whether something is compliant with Singapore banking regulations. Not for line-by-line application code review or pull request approval (use banking-code-review), and not for scanning or masking PII and secrets (use pii-detection).
metadata:
  author: Security Architecture Team
  version: 1.3.0
  mas_version: TRM_2021
  regulations: MAS TRM, PDPA, MAS Guidelines on Artificial Intelligence Risk Management, MAS Outsourcing Guidelines
---

# MAS Compliance Review Skill

## Purpose

Map code, infrastructure-as-code and designs in Kiro-assisted development to Singapore banking regulations, and report each finding against the MAS TRM section, MAS notice or PDPA obligation it relates to.

## Scope and related skills

- **This skill:** regulatory and infrastructure mapping, including:
  - MAS TRM sections, MAS Notices FSM-N05/FSM-N06 and PDPA obligations;
  - infrastructure-as-code review (IAM, KMS, networking, logging, backup);
  - audit preparation and compliance evidence.
- **banking-code-review:** use it for application code review: secure coding, OWASP risks, transaction logic, and a pull request verdict against approval criteria. When this review finds application-level issues, point the user to that skill rather than doing a line-by-line review here.
- **pii-detection:** use it to find, mask or redact NRIC/FIN, card numbers, account numbers and secrets. This skill cites its findings (MAS TRM 11.1, PDPA) but does not run the scan.
- The AI review is an aid: findings are inputs to the institution's own compliance assessment, not a compliance sign-off.

## Review Process

When activated, perform these checks in order:

### 1. Access Control (MAS TRM Section 9)

Check for:
- [ ] Multi-factor authentication implementation (TRM 9.1; administrative accounts 9.2; customer authentication for online financial services 14.2)
- [ ] Privileged access management (no hardcoded admin credentials) (TRM 9.2)
- [ ] Session timeout configuration (example institutional policy, not prescribed by MAS TRM: max 15 minutes for banking apps)
- [ ] Failed login lockout (example institutional policy, not prescribed by MAS TRM: max 3 attempts)
- [ ] Least privilege principle in IAM policies (TRM 9.1); in IaC, no `"Action": "*"` or `"Resource": "*"` without a documented reason

**Fail patterns:**
```python
# FAIL: Hardcoded credentials
password = "admin123"
aws_key = "AKIA..."

# PASS: Use AWS Secrets Manager
import boto3
secrets = boto3.client('secretsmanager', region_name='ap-southeast-1')
api_key = secrets.get_secret_value(SecretId='/banking/prod/api-key')['SecretString']
```

### 2. Cryptography (MAS TRM Section 10)

Check for:
- [ ] TLS 1.2 or higher for all connections (TLS 1.3 recommended) (TRM 10.1)
- [ ] AWS KMS customer-managed keys for data at rest (institutional policy for regulated data; TRM 10.2 key management)
- [ ] No use of deprecated algorithms: MD5, SHA-1, DES, 3DES, RC4, SSLv3, TLS 1.0/1.1 (TRM 10.1)
- [ ] Proper key rotation configuration (TRM 10.2)
- [ ] No hardcoded encryption keys

**Fail patterns:**

Since 5 January 2023, Amazon S3 encrypts every new object with SSE-S3 by default, so a new bucket is never unencrypted. The finding below is that the bucket does not use **SSE-KMS with a customer-managed key**, which an institutional policy for regulated data typically requires (key policy, rotation and CloudTrail audit of key use under TRM 10.2).

```python
import boto3

s3 = boto3.client('s3', region_name='ap-southeast-1')

# FAIL (against a CMK policy): bucket relies on the default SSE-S3 encryption
s3.create_bucket(Bucket='banking-data',
                 CreateBucketConfiguration={'LocationConstraint': 'ap-southeast-1'})

# PASS: set default encryption to SSE-KMS with a customer-managed key
# (create_bucket does not accept an encryption configuration; set it with put_bucket_encryption)
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
    })
```

In AWS CDK, the equivalent is `encryption: s3.BucketEncryption.KMS` with `encryptionKey` set to a `kms.Key` that has `enableKeyRotation: true`.

### 3. Data Security (MAS TRM 11.1 + PDPA) and Secure Coding (MAS TRM 6.1)

Check for:
- [ ] No PII in logs (NRIC, credit cards, bank accounts); use the pii-detection skill for the scan
- [ ] Data encryption at rest and in transit
- [ ] Input validation on all user inputs (TRM 6.1)
- [ ] SQL injection prevention (parameterized queries) (TRM 6.1)
- [ ] XSS prevention (output encoding) (TRM 6.1)
- [ ] PDPA data classification compliance
- [ ] Full NRIC/FIN stored only where the law requires it (for banks, for example, customer due diligence under MAS Notice 626); elsewhere removed, masked or tokenized
- [ ] NRIC numbers not used as an authenticator or default password (PDPC/CSA advisory: organisations to cease using NRIC numbers for authentication by 31 Dec 2026)

**Fail patterns:**
```python
# FAIL: PII in logs
logger.info(f"Processing NRIC: {nric}")

# PASS: Masked PII (masking standard S1234567D -> S****567D:
# first letter, four asterisks, last 3 digits and the check letter)
logger.info(f"Processing NRIC: {nric[0]}****{nric[-4:]}")

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
- [ ] In IaC: no public subnets, internet gateways or NAT gateways where the design is private-only (this repository's convention)

### 5. Audit Logging (MAS TRM 12.2 Cyber Event Monitoring and Detection)

The logs also serve as evidence for the independent IT audit function (TRM 15.1).

Check for:
- [ ] All financial transactions logged
- [ ] CloudTrail enabled for AWS API calls
- [ ] Log integrity protection enabled (CloudTrail log file validation, S3 Object Lock or equivalent)
- [ ] Audit log retention defined (example institutional policy, not prescribed by MAS TRM: minimum 90 days)
- [ ] No sensitive data in log messages
- [ ] In IaC: log buckets and KMS keys use a RETAIN removal policy

### 6. AI Governance (MAS Guidelines on Artificial Intelligence Risk Management)

Check for:
- [ ] AI-generated code has human review gate (TRM 6.1, 6.3), enforced by branch protection rather than by the agent
- [ ] No bias in decision-making logic (credit scoring, fees)
- [ ] Explainability for financial decisions
- [ ] Prompt logging enabled for the audit trail: this is a Kiro administrator console setting; ask for evidence (the setting, the prompt-log bucket and its retention), because the agent cannot see or change it

## Output Format

After review, produce a compliance report:

```markdown
# MAS Compliance Review Report
Date: {date}
Reviewer: Kiro (AI-assisted); findings to be confirmed by {human_reviewer}
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
