# OWASP Top 10 for Banking Applications

## Quick Reference Mapped to MAS TRM

| # | OWASP Risk | MAS TRM Section | Banking Impact |
|---|-----------|-----------------|----------------|
| 1 | Broken Access Control | 9.1 (User Access Management) | Unauthorized account access, privilege escalation |
| 2 | Cryptographic Failures | 10.1, 10.2 (Cryptographic Algorithm and Protocol; Key Management) | PII exposure, credential theft |
| 3 | Injection | 6.1 (Secure Coding, Source Code Review and Application Security Testing) | Data exfiltration, unauthorized transactions |
| 4 | Insecure Design | 5.4 (System Development Life Cycle and Security-By-Design) | Systemic vulnerabilities in financial logic |
| 5 | Security Misconfiguration | 11.3 (System Security) | Open admin panels, default credentials |
| 6 | Vulnerable Components | 6.1.3, 7.4 (Third-party and open-source code; Patch Management) | Supply chain attacks, known CVEs |
| 7 | Auth & Identification Failures | 9.1, 14.2 (User Access Management; Customer Authentication) | Account takeover, session hijacking |
| 8 | Software & Data Integrity | 6.1, 6.3 (Secure Coding; DevSecOps Management) | Tampered transactions, CI/CD compromise |
| 9 | Security Logging Failures | 12.2 (Cyber Event Monitoring and Detection) | Missing audit trail, undetected breaches |
| 10 | Server-Side Request Forgery | 11.2 (Network Security) | Internal service access, metadata theft |

## Banking-Specific Mitigations

### A01: Broken Access Control
- Enforce authorization at data layer (not just API layer)
- Implement transaction signing for high-value operations
- Log all authorization failures for SIEM analysis

### A02: Cryptographic Failures
- Use AWS KMS with customer-managed keys (MAS TRM 10.2)
- Enforce TLS 1.2+ (TLS 1.3 preferred) for all connections
- Never store passwords - use bcrypt/scrypt with appropriate cost factor

### A03: Injection
- Parameterized queries for ALL database operations
- Input validation using allowlist approach
- Output encoding appropriate to context (HTML, JS, SQL, LDAP)

### A07: Authentication Failures
- MFA for all customer-facing and admin operations (MAS TRM 14.2 for customers; 9.2 for admins; banks: FSM-N06 para 4.6)
- Session timeout: 15 minutes for banking apps (example institutional policy, not prescribed by MAS TRM)
- Account lockout after 3 failed attempts (example institutional policy, not prescribed by MAS TRM)
- Monitor for credential stuffing patterns

### A09: Security Logging Failures
- Log all financial transactions with full context (MAS TRM 12.2; the logs serve as evidence for the IT audit function, TRM 15.1)
- Protect log integrity (append-only, signed)
- Minimum 90-day retention (example institutional policy, not prescribed by MAS TRM); archive period set per your record-keeping obligations (commonly 5-7 years)
- Never log PII or credentials
