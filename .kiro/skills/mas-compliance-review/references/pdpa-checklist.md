# PDPA Compliance Checklist for Developers

## When Writing Code That Handles Personal Data

### Accountability
- [ ] Data protection policies and practices documented and available on request
- [ ] Data Protection Officer (DPO) designated and contactable
- [ ] Process in place to receive and respond to complaints

### Data Collection
- [ ] Consent obtained before collecting personal data
- [ ] Purpose of collection clearly stated
- [ ] Only minimum necessary data collected (data minimization)
- [ ] Collection method is lawful and reasonable

### Data Use
- [ ] Data used only for stated purpose
- [ ] No secondary use without additional consent
- [ ] Access restricted to authorized personnel only
- [ ] Purpose limitation enforced in code logic

### Data Storage
- [ ] Encrypted at rest (AES-256 / KMS)
- [ ] Encrypted in transit (TLS 1.2+)
- [ ] Storage location recorded for each system: application data in the workload region (for example `ap-southeast-1`) where institutional policy requires it; Kiro stores and processes prompts and code context in its profile region (`us-east-1` or `eu-central-1`), so treat any personal data reaching Kiro as a cross-border transfer (see Transfer Limitation below)
- [ ] Retention period defined and enforced
- [ ] Secure deletion when retention expires

### Transfer Limitation (PDPA s26)
- [ ] Personal data transferred outside Singapore receives a standard of protection comparable to the PDPA: legally enforceable obligations (for example, a contract specifying the recipient countries, or binding corporate rules), specified certifications (APEC CBPR / Global CBPR; PRP for data intermediaries), or another deemed-compliance case
- [ ] Transfers made by data intermediaries and cloud providers are covered (for example, an AI coding service that processes prompts or code in another region); the organisation remains responsible
- [ ] Personal data kept out of Kiro prompts and code context (use masked or synthetic test data); Kiro has no Singapore profile region and may process content in other regions of the same geography, and Global-scope models (currently GPT-5.6 Sol, Terra and Luna) may be processed in AWS Regions worldwide, so exclude them with the model allow list if processing must stay within one geography

### Data Protection
- [ ] No PII in logs, error messages, or debug output
- [ ] PII masked in displays and logs (NRIC/FIN: `S****567D`, i.e. first letter, four asterisks, last 3 digits and check letter; card, phone and account numbers: last 4 digits)
- [ ] Full NRIC/FIN stored only where the law requires it (for banks, for example, customer due diligence under MAS Notice 626) or where identity must be established to a high degree of fidelity (PDPC Advisory Guidelines on the PDPA for NRIC and other National Identification Numbers, 31 August 2018); elsewhere removed, masked or tokenized
- [ ] SQL injection prevention (parameterized queries)
- [ ] Input validation on all user inputs
- [ ] Output encoding to prevent XSS
- [ ] NRIC numbers not used as an authenticator or default password (PDPC/CSA advisory: organisations to cease using NRIC numbers for authentication by 31 Dec 2026)

### Singapore-Specific PII Patterns

Same patterns as the `pii-detection` skill (`.kiro/skills/pii-detection/references/singapore-pii-patterns.md`, which also has the POSIX ERE forms for `grep -E`, the NRIC/FIN checksum and the Luhn check). `flags` is `i` for case-insensitive, `-` for case-sensitive; apply it as an engine option, because JavaScript does not support a leading `(?i)`. The pii-detection test checks that this block matches the reference.

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
```
<!-- pii-patterns:pcre:end -->

| Data Type | Pattern id | Severity | Context rule | Action |
|-----------|------------|----------|--------------|--------|
| NRIC / FIN | `nric` (`fin` is the F/G/M subset; report each value once) | Critical | Validate the checksum | Block; remove, mask or tokenize |
| Phone (SG) | `phone_sg` | High | Corroborate with phone/mobile/tel/contact | Mask |
| Bank account | `bank_account` | High | Only within 20 characters after account/acct/a/c; high false-positive rate (timestamps, phone numbers) | Block/mask |
| Credit card | `card_visa`, `card_mastercard`, `card_amex` | Critical | Luhn check | Block |
| Email | `email` | Medium | Ignore reserved example domains | Mask |
| Postal code | `postal_sg` | Low | Only after Singapore, `S(` or postal/postcode | Review (Medium when part of a full address) |
| SWIFT/BIC | `swift_bic` | Low (not PII; identifies a bank) | Only after SWIFT or BIC; upper case | Informational |

### Data Breach Notification
Source: PDPC Advisory Guidelines on Key Concepts in the PDPA, chapter 20.
- Assess whether a breach is notifiable expeditiously; PDPC expects the assessment to be completed generally within 30 calendar days
- Notifiable if either test is met (two separate tests):
  - **Significant harm:** the breach results in, or is likely to result in, significant harm to affected individuals (prescribed classes of personal data in the PDP (Notification of Data Breaches) Regulations 2021)
  - **Significant scale:** the breach affects 500 or more individuals
- Notify PDPC as soon as practicable, and no later than 3 calendar days after determining that the breach is notifiable
- Notify affected individuals as soon as practicable, at the same time as or after notifying PDPC (required where the breach is likely to result in significant harm to them)
