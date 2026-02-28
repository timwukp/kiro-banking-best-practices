---
name: pii-detection
description: Detect and flag Personally Identifiable Information (PII) in code, data files, logs, and documentation. Use when scanning code for PII, preparing for PDPA compliance audit, reviewing data handling, or checking for data leakage in Singapore banking applications.
metadata:
  author: Data Protection Team
  version: 1.0.0
  regulations: PDPA 2012, MAS TRM Section 11
---

# PII Detection Skill

## Purpose

Scan code, configuration, and documentation for Singapore-specific PII patterns. Flag violations and provide remediation guidance aligned with PDPA requirements.

## Activation Triggers

- "Scan this code for PII"
- "Check for personal data in this file"
- "PDPA compliance scan"
- "Find sensitive data in this project"
- "Are there any NRIC numbers in the code?"

## Detection Patterns

### Singapore-Specific PII

| Type | Regex Pattern | Severity | Example |
|------|---------------|----------|---------|
| **NRIC** | `[STFG]\d{7}[A-Z]` | Critical | S1234567D |
| **FIN** | `[FG]\d{7}[A-Z]` | Critical | F1234567N |
| **SG Phone** | `(?:\+65)?[689]\d{7}` | High | +6591234567 |
| **SG Postal** | `\b\d{6}\b` (context-dependent) | Low | 238801 |

### Financial PII

| Type | Detection Method | Severity | Example |
|------|-----------------|----------|---------|
| **Credit Card** | Luhn algorithm + prefix match | Critical | 4111111111111111 |
| **Bank Account** | `\b\d{10,12}\b` (context) | High | 1234567890 |
| **SWIFT/BIC** | `[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?` | Medium | DBSSSGSG |

### General PII

| Type | Pattern | Severity |
|------|---------|----------|
| **Email** | Standard email regex | Medium |
| **AWS Access Key** | `AKIA[0-9A-Z]{16}` | Critical |
| **Private Key** | `BEGIN (RSA\|EC\|DSA )?PRIVATE KEY` | Critical |
| **Password in Code** | `password\s*=\s*["'][^"']+["']` | Critical |

## Scan Process

When activated:

1. **Identify file scope** - Determine which files to scan (all, staged, or specific)
2. **Run pattern matching** - Apply all detection patterns above
3. **Context analysis** - Distinguish real PII from:
   - Regex pattern definitions (in security code)
   - Test fixtures with example data
   - Documentation examples
4. **Report findings** with severity, location, and remediation

## Output Format

```markdown
# PII Detection Report
Date: {date}
Scope: {files scanned}

## Summary
- Files scanned: {count}
- PII instances found: {count}
- Critical: {count} | High: {count} | Medium: {count} | Low: {count}

## Findings

### Critical
| File | Line | Type | Value (masked) | Recommendation |
|------|------|------|----------------|----------------|
| src/auth.py | 42 | NRIC | S****567D | Use Secrets Manager |

## Remediation Guide
{specific fix instructions for each finding}
```

## Remediation Patterns

### Masking PII in Logs
```python
# FAIL
logger.info(f"Customer NRIC: {nric}")

# PASS
def mask_nric(nric: str) -> str:
    return f"{nric[0]}{'*' * 5}{nric[-2:]}"

logger.info(f"Customer NRIC: {mask_nric(nric)}")
```

### Removing PII from Error Messages
```python
# FAIL
raise ValueError(f"Invalid account {account_number}")

# PASS
raise ValueError("Invalid account number format")
```

### Secure Storage of PII
```python
# FAIL
config = {"db_password": "plaintext123"}

# PASS
import boto3
ssm = boto3.client('secretsmanager', region_name='ap-southeast-1')
config = {"db_password": ssm.get_secret_value(SecretId='/banking/db-password')}
```

## False Positive Handling

Exclude from detection:
- Files in `test/fixtures/` with clearly fake data
- Regex patterns defined in security scanning code
- Documentation with `# Example:` or `# Sample:` context
- UUID patterns that match postal code length
