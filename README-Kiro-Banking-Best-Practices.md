# Quick Reference Card: AWS Kiro Banking Best Practices

> For the full guide, see [README.md](README.md).

---

## Document Map

| Document | Sections | Content |
|----------|----------|---------|
| [Kiro-Agentic-SDLC-Banking-Best-Practices.md](Kiro-Agentic-SDLC-Banking-Best-Practices.md) | 1-4 | Architecture, Identity, Network, VDI |
| [Kiro-Banking-Best-Practices-Part2.md](Kiro-Banking-Best-Practices-Part2.md) | 5-10 | MCP Governance, SDLC, Data Protection, Compliance, Operations, Incident Response |
| [Banking-Skills-Development-Guide.md](Banking-Skills-Development-Guide.md) | -- | Building MAS-compliant Kiro Skills |

---

## Implementation Phases (6 Weeks)

| Phase | Week | Focus | Key Deliverable |
|-------|------|-------|-----------------|
| 1 | 1-2 | Identity & Access | Enterprise IdP + IAM IDC + MFA |
| 2 | 2-3 | Network Security | VPC + PrivateLink endpoints |
| 3 | 3-4 | VDI Deployment | WorkSpaces + DLP + GPO |
| 4 | 4-5 | MCP Governance | Centralized whitelist + permissions |
| 5 | 5-6 | Monitoring & Compliance | CloudTrail + validation scripts |

---

## MAS TRM Compliance Quick Map

| MAS Section | Control | Kiro Implementation |
|-------------|---------|---------------------|
| 3.1 Governance | Board oversight of tech risk | IAM IDC + Enterprise IdP |
| 5.1 IT Project Mgmt | Security-by-design in SDLC | Supervised mode + code review gates |
| 9.1 Access Control | Authentication & authorization | MFA + session management + RBAC |
| 9.3 Remote Access | Secure remote connectivity | VPC + PrivateLink (no internet) |
| 10.1 Cryptography | Data encryption standards | TLS 1.2+ in transit, KMS at rest |
| 11.1 Data Security | Data protection controls | DLP agents + encryption + PDPA compliance |
| 11.2 Network Security | Network segmentation | VPC endpoints + security groups + NACLs |
| 12.1 Cyber Ops | Threat monitoring | CloudWatch + GuardDuty + MCP audit logs |
| 15.1 IT Audit | Audit trail requirements | CloudTrail (90-day min retention) |

---

## Key Security Controls Checklist

- [ ] IAM IDC integrated with Enterprise IdP (SAML 2.0 + SCIM)
- [ ] MFA enabled for all users
- [ ] Social logins blocked at firewall
- [ ] VPC endpoints created for Kiro services
- [ ] WorkSpaces deployed with encryption
- [ ] DLP agents installed and configured
- [ ] Centralized MCP config deployed (read-only)
- [ ] CloudTrail logging enabled with data events
- [ ] KMS customer-managed keys configured
- [ ] Prompt logging enabled
- [ ] Incident response plan documented

---

## MCP Server Tiers

| Tier | Status | Servers | Risk Level |
|------|--------|---------|------------|
| **1** | Pre-Approved | AWS Docs, Git, Filesystem | Low |
| **2** | Conditional | GitHub, Docker, Kubernetes | Medium |
| **3** | Prohibited | Web Search, Browser, Custom | High |

---

## Incident Escalation

```
Developer -> Team Lead (15 min) -> Security Team (30 min) -> CISO (1 hr) -> MAS (24 hrs if material)
```

---

## Regulatory Framework References

- **MAS TRM Guidelines** (Jan 2021) - Primary technology risk regulation
- **PDPA** (2012) - Personal data protection
- **MAS Outsourcing Guidelines** (2018) - Third-party service risk
- **MAS FEAT Principles** - AI/ML governance in financial services
- **ABS Cloud Computing Guide** - Industry cloud security standards

---

*See [README.md](README.md) for full documentation, architecture diagrams, and detailed guidance.*

*Licensed under [MIT License](LICENSE). See [DISCLAIMER](Kiro-Agentic-SDLC-Banking-Best-Practices.md#disclaimer) for important notices.*
