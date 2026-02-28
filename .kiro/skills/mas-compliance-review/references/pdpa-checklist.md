# PDPA Compliance Checklist for Developers

## When Writing Code That Handles Personal Data

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

### Data Protection
- [ ] No PII in logs, error messages, or debug output
- [ ] PII masked in displays (NRIC: S****567D)
- [ ] SQL injection prevention (parameterized queries)
- [ ] Input validation on all user inputs
- [ ] Output encoding to prevent XSS

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
- Assess within 30 calendar days if breach is notifiable
- Notify PDPC within 3 calendar days of assessment (if notifiable)
- Notifiable if: significant harm likely OR affects 500+ individuals
- Notify affected individuals as soon as practicable
