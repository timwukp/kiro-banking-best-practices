# MAS TRM Guidelines Quick Reference

Source: [MAS Technology Risk Management Guidelines](https://www.mas.gov.sg/regulation/guidelines/technology-risk-management-guidelines) (18 January 2021). Section numbers and titles follow the published table of contents. The Guidelines apply to all MAS-regulated financial institutions. Banks must also meet the binding MAS Notice FSM-N05 (Technology Risk Management) and MAS Notice FSM-N06 (Cyber Hygiene); other sectors have equivalent FSM notices.

## Key Sections for Code Review

| Section | Title | What to Check |
|---------|-------|---------------|
| 3.1 | Role of the Board of Directors and Senior Management | Board and senior management oversight of Kiro adoption |
| 3.2 | Policies, Standards and Procedures | Documented policies for AI-assisted development |
| 3.4 | Management of Third Party Services | Kiro, MCP servers and model providers assessed as third-party services (also check the MAS outsourcing requirements) |
| 3.6 | Security Awareness and Training | Developer training on AI-assisted development risks |
| 4.2-4.4 | Risk Identification; Risk Assessment; Risk Treatment | Technology risk assessment of Kiro and AI use |
| 5.4 | System Development Life Cycle and Security-By-Design | Security requirements in specs, steering files and skills |
| 6.1 | Secure Coding, Source Code Review and Application Security Testing | Secure coding, peer review of AI-generated code, SAST/DAST/IAST (Annex A); para 6.1.3: third-party, open-source and AI-generated code reviewed and tested before integration |
| 6.3 | DevSecOps Management | Segregation of duties for development, testing and release; human approval before merge |
| 7.4 | Patch Management | Timely patching of IDE, CLI, VDI images and dependencies |
| 7.5 | Change Management | Change approval workflow, rollback, emergency changes |
| 7.6 | Software Release Management | Release approval and versioning |
| 8.4 | System Backup and Recovery | Backup plan, encrypted vault, restore tests |
| 9.1 | User Access Management | SSO, MFA, session management, RBAC |
| 9.2 | Privileged Access Management | Admin controls, admin MFA (banks: FSM-N06 para 4.1, 4.6) |
| 9.3 | Remote Access Management | Remote access through WorkSpaces VDI |
| 10.1 | Cryptographic Algorithm and Protocol | TLS 1.2+, no deprecated algorithms |
| 10.2 | Cryptographic Key Management | KMS customer-managed keys, key rotation |
| 11.1 | Data Security | Encryption, DLP, PII masking, classification |
| 11.2 | Network Security | VPC isolation, PrivateLink, security groups, NACLs, egress allowlist |
| 11.3 | System Security | Endpoint and VDI image hardening, GPO, MDM |
| 11.4 | Virtualisation Security | VDI virtualisation controls |
| 12.1 | Cyber Threat Intelligence and Information Sharing | Threat feeds, information sharing |
| 12.2 | Cyber Event Monitoring and Detection | CloudTrail, CloudWatch alarms, GuardDuty, prompt logging, audit trail, log integrity |
| 12.3 | Cyber Incident Response and Management | Procedures, escalation, MAS notification (banks: not later than 1 hour after discovery of a relevant incident, FSM-N05 para 7; root-cause report within 14 days, para 8) |
| 13.1 | Vulnerability Assessment | Regular VA scans |
| 13.2 | Penetration Testing | Black-box and grey-box penetration tests |
| 13.4 | Adversarial Attack Simulation Exercise | Red-team exercises |
| 14.1 | Security of Online Financial Services | Web and mobile application security |
| 14.2 | Customer Authentication and Transaction Signing | Customer MFA, transaction signing |
| 15.1 | Audit Function | Independent IT audit; uses the 12.2 logs as evidence (Section 15 is the audit function, not logging) |
| Annex A | Application Security Testing | SAST, DAST, IAST, fuzzing |

## Encryption Standards

- **In transit (TRM 10.1):** TLS 1.2 minimum, TLS 1.3 recommended
- **At rest (TRM 10.2, 11.1):** AES-256 via AWS KMS (customer-managed keys)
- **Key rotation (TRM 10.2):** Enabled; annual rotation is an example institutional policy (not prescribed by MAS TRM)
- **Prohibited:** MD5, SHA-1, DES, 3DES, RC4, SSLv3, TLS 1.0/1.1

## Authentication Standards

- **MFA:** Required for all privileged access (TRM 9.2). Banks: MAS Notice FSM-N06 para 4.6 requires MFA for all administrative accounts on critical systems and for all accounts used to access customer information through the internet. Customer authentication: TRM 14.2.
- **Password policy:** Min 14 chars, complexity, 90-day rotation, 24 history (example institutional policy, not prescribed by MAS TRM)
- **Session timeout:** 15 min for banking apps, 2 hours for dev tools (example institutional policy, not prescribed by MAS TRM)
- **Lockout:** 3 failed attempts (example institutional policy, not prescribed by MAS TRM)
- **Biometrics:** FAR/FRR calibrated to risk

## Data Location and Cross-Border Processing

- **MAS position:** MAS TRM does not impose a data-localisation mandate. Where data is hosted is an institutional choice. Offshore processing is assessed as a third-party and outsourcing risk (TRM 3.4 and the MAS outsourcing requirements) and, for personal data, under the PDPA Transfer Limitation Obligation (s26; see `pdpa-checklist.md`).
- **Workload region:** `ap-southeast-1` (Singapore) for the institution's own infrastructure and application data (VPC, WorkSpaces, CloudTrail, AWS Config, AWS Backup), where institutional policy requires it.
- **Kiro profile region:** `us-east-1` or `eu-central-1` (AWS GovCloud (US) for US public-sector profiles). Kiro has no Singapore profile region. Prompts, code context and responses are stored and processed there, and the prompt-log bucket, user activity report bucket and Kiro customer-managed KMS key must be in that region. IAM Identity Center can stay in `ap-southeast-1`.
- **Cross-region inference:** inference scope is set per model ([Kiro models page](https://kiro.dev/docs/models/)). Geography-scope models, which include all Claude models, may be processed in another region of the same geography (US: `us-east-1`, `us-east-2`, `us-west-2`; Europe: `eu-central-1`, `eu-west-1`, `eu-west-3`, `eu-north-1`, `eu-south-1`, `eu-south-2`). Global-scope models (currently GPT-5.6 Sol, Terra and Luna) may be processed in supported commercial AWS Regions worldwide and use the US endpoint even for `eu-central-1` profiles. Lifecycle status (experimental or preview) does not determine routing, and cross-region inference does not change where Kiro stores data. Kiro has no setting to disable cross-region inference; if processing must stay within one geography, use the model allow list (model governance) to exclude Global-scope models.
- **What to check:** Kiro is treated as a cross-border transfer and assessed under TRM 3.4 and outsourcing; customer information and personal data are kept out of prompts and code context (banks: FSM-N05 para 9, banking secrecy); Global-scope models are excluded through the model allow list (and preview terms such as Claude Fable 5.1's 30-day retention are reviewed); workload backups stay in the workload region or another jurisdiction approved by institutional policy.
- Source: [Kiro supported regions](https://kiro.dev/docs/enterprise/supported-regions/) and [Kiro data protection](https://kiro.dev/docs/privacy-and-security/data-protection/) (verified 2026-10-08).
