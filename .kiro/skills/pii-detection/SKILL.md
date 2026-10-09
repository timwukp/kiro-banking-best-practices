---
name: pii-detection
description: Detect, mask and redact Singapore personal data (PII) and secrets in source code, configuration, logs, test fixtures and documentation. Use when asked to scan this code for PII, check a file for personal data, run a PDPA compliance scan, find sensitive data in a project, or check whether there are NRIC or FIN numbers, credit card numbers, bank account numbers, Singapore phone numbers, email addresses or postal codes in the code; when asked to mask, redact or tokenize NRIC, FIN, card or account numbers in logs, error messages or test data; and when asked to find hardcoded secrets such as AWS access keys, AWS secret keys, private keys, GitHub tokens or passwords before a commit. Not for mapping findings to MAS TRM sections or reviewing infrastructure (use mas-compliance-review), and not for a full secure code review or pull request verdict (use banking-code-review).
metadata:
  author: Data Protection Team
  version: 1.1.0
  regulations: PDPA 2012, MAS TRM 11.1 (Data Security)
---

# PII Detection Skill

## Purpose

Find Singapore personal data and secrets in code, configuration, logs, test data and documentation. Report each finding with its severity, location and a masked value, and give PDPA-aligned remediation (remove, mask or tokenize personal data; rotate and vault secrets).

## Scope and related skills

- **This skill:** detecting, masking and redacting PII and secrets.
- **mas-compliance-review:** use it to map findings to MAS TRM sections, PDPA obligations and MAS notices, or to review infrastructure-as-code.
- **banking-code-review:** use it for a full secure code review of a change or a pull request verdict. That review calls for a clean PII scan, which is this skill.
- **Never echo a full value.** Report NRIC/FIN, card and account numbers masked, and secrets by type and location only, in the chat and in the report. Kiro stores and processes prompts and responses in its profile region (`us-east-1` or `eu-central-1`), not in Singapore. Scan files in place; do not ask the user to paste personal data into the chat.

## Detection Patterns

