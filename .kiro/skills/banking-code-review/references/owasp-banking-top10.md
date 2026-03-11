# OWASP Top 10 for Banking Applications

## Quick Reference Mapped to MAS TRM

| # | OWASP Risk | MAS TRM Section | Banking Impact |
|---|-----------|-----------------|----------------|
| 1 | Broken Access Control | 9.1 (Access Control) | Unauthorized account access, privilege escalation |
| 2 | Cryptographic Failures | 10.1 (Cryptography) | PII exposure, credential theft |
| 3 | Injection | 11.1 (Data Security) | Data exfiltration, unauthorized transactions |
| 4 | Insecure Design | 5.2 (Security-by-Design) | Systemic vulnerabilities in financial logic |
| 5 | Security Misconfiguration | 11.3 (System Security) | Open admin panels, default credentials |
| 6 | Vulnerable Components | 11.3 (System Security) | Supply chain attacks, known CVEs |
| 7 | Auth & Identification Failures | 9.1 (Access Control) | Account takeover, session hijacking |
| 8 | Software & Data Integrity | 6.1 (System Development) | Tampered transactions, CI/CD compromise |
| 9 | Security Logging Failures | 15.1 (IT Audit) | Missing audit trail, undetected breaches |
| 10 | Server-Side Request Forgery | 11.2 (Network Security) | Internal service access, metadata theft |

## Banking-Specific Mitigations

### A01: Broken Access Control
- Enforce authorization at data layer (not just API layer)
- Implement transaction signing for high-value operations
- Log all authorization failures for SIEM analysis

### A02: Cryptographic Failures
- Use AWS KMS with customer-managed keys (MAS TRM 10.1)
- Enforce TLS 1.2+ (TLS 1.3 preferred) for all connections
- Never store passwords - use bcrypt/scrypt with appropriate cost factor

### A03: Injection
- Parameterized queries for ALL database operations
- Input validation using allowlist approach
- Output encoding appropriate to context (HTML, JS, SQL, LDAP)

### A07: Authentication Failures
- MFA for all customer-facing and admin operations (MAS TRM 9.1)
- Session timeout: 15 minutes for banking apps
- Account lockout after 3 failed attempts
- Monitor for credential stuffing patterns

### A09: Security Logging Failures
- Log all financial transactions with full context (MAS TRM 15.1)
- Protect log integrity (append-only, signed)
- Minimum 90-day retention, 7-year archive for financial services
- Never log PII or credentials
