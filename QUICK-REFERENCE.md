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
| [managed-settings/](managed-settings/README.md) | -- | Admin policy `managed-settings.json` (Option A and Option B), user `permissions.yaml` template, MCP registry example, deployment steps |
| [agent-hooks/README.md](agent-hooks/README.md) | -- | Defense-in-depth hooks (secret/PII, git and destructive-command guards, audit) and the reference agent |
| [kiro-docs/agent-runtime-governance.md](kiro-docs/agent-runtime-governance.md) | Layer 4 | How admin policy, console settings, workspace trust, permissions, hooks and audit fit together |
| [kiro-docs/permissions-and-managed-settings.md](kiro-docs/permissions-and-managed-settings.md) | -- | Permission rules and precedence, sign-in controls, hooks, custom agents (Kiro 1.x) |
| [mdm/](mdm/) | -- | MDM lockdown scripts for Windows, macOS and Linux (official paths, drift check, dry-run tests); guide: [kiro-docs/mdm-endpoint-enforcement.md](kiro-docs/mdm-endpoint-enforcement.md) |

---

## Architecture Options

| Option | Identity Flow | Best For |
|--------|--------------|----------|
| **A** (Default) | IdP → IAM Identity Center → Kiro + WorkSpaces | Unified AWS access management |
| **B** (Direct) | IdP → Kiro (OIDC) + WorkSpaces (SAML) directly | Fewer AWS dependencies, existing IdP-centric orgs |

See [README.md - Security Architecture](README.md#security-architecture) for full diagrams.

---

## Implementation Plan (Effort and Exit Criteria)

No fixed calendar: the hands-on work totals a few days, and the calendar is set by IdP/SCIM coordination, MCP security reviews and change approvals. Measure progress by the exit criteria, not by elapsed weeks. Details and assumptions: [README – Implementation plan](README.md#implementation-plan).

| Workstream | Effort* | Exit criterion (objective evidence) |
|------------|---------|-------------------------------------|
| Identity & access (IdP + SCIM + MFA) | ~0.5–1 d | Test user provisioned via SCIM; MFA enforced; social / Builder ID sign-in blocked |
| Network isolation (endpoints, SG/NACL, egress allowlist) | ~0.5–1 d | `cdk synth` clean; VDI reaches Kiro only through the allowlisted egress path; no inbound public endpoint |
| Secure VDI (WorkSpaces + GPO/DLP) | ~1–2 d | Encrypted WorkSpace; no local admin rights; `managed-settings.json` present, valid and read-only; agent `git push --force` denied with the source "administration" |
| MCP governance | ~0.5 d | MCP Registry URL set; every entry pins an exact version; an unlisted server stays hidden |
| Agent runtime + endpoint enforcement | ~0.5–1 d | `agent-hooks/tests/run-tests.sh` and `mdm/tests/test-lockdown.sh` green; chaos harness shows 0 unexpected bypasses |
| Monitoring & compliance | ~0.5 d | Prompt logs and user activity reports in S3 (profile region) and the SIEM; test alarm fires; MAS TRM mapping reviewed |

\* Hands-on time, assuming the prerequisite already exists. Estimates are illustrative; validate them in your environment.

---

## MAS TRM Compliance Quick Map

| MAS Section | Control | Kiro Implementation |
|-------------|---------|---------------------|
| 3.4 Third Party Services | Kiro, MCP servers, model providers | Due diligence + outsourcing assessment + MCP whitelist |
| 5.4 SDLC & Security-by-Design | Security-by-design in SDLC | Supervised mode + Skills + steering |
| 6.1 / 6.3 Secure Coding & DevSecOps | Review of AI-generated code; segregation of duties | Code review gates + SAST/DAST + human approval before merge |
| 9.1 User Access Mgmt | Authentication & authorization | Enterprise IdP + MFA + session management + RBAC |
| 9.2 Privileged Access | Administrative accounts | MFA for admin access (banks: FSM-N06 paras 4.1, 4.6) |
| 9.3 Remote Access | Secure remote connectivity | WorkSpaces VDI in a private VPC with allowlisted HTTPS egress |
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
- [ ] Admin policy `managed-settings.json` deployed read-only by MDM/GPO (sign-in restricted to the corporate identity, so Builder ID and social logins are removed)
- [ ] AWS service endpoints in the workload region and an allowlisted HTTPS egress path for Kiro (Kiro PrivateLink exists only in the profile region)
- [ ] WorkSpaces deployed with encryption
- [ ] DLP agents installed and configured
- [ ] MCP governance on: MCP Registry URL set in the Kiro console, exact versions pinned
- [ ] CloudTrail logging enabled (management events, log file validation)
- [ ] KMS customer-managed keys configured
- [ ] Prompt logging enabled
- [ ] Incident response plan documented

---

## MCP Server Tiers

| Tier | Status | Servers | Risk Level |
|------|--------|---------|------------|
| **1** | Pre-Approved | AWS Docs, Git (read-only) | Low |
| **2** | Conditional | GitHub, Docker, Kubernetes, Filesystem | Medium |
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
