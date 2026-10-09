# Quick Reference Card: AWS Kiro Banking Best Practices

> **Audience:** everyone · **Purpose:** one-page checklist / quick reference · **Prerequisites:** none.

> For the full guide with architecture diagrams and detailed implementation steps, see [README.md](README.md).

---

## Document Map

| Document | Sections | Content |
|----------|----------|---------|
| [README.md](README.md) | Overview | Architecture diagrams, compliance framework, quick start |
| [Kiro-Agentic-SDLC-Banking-Best-Practices.md](Kiro-Agentic-SDLC-Banking-Best-Practices.md) | 1-4 | Architecture, Identity, Network, VDI |
| [Kiro-Banking-Best-Practices-Part2.md](Kiro-Banking-Best-Practices-Part2.md) | 5-14 | MCP Governance, SDLC, Data Protection, PDPA, FEAT, ABS |
| [Banking-Skills-Development-Guide.md](Banking-Skills-Development-Guide.md) | -- | Building MAS-aligned Kiro Skills |

---

## Architecture Options

| Option | Identity Flow | Best For |
|--------|--------------|----------|
| **A** (Default) | IdP → IAM Identity Center → Kiro + WorkSpaces | Unified AWS access management |
| **B** (Direct) | IdP → Kiro (OIDC) + WorkSpaces (SAML) directly | Fewer AWS dependencies, existing IdP-centric orgs |

See [README.md - Security Architecture](README.md#security-architecture) for full diagrams.

---

## Implementation Phases (6 Weeks)

| Phase | Week | Focus | Key Deliverable |
|-------|------|-------|-----------------|
| 1 | 1-2 | Identity & Access | Enterprise IdP integration + MFA |
| 2 | 2-3 | Network Security | VPC + PrivateLink endpoints |
| 3 | 3-4 | VDI Deployment | WorkSpaces + DLP + GPO |
| 4 | 4-5 | MCP Governance | Centralized whitelist + permissions |
| 5 | 5-6 | Monitoring & Compliance | CloudTrail + validation scripts |

---

## MAS TRM Compliance Quick Map

| MAS Section | Control | Kiro Implementation |
|-------------|---------|---------------------|
| 3.4 Third Party Services | Kiro, MCP servers, model providers | Due diligence + outsourcing assessment + MCP whitelist |
| 5.4 SDLC & Security-by-Design | Security-by-design in SDLC | Supervised mode + Skills + steering |
| 6.1 / 6.3 Secure Coding & DevSecOps | Review of AI-generated code; segregation of duties | Code review gates + SAST/DAST + human approval before merge |
| 9.1 User Access Mgmt | Authentication & authorization | Enterprise IdP + MFA + session management + RBAC |
| 9.2 Privileged Access | Administrative accounts | MFA for admin access (banks: FSM-N06 paras 4.1, 4.6) |
| 9.3 Remote Access | Secure remote connectivity | WorkSpaces VDI over VPC + PrivateLink |
| 10.1 / 10.2 Cryptography | Algorithms & protocols; key management | TLS 1.2+ in transit, KMS customer-managed keys with rotation at rest |
| 11.1 Data Security | Data protection controls | DLP agents + encryption + PDPA controls |
| 11.2 Network Security | Network segmentation | VPC endpoints + security groups + NACLs |
| 11.3 / 11.4 System & Virtualisation Security | Endpoint hardening | Hardened WorkSpaces images + GPO |
| 12.2 Cyber Event Monitoring | Logging, monitoring & detection | CloudTrail + CloudWatch + MCP audit logs (90-day min retention: example institutional policy, not prescribed by MAS TRM) |
| 12.3 Incident Response | Cyber incident response | Escalation matrix + MAS notification (banks: FSM-N05 paras 7–8) |
| 15.1 IT Audit | Independent IT audit | Auditors use the CloudTrail / prompt-log trail as evidence |

> **Binding notices:** for banks, MAS Notices FSM-N05 (Technology Risk Management) and FSM-N06 (Cyber Hygiene) apply; other MAS-regulated sectors have their own notices — see [README – Applicability](README.md#applicability-across-mas-regulated-financial-institutions).

---

## Key Security Controls Checklist

- [ ] Enterprise IdP integrated (SAML 2.0 / OIDC + SCIM)
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
Developer -> Team Lead (15 min) -> Security Team (30 min) -> CISO (1 hr) -> MAS within 1 hour of discovery of a relevant incident (FSM-N05 para 7); root-cause report within 14 days (para 8)
```

> The MAS 1-hour clock runs from discovery of a relevant incident, not from the end of internal escalation, so escalate internally in parallel. Internal timings are example institutional policy. FSM-N05 applies to banks; other sectors follow their own TRM notice.

---

*See [README.md](README.md) for full documentation, architecture diagrams, and detailed guidance.*

*Licensed under [MIT License](LICENSE). See [DISCLAIMER](README.md#disclaimer) for important notices.*
