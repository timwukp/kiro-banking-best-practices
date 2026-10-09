# Singapore PII and Secret Pattern Reference

Detailed reference for the `pii-detection` skill. It documents the format of each Singapore identifier, the detection patterns, the context rules that keep false positives down, the validation checks (NRIC/FIN checksum, Luhn) and the masking standard.

- **Two pattern forms.** The *PCRE form* works in Python `re`, Java, JavaScript, Perl and PCRE. The *ERE form* is POSIX extended regex for `grep -E` on macOS and GNU (no `\d`, no `\b`, no lookaround; word boundaries are written as `(^|[^A-Za-z0-9_])` and `([^A-Za-z0-9_]|$)`).
- **Flags.** The `flags` column is `i` (case-insensitive) or `-` (case-sensitive). Patterns never embed `(?i)`, because JavaScript does not support a leading `(?i)` inline flag: use `/.../i` or `new RegExp(p, "i")` in JavaScript, `re.IGNORECASE` in Python, `Pattern.CASE_INSENSITIVE` in Java and `grep -Ei` for ERE.
- **Tested.** `tests/patterns.test.sh` reads both blocks below and runs every pattern against the positive and negative fixtures in `tests/fixtures/pattern-cases.tsv` (ERE with `grep -E`; PCRE with `perl` when it is installed). It also checks that the pattern blocks in `SKILL.md` and in `mas-compliance-review/references/pdpa-checklist.md` match these blocks exactly. Change a pattern here, in those two blocks and in the fixtures together, then run the test.
- **Fixtures are synthetic.** NRIC/FIN examples use the sequential digits `1234567` with a valid check letter; card numbers are public test numbers; the AWS key is the AWS documentation example. Token-shaped values are assembled at runtime by the test, so none is committed.

## Pattern catalogue

