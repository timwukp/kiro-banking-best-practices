# MAS TRM Guidelines Quick Reference

## Key Sections for Code Review

| Section | Topic | What to Check |
|---------|-------|---------------|
| 3.1 | Governance | Board oversight, policies documented |
| 5.1 | IT Project Mgmt | Security-by-design, risk assessment |
| 5.2 | Security-by-Design | Threat modeling, secure coding |
| 6.1 | System Development | SDLC controls, code review, testing |
| 6.2 | Source Code Review | Static analysis, peer review |
| 6.3 | Testing | Security testing (SAST, DAST, IAST) |
| 7.1 | IT Service Mgmt | Change management, approval workflow |
| 9.1 | Access Control | Authentication, authorization, MFA |
| 9.2 | Privileged Access | Admin controls, session recording |
| 9.3 | Remote Access | VPN, VPC, PrivateLink |
| 10.1 | Cryptography | TLS 1.2+, KMS, key rotation |
| 11.1 | Data Security | Encryption, DLP, classification |
| 11.2 | Network Security | Segmentation, firewall, IDS/IPS |
| 11.3 | System Security | Hardening, patching, vulnerability mgmt |
| 12.1 | Cyber Threat Intel | Monitoring, threat feeds |
| 12.2 | Event Monitoring | SIEM, log analysis, alerting |
| 12.3 | Incident Response | Procedures, escalation, MAS notification |
| 13.1 | Vulnerability Assessment | Regular VA scans |
| 13.2 | Penetration Testing | Annual PT, blackbox + greybox |
| 14.1 | Online Financial Services | Web security, mobile security |
| 14.2 | Customer Authentication | MFA, transaction signing |
| 15.1 | IT Audit | Audit trail, log integrity, retention |

## Encryption Standards

- **In transit:** TLS 1.2 minimum, TLS 1.3 recommended
- **At rest:** AES-256 via AWS KMS (customer-managed keys)
- **Key rotation:** Enabled, annual minimum
- **Prohibited:** MD5, SHA-1, DES, 3DES, RC4, SSLv3, TLS 1.0/1.1

## Authentication Standards

- **MFA:** Required for all privileged access
- **Password policy:** Min 14 chars, complexity, 90-day rotation, 24 history
- **Session timeout:** 15 min for banking apps, 2 hours for dev tools
- **Lockout:** 3 failed attempts
- **Biometrics:** FAR/FRR calibrated to risk

## Data Residency (Singapore)

- Primary region: `ap-southeast-1`
- Cross-region inference: Disabled for regulated workloads
- Data storage: Singapore only
- Backup: Within Singapore or approved jurisdictions