| Type | id | Severity | Context rule | Synthetic example |
|------|----|----------|--------------|-------------------|
| NRIC/FIN (S, T, F, G, M series) | `nric` | Critical | Validate the checksum | `S1234567D`, `M1234567K` |
| FIN only (F, G, M) | `fin` | Critical | Subset of `nric`: report once | `F1234567N` |
| Singapore phone | `phone_sg` | High | Corroborate with phone/mobile/tel/contact | `+65 9123 4567` |
| Bank account | `bank_account` | High | Only within 20 characters after account/acct/a/c; high false-positive rate | `Acct No. 123-456789-0` |
| Credit card (Visa, Mastercard, Amex) | `card_visa`, `card_mastercard`, `card_amex` | Critical | Luhn check | `4111 1111 1111 1111` |
| Email | `email` | Medium | Ignore example.com and other reserved example domains | `john@example.com` |
| Singapore postal code | `postal_sg` | Low | Only after Singapore, `S(` or postal/postcode | `Singapore 238801` |
| SWIFT/BIC | `swift_bic` | Low (not PII) | Only after SWIFT or BIC; code must be upper case | `SWIFT: DBSSSGSG` |
| AWS access key ID (`AKIA`, `ASIA`) | `aws_access_key_id` | Critical | None | `AKIAIOSFODNN7EXAMPLE` (AWS docs example) |
| AWS secret access key assignment | `aws_secret_access_key` | Critical | None | `aws_secret_access_key = ...` |
| GitHub token (`ghp_`, `github_pat_` and others) | `github_token` | Critical | None | (no committed example) |
| Private key header (RSA, EC, DSA, OPENSSH, ENCRYPTED, PKCS#8, PGP) | `private_key` | Critical | None | (no committed example) |
| Password or secret literal (`=`, `:`, JSON) | `password_assignment` | Critical | Empty values and environment lookups do not match | `"db_password": "..."` |

Patterns (PCRE form; `flags` is `i` for case-insensitive, `-` for case-sensitive). Apply the flag with the engine's option (`/.../i` or `new RegExp(p, "i")` in JavaScript, `re.IGNORECASE` in Python, `grep -i`): JavaScript does not support a leading `(?i)` inline flag, so the patterns never embed one. POSIX ERE versions for `grep -E` are in `references/singapore-pii-patterns.md`.

<!-- pii-patterns:pcre:start -->
```text
# id                    flags  pattern (Python re, Java, JavaScript, Perl, PCRE)
nric                    -      \b[STFGM]\d{7}[A-Z]\b
fin                     -      \b[FGM]\d{7}[A-Z]\b
phone_sg                -      (?<![\w+])(?:\+65[ -]?)?[3689]\d{3}[ -]?\d{4}\b
postal_sg               i      (?:singapore|\bs\(|\bpost(?:al)?(?:\s*code)?)[^\d\n]{0,12}\d{6}\b
bank_account            i      \b(?:accounts?|acct|a/c)[^\d\n]{0,20}\d(?:[- ]?\d){9,11}\b
card_visa               -      \b4(?:\d{12}|\d{3}(?:[ -]?\d{4}){3}(?:[ -]?\d{3})?)\b
card_mastercard         -      \b(?:5[1-5]\d{2}|222[1-9]|22[3-9]\d|2[3-6]\d{2}|27[01]\d|2720)(?:[ -]?\d{4}){3}\b
card_amex               -      \b3[47]\d{2}[ -]?\d{6}[ -]?\d{5}\b
swift_bic               -      (?:[Ss][Ww][Ii][Ff][Tt]|[Bb][Ii][Cc])[^A-Z0-9\n]{0,12}[A-Z]{6}[A-Z0-9]{2}(?:[A-Z0-9]{3})?\b
email                   -      [A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}
aws_access_key_id       -      \b(?:AKIA|ASIA)[0-9A-Z]{16}\b
aws_secret_access_key   i      (?:aws_?)?secret_?access_?key["']?\s*[:=]\s*["']?[A-Za-z0-9/+]{40}(?![A-Za-z0-9/+])
github_token            -      \b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})
private_key             -      -----BEGIN ([A-Z]+ )*PRIVATE KEY( BLOCK)?-----
password_assignment     i      (?:password|passwd|pwd|secret)[A-Za-z0-9_]*["']?\s*[:=]\s*["'][^"'\n]+["']
```
<!-- pii-patterns:pcre:end -->

The patterns are tested: `bash .kiro/skills/pii-detection/tests/patterns.test.sh` runs both forms against positive and negative fixtures and checks that this block matches the reference. If you change a pattern, change it in the reference, here, in `mas-compliance-review/references/pdpa-checklist.md` and in the fixtures, then run the test.

### Validation and de-duplication

- **NRIC/FIN checksum:** weights `[2,7,6,5,4,3,2]`; add 4 for T and G, 3 for M; `r = sum % 11`; check letter S/T `JZIHGFEDCBA[r]`, F/G `XWUTRQPNMLK[r]`, M `KLJNPQRTUWX[10 - r]`. The M-series table is not published by ICA (verify against ICA); see the reference for details.
- **Cards:** run the Luhn check after stripping spaces and dashes.
- A value that fails its check is probably not real: lower its severity by one level, but still report it in production data, logs or prompts.
- **De-duplicate:** every FIN also matches `nric`; report it once, typed by prefix (S/T = NRIC, F/G/M = FIN). A card number near the word "account" may also match `bank_account`; report it as a card if it passes Luhn.

## Scan Process

When activated:

1. **Identify file scope:** all files, staged files (`git diff --cached --name-only`), or the files the user named.
2. **Run pattern matching:** apply every pattern above (for a shell scan, use the ERE forms in the reference with `LC_ALL=C grep -nE -f <pattern-file>`, plus `-i` where flagged).
3. **Apply context rules, validate and de-duplicate** as described above.
4. **Separate real findings from non-findings:**
   - regex or pattern definitions in security tooling;
   - published synthetic examples in test fixtures and documentation;
   - the AWS documentation example keys (they contain `EXAMPLE`).
5. **Report** with severity, location, masked value and remediation.

## Output Format

```markdown
# PII Detection Report
Date: {date}
Scope: {files scanned}

## Summary
- Files scanned: {count}
- Findings: {count} (Critical: {count} | High: {count} | Medium: {count} | Low: {count})
- Skipped as non-findings: {count} (listed at the end with the reason)

## Findings

### Critical
| File | Line | Type | Value (masked) | Recommendation |
|------|------|------|----------------|----------------|
| src/onboarding.py | 42 | NRIC | S****567D | Remove the literal; use synthetic test data or a tokenized customer reference |
| config/app.py | 7 | AWS access key ID | (secret, not shown) | Rotate the key, then load it from AWS Secrets Manager |

## Remediation Guide
{specific fix instructions for each finding}
```

## Remediation Patterns

### Masking PII in logs

Masking standard for NRIC/FIN: first letter, four asterisks, last 3 digits and the check letter (`S1234567D` -> `S****567D`).

```python
# FAIL
logger.info(f"Customer NRIC: {nric}")

# PASS
def mask_nric(nric: str) -> str:
    """S1234567D -> S****567D."""
    return f"{nric[0]}****{nric[-4:]}"

logger.info(f"Customer NRIC: {mask_nric(nric)}")
```

Other masks: card `************1111`, phone `****4567`, email `j***@example.com`, bank account `******7890` (last 4 digits only).

### Removing PII from error messages
```python
# FAIL
raise ValueError(f"Invalid account {account_number}")

# PASS
raise ValueError("Invalid account number format")
```

### NRIC/FIN found in code, data or test fixtures

An NRIC or FIN is customer data, not a credential: do not move it to Secrets Manager. Instead:
- **Remove** it from source code, comments, test fixtures and sample data; use synthetic values (such as `S1234567D`) or generated test data.
- **Mask** it (`S****567D`) where a person must recognise the record (screens, letters, logs that need it at all).
- **Tokenize** it (replace with an internal customer reference) where systems need to join records.
- Store the full number only where the law requires it (for banks, for example, customer due diligence under MAS Notice 626) or where identity must be established to a high degree of fidelity (PDPC Advisory Guidelines on the PDPA for NRIC and other National Identification Numbers, 31 August 2018).
- Flag any use of an NRIC as an authenticator, password or default password: PDPC and CSA advised organisations to cease using NRIC numbers for authentication by 31 December 2026 (joint advisory, PDPC press release, 2 February 2026).

### Secrets found in code
```python
# FAIL
config = {"db_password": "plaintext123"}

# PASS: load the secret at runtime from AWS Secrets Manager
import boto3

secrets = boto3.client('secretsmanager', region_name='ap-southeast-1')
config = {"db_password": secrets.get_secret_value(SecretId='/banking/db-password')['SecretString']}
```

Deleting a committed secret does not remove it from git history: rotate or revoke it first, then remove it.

## False Positive Handling

Skip, and list as skipped in the report:
- regex patterns defined in security scanning code (such as this skill's references and tests);
- clearly synthetic test data in `test/fixtures/` or `tests/fixtures/` that uses the published examples;
- documentation examples marked `Example:` or `Sample:`;
- the AWS documentation example keys.

Never skip values in logs, data exports, prompts or production configuration, even if they look like examples.

## References

- See `references/singapore-pii-patterns.md` for each identifier's format, the NRIC/FIN checksum, the ERE patterns for `grep -E`, the context rules and the masking standard.
- Run `tests/patterns.test.sh` after changing any pattern.