| id | Detects | Severity | Context rule (apply before reporting) |
|----|---------|----------|---------------------------------------|
| `nric` | NRIC or FIN, all series (S, T, F, G, M) | Critical | None. Validate the checksum (below) |
| `fin` | FIN only (F, G, M) | Critical | Subset of `nric`: report each value once (see De-duplication) |
| `phone_sg` | Singapore phone number, with or without +65 | High | None. Corroborate with nearby words such as phone, mobile, tel, contact |
| `postal_sg` | Singapore postal code | Low | Built in: only after `Singapore`, `S(` or `postal`/`postcode` |
| `bank_account` | Bank account number | High | Built in: only within 20 characters after `account`, `acct` or `a/c` |
| `card_visa` | Visa, 13, 16 or 19 digits | Critical | Luhn check |
| `card_mastercard` | Mastercard 51-55 and 2221-2720, 16 digits | Critical | Luhn check |
| `card_amex` | American Express 34/37, 15 digits | Critical | Luhn check |
| `swift_bic` | SWIFT/BIC code (8 or 11 characters) | Low (not PII) | Built in: only after `SWIFT` or `BIC`; the code itself must be upper case |
| `email` | Email address | Medium | Ignore `example.com`, `example.org` and other reserved example domains |
| `aws_access_key_id` | AWS access key ID, long-term (`AKIA`) and temporary (`ASIA`) | Critical | None |
| `aws_secret_access_key` | AWS secret access key assignment | Critical | None |
| `github_token` | GitHub classic (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`) and fine-grained (`github_pat_`) tokens | Critical | None |
| `private_key` | PEM/OpenSSH/PGP private key header (RSA, EC, DSA, OPENSSH, ENCRYPTED, PKCS#8) | Critical | None |
| `password_assignment` | Password or secret assigned a quoted literal (`=`, `:`, JSON `"key": "value"`) | Critical | Ignore empty values and references such as `os.environ[...]` (they do not match) |

### PCRE form

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

### ERE form (`grep -E`)

Run with `LC_ALL=C grep -E -f <pattern-file>` (one pattern per file), adding `-i` when `flags` is `i`. `-e '<pattern>'` also works with GNU and BSD grep, but the `private_key` pattern starts with `-----`, which some reimplementations (for example ugrep) parse as an option even after `-e`; `-f` avoids this. `LC_ALL=C` keeps `[A-Z]` from matching lower-case letters in some locales.

<!-- pii-patterns:ere:start -->
```text
# id                    flags  pattern (POSIX ERE)
nric                    -      (^|[^A-Za-z0-9_])[STFGM][0-9]{7}[A-Z]([^A-Za-z0-9_]|$)
fin                     -      (^|[^A-Za-z0-9_])[FGM][0-9]{7}[A-Z]([^A-Za-z0-9_]|$)
phone_sg                -      (^|[^A-Za-z0-9_+])(\+65[ -]?)?[3689][0-9]{3}[ -]?[0-9]{4}([^A-Za-z0-9_]|$)
postal_sg               i      (singapore|(^|[^A-Za-z0-9_])s\(|(^|[^A-Za-z0-9_])post(al)?([[:space:]]*code)?)[^0-9]{0,12}[0-9]{6}([^A-Za-z0-9_]|$)
bank_account            i      (^|[^A-Za-z0-9_])(accounts?|acct|a/c)[^0-9]{0,20}[0-9]([- ]?[0-9]){9,11}([^A-Za-z0-9_]|$)
card_visa               -      (^|[^A-Za-z0-9_])4([0-9]{12}|[0-9]{3}([ -]?[0-9]{4}){3}([ -]?[0-9]{3})?)([^A-Za-z0-9_]|$)
card_mastercard         -      (^|[^A-Za-z0-9_])(5[1-5][0-9]{2}|222[1-9]|22[3-9][0-9]|2[3-6][0-9]{2}|27[01][0-9]|2720)([ -]?[0-9]{4}){3}([^A-Za-z0-9_]|$)
card_amex               -      (^|[^A-Za-z0-9_])3[47][0-9]{2}[ -]?[0-9]{6}[ -]?[0-9]{5}([^A-Za-z0-9_]|$)
swift_bic               -      ([Ss][Ww][Ii][Ff][Tt]|[Bb][Ii][Cc])[^A-Z0-9]{0,12}[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?([^A-Za-z0-9_]|$)
email                   -      [A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}
aws_access_key_id       -      (^|[^A-Za-z0-9_])(AKIA|ASIA)[0-9A-Z]{16}([^A-Za-z0-9_]|$)
aws_secret_access_key   i      (aws_?)?secret_?access_?key["']?[[:space:]]*[:=][[:space:]]*["']?[A-Za-z0-9/+]{40}([^A-Za-z0-9/+]|$)
github_token            -      (^|[^A-Za-z0-9_])(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})
private_key             -      -----BEGIN ([A-Z]+ )*PRIVATE KEY( BLOCK)?-----
password_assignment     i      (password|passwd|pwd|secret)[A-Za-z0-9_]*["']?[[:space:]]*[:=][[:space:]]*["'][^"']+["']
```
<!-- pii-patterns:ere:end -->

## Applying the patterns

1. **Match**, then apply the context rule of the pattern (table above).
2. **Validate** where a check exists: NRIC/FIN checksum, Luhn for cards. A value that passes is a confirmed finding. A value that fails is probably not a real identifier, so lower its severity by one level, but still report it if it is in production data, logs or prompts (it may be a mistyped real value).
3. **De-duplicate.** Report each matched value once, under its most specific type:
   - every FIN also matches `nric`: report it once, typed by its prefix (S/T = NRIC, F/G/M = FIN);
   - a card number near the word "account" can also match `bank_account`: report it as a card if it passes Luhn.
4. **Skip known non-findings** (see False positives) and say in the report which ones were skipped and why.

## National identifiers

### NRIC and FIN (pattern ids `nric`, `fin`)

- **Format:** prefix letter + 7 digits + check letter, for example `S1234567D`.
- **Prefixes:**
  - `S`: Singapore citizens and permanent residents born before 1 January 2000
  - `T`: Singapore citizens and permanent residents born on or after 1 January 2000
  - `F`: foreigners issued a long-term pass (FIN) before 1 January 2000
  - `G`: foreigners issued a FIN from 1 January 2000 to 31 December 2021
  - `M`: foreigners issued a FIN on or after 1 January 2022
- **Checksum** (ICA does not publish the algorithm; this is the publicly documented one, also implemented in the Singapore Government's FormSG validator, `opengovsg/FormSG`, `packages/shared/utils/nric-validation.ts`):
  1. Multiply the 7 digits by the weights `[2, 7, 6, 5, 4, 3, 2]` and add the products.
  2. Add an offset: `0` for S and F, `4` for T and G, `3` for M.
  3. Let `r = sum % 11`.
  4. Check letter: S/T `"JZIHGFEDCBA"[r]`; F/G `"XWUTRQPNMLK"[r]`; M `"KLJNPQRTUWX"[10 - r]` (the M table is indexed from the end; equivalently `"XWUTRQPNJLK"[r]`).
  - The S/T/F/G tables are long established. The M-series table and indexing follow FormSG and are not published by ICA: **verify against ICA** before relying on them to reject values.
- **Checksum-valid synthetic examples** (sequential digits; used in the fixtures): `S1234567D`, `T1234567J`, `F1234567N`, `G1234567X`, `M1234567K`.
- **Classification:** Critical. Never in logs, prompts, error messages, analytics or test fixtures built from production data.
- **Handling rules:**
  - Store the full NRIC/FIN only where the law requires it (for banks, for example, customer due diligence under MAS Notice 626) or where identity must be established to a high degree of fidelity (PDPC Advisory Guidelines on the PDPA for NRIC and other National Identification Numbers, 31 August 2018). Everywhere else remove it, mask it (`S****567D`) or replace it with a token. Secrets Manager is for credentials, not for customer identifiers.
  - Do not use NRIC numbers as an authenticator, password or default password: PDPC and CSA advised organisations to cease using NRIC numbers for authentication by 31 December 2026 (joint advisory, PDPC press release, 2 February 2026).

## Financial identifiers

### Payment card numbers (pattern ids `card_visa`, `card_mastercard`, `card_amex`)

- **Visa:** starts with 4; 13, 16 or 19 digits. 16 and 19 digits may be grouped 4-4-4-4(-3) with spaces or dashes.
- **Mastercard:** starts with 51-55 or 2221-2720; 16 digits, grouped 4-4-4-4.
- **American Express:** starts with 34 or 37; 15 digits, grouped 4-6-5.
- **Luhn check (recommended):** strip spaces and dashes; from the rightmost digit, double every second digit, subtract 9 from any result above 9, add everything; valid when the total is a multiple of 10. The test script implements it (`luhn_ok`).
- **Public test numbers used in the fixtures** (Luhn-valid): `4111111111111111`, `4222222222222`, `4111111111111111110`, `5555555555554444`, `5105105105105100`, `2223003122003222`, `2221000000000009`, `2720999999999996`, `378282246310005`, `371449635398431`.
- **Classification:** Critical (PCI DSS scope as well as PDPA).

### Bank account numbers (pattern id `bank_account`)

- **Approach (one rule, used in every file):** a run of 10-12 digits, optionally separated by single hyphens or spaces, that appears within 20 characters after the keyword `account`, `accounts`, `acct` or `a/c` (any case). A bare digit run is never reported on its own.
- **Why context is required:** bare 10-12 digit runs have a very high false-positive rate: Unix timestamps in seconds (10 digits), phone numbers with country code (`6591234567`), order and reference numbers, and IDs. Even with the keyword, expect false positives such as `account created 1696800000`; confirm before reporting.
- **Per-bank formats (unverified):** commonly cited lengths are DBS 10 digits, POSB 9 digits, OCBC 10 or 12 digits and UOB 10 digits. These have not been verified with the banks and are not used by the pattern; confirm with your institution's own account-number specification and adjust the digit range if needed.
- **Classification:** High.

### SWIFT/BIC codes (pattern id `swift_bic`)

- **Format:** 4-letter institution code + 2-letter country code + 2-character location code + optional 3-character branch code (8 or 11 characters), upper case.
- **Context:** the code must be upper case and appear within 12 characters after `SWIFT` or `BIC` (keyword in any case). Without the keyword, any 8- or 11-letter upper-case word (for example `PASSWORD`, `ENCRYPTED`) would match.
- **Examples:** `DBSSSGSG` (DBS), `OCBCSGSG` (OCBC), `UOVBSGSG` (UOB).
- **Classification:** Low. A BIC identifies a bank, not a person, and is public. Report it only as context (for example, next to an account number).

## Contact information

### Singapore phone numbers (pattern id `phone_sg`)

- **Format:** 8 digits; optional `+65` country code; optional single space or dash after `+65` and between the two 4-digit groups (`91234567`, `9123 4567`, `+6591234567`, `+65 9123 4567`, `+65-9123-4567`).
- **First digit:** `6` fixed line; `8` and `9` mobile; `3` business IP telephony (VoIP), introduced in 2005. Source: Wikipedia, *Telephone numbers in Singapore*; IMDA lists `3`, `6`, `8` and `9` as number levels but its National Numbering Plan page could not be read to confirm the service mapping (checked 2026-10-09). Confirm against the IMDA National Numbering Plan.
- **Not matched:** numbers starting with other digits, 7- or 9-digit runs, and `+65` followed by a number starting with 1, 2, 4, 5 or 7.
- **Classification:** High.

### Singapore postal codes (pattern id `postal_sg`)

- **Format:** 6 digits; the first two digits are the postal sector (01-82).
- **Context:** only after `Singapore`, `S(` (as in `S(238801)`) or `postal`/`postal code`/`postcode` (any case), within 12 characters. A bare 6-digit number is never reported on its own: it is far more often an ID, an amount, a time (`235959`) or a date (`091026`).
- **Classification:** Low on its own; Medium when it appears with a name or unit number (a full address).

### Email addresses (pattern id `email`)

- **Classification:** Medium. Ignore reserved example domains (`example.com`, `example.org`, `example.net`) and obvious placeholders.

## Credentials and secrets

| id | What it catches | Notes |
|----|-----------------|-------|
| `aws_access_key_id` | `AKIA...` (long-term) and `ASIA...` (temporary STS) access key IDs, 20 characters | Upper case only. `AKIAIOSFODNN7EXAMPLE` is the AWS documentation example |
| `aws_secret_access_key` | `aws_secret_access_key = ...`, `AWS_SECRET_ACCESS_KEY=...`, `"SecretAccessKey": "..."` with a 40-character value | The value alone is not detectable reliably; the assignment is |
| `github_token` | `ghp_`/`gho_`/`ghu_`/`ghs_`/`ghr_` + 36 or more characters; `github_pat_` + 22 or more characters | |
| `private_key` | `-----BEGIN ... PRIVATE KEY-----` headers: PKCS#8 (no algorithm), RSA, EC, DSA, OPENSSH, ENCRYPTED, and PGP `PRIVATE KEY BLOCK` | Public keys and certificates do not match |
| `password_assignment` | `password = "..."`, `PASSWORD: '...'`, `"db_password": "..."`, `client_secret = "..."` | Unquoted `.env` values are not matched; keep `.env` files out of source control |

- **Classification:** Critical. Block the commit, rotate the credential (removing it from the file does not remove it from git history), and move it to AWS Secrets Manager or SSM Parameter Store.

## False positives

Skip, and list as skipped in the report:
- values inside regex or pattern definitions in security tooling (such as this file and the test fixtures);
- clearly synthetic test data in `test/fixtures/`, `tests/fixtures/` or files named `*fake*`/`*sample*`, when it uses the published examples above;
- documentation examples marked `Example:` or `Sample:`;
- the AWS documentation example keys (they contain `EXAMPLE`).

Do not skip values in logs, data exports, prompts or production configuration, even if they look like examples.

## Masking standard

| Data type | Original | Masked | Rule |
|-----------|----------|--------|------|
| NRIC/FIN | `S1234567D` | `S****567D` | First letter, four asterisks, last 3 digits and the check letter |
| Credit card | `4111111111111111` | `************1111` | Last 4 digits only |
| Phone | `91234567` | `****4567` | Last 4 digits only |
| Email | `john@example.com` | `j***@example.com` | First character of the local part, then the domain |
| Bank account | `1234567890` | `******7890` | Last 4 digits only |

```python
def mask_nric(nric: str) -> str:
    """S1234567D -> S****567D (first letter, four asterisks, last 3 digits and check letter)."""
    return f"{nric[0]}****{nric[-4:]}"
```

A masked value is still personal data when it can be linked to other data about the person. Masking is for display and logs; it is not anonymisation.
