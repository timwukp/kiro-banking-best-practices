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
- [ ] Data residency in Singapore (ap-southeast-1)
- [ ] Retention period defined and enforced
- [ ] Secure deletion when retention expires

### Transfer Limitation (PDPA s26)
- [ ] Personal data transferred outside Singapore receives a standard of protection comparable to the PDPA: legally enforceable obligations (for example, a contract specifying the recipient countries, or binding corporate rules), specified certifications (APEC CBPR / Global CBPR; PRP for data intermediaries), or another deemed-compliance case
- [ ] Transfers made by data intermediaries and cloud providers are covered (for example, an AI coding service that processes prompts or code in another region); the organisation remains responsible

### Data Protection
- [ ] No PII in logs, error messages, or debug output
- [ ] PII masked in displays (NRIC: S****567D)
- [ ] SQL injection prevention (parameterized queries)
- [ ] Input validation on all user inputs
- [ ] Output encoding to prevent XSS
- [ ] NRIC numbers not used as an authenticator or default password (PDPC/CSA advisory: organisations to cease using NRIC numbers for authentication by 31 Dec 2026)

### Singapore-Specific PII Patterns

| Data Type | Pattern | Action |
|-----------|---------|--------|
| NRIC | `[STFG]\d{7}[A-Z]` | Block/mask |
| FIN | `[FG]\d{7}[A-Z]` | Block/mask |
| Phone (SG) | `[689]\d{7}` | Mask |
| Postal Code | `\d{6}` | Log only |
| Credit Card | Luhn algorithm | Block |
| Bank Account | `\d{10,12}` | Block/mask |

### Data Breach Notification
Source: PDPC Advisory Guidelines on Key Concepts in the PDPA, chapter 20.
- Assess whether a breach is notifiable expeditiously; PDPC expects the assessment to be completed generally within 30 calendar days
- Notifiable if either test is met (two separate tests):
  - **Significant harm:** the breach results in, or is likely to result in, significant harm to affected individuals (prescribed classes of personal data in the PDP (Notification of Data Breaches) Regulations 2021)
  - **Significant scale:** the breach affects 500 or more individuals
- Notify PDPC as soon as practicable, and no later than 3 calendar days after determining that the breach is notifiable
- Notify affected individuals as soon as practicable, at the same time as or after notifying PDPC (required where the breach is likely to result in significant harm to them)
