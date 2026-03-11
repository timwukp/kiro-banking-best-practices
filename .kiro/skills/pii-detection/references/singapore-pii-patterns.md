# Singapore PII Pattern Reference

## National Identifiers

### NRIC (National Registration Identity Card)
- **Format:** Letter + 7 digits + checksum letter
- **Regex:** `[STFG]\d{7}[A-Z]`
- **Prefixes:**
  - `S` - Citizens born before 2000
  - `T` - Citizens born 2000 onwards
  - `F` - Foreigners issued before 2000
  - `G` - Foreigners issued 2000 onwards
- **Checksum:** Modulus 11 with weights [2,7,6,5,4,3,2]
- **PDPA Classification:** Critical - must never appear in logs, prompts, or error messages

### FIN (Foreign Identification Number)
- **Format:** Same as NRIC but starts with F or G
- **Regex:** `[FG]\d{7}[A-Z]`
- **PDPA Classification:** Critical

## Financial Identifiers

### Credit Card Numbers
- **Detection:** Luhn algorithm validation + prefix matching
- **Visa:** `4\d{12}(?:\d{3})?`
- **Mastercard:** `5[1-5]\d{14}` or `2[2-7]\d{14}`
- **AMEX:** `3[47]\d{13}`
- **PDPA Classification:** Critical

### Singapore Bank Account Numbers
- **DBS/POSB:** 10 digits (prefix 0, 1, or 5)
- **OCBC:** 10-12 digits (prefix 5, 6, or 7)
- **UOB:** 10-13 digits (prefix 1, 2, 3, or 9)
- **General regex:** `\b\d{10,13}\b` (requires context analysis to reduce false positives)
- **PDPA Classification:** High

### SWIFT/BIC Codes
- **Format:** 8 or 11 alphanumeric characters
- **Regex:** `[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?`
- **Common SG banks:** DBSSSGSG (DBS), OCBCSGSG (OCBC), UOVBSGSG (UOB)
- **PDPA Classification:** Low (public information)

## Contact Information

### Singapore Phone Numbers
- **Mobile:** `[89]\d{7}` (starts with 8 or 9)
- **Landline:** `6\d{7}` (starts with 6)
- **With country code:** `(?:\+65)?[689]\d{7}`
- **PDPA Classification:** High

### Singapore Postal Codes
- **Format:** 6 digits
- **Regex:** `\b\d{6}\b`
- **Range:** 01xxxx to 82xxxx
- **PDPA Classification:** Low (high false positive rate - use context analysis)

### Email Addresses
- **Regex:** `[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}`
- **PDPA Classification:** Medium

## Credential Patterns

### AWS Access Keys
- **Regex:** `AKIA[0-9A-Z]{16}`
- **Classification:** Critical - immediate block and alert

### Private Keys
- **Regex:** `-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----`
- **Classification:** Critical - immediate block and alert

### Passwords in Code
- **Regex:** `(?i)(password|passwd|pwd|secret)\s*[=:]\s*["'][^"']+["']`
- **Classification:** Critical - immediate block and alert

## Masking Standards

| Data Type | Original | Masked |
|-----------|----------|--------|
| NRIC | S1234567D | S\*\*\*\*567D |
| Credit Card | 4111111111111111 | \*\*\*\*\*\*\*\*\*\*\*\*1111 |
| Phone | 91234567 | \*\*\*\*4567 |
| Email | john@example.com | j\*\*\*@example.com |
| Bank Account | 1234567890 | \*\*\*\*\*\*7890 |
