# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.9] - 2026-10-09

Correction release. A review of 1.0–1.8 found inaccurate regulatory citations, data-location and network claims that do not match the official Kiro documentation, Kiro settings and commands that do not exist, hooks that failed open, and CDK defects. This release fixes them and records two changes that were merged after 1.8.

### Fixed
- **MAS TRM citations** remapped to the January 2021 table of contents: audit logging 15 → 12.2, security-by-design 5.2 → 5.4, change management 7.1 → 7.5, key management 10.1 → 10.2, VDI 8.5 / 11.5 → 9.3 / 11.3 / 11.4, secure coding "Section 10" → 6.1, monitoring 12.1 → 12.2
- **Incident notification:** the cancelled Notice 644 "24 hours" step is replaced by MAS Notice FSM-N05: notify MAS within 1 hour of discovery of a relevant incident (para 7) and submit a root-cause and impact report within 14 days (para 8)
- **Outsourcing:** MAS Notice 658 and the Guidelines on Outsourcing (Banks / FIs other than Banks), effective 11 Dec 2024, replace the cancelled 2016/2018 guidelines; TRM 3.4 (third-party services) added
- **AI governance:** the final MAS Guidelines on AI Risk Management (published 7 Oct 2026, effective 7 Oct 2027) replace the 2025 consultation paper
- **PDPA:** significant-scale and significant-harm tests, 3-day PDPC notification, Transfer Limitation Obligation (s26), purpose-based retention, NRIC authentication cessation by 31 Dec 2026
- **Overclaims:** "MAS compliant", "full compliance" and "tested" replaced with "MAS-aligned" wording; institution-specific numbers labelled as example policy
- **Data location:** Kiro has no Singapore profile region. Kiro content is stored and processed in the profile region (`us-east-1` or `eu-central-1`), inference scope is set per model (Geography for Claude models, Global for GPT-5.6 Sol, Terra and Luna), and Kiro use is treated as a cross-border transfer
- **Network:** removed the non-existent `com.amazonaws.ap-southeast-1.q` and `.codewhisperer` endpoints and the unused `bedrock-runtime` endpoints; documented the official Kiro VPC endpoint names (profile region only) and the official firewall allowlist; no longer advises blocking `prod.us-east-1.auth.desktop.kiro.dev` (restrict sign-in methods in `managed-settings.json` instead)
- **Kiro configuration:** removed invented `kiro.*` settings keys, `aws q` commands and `AWS::Q::*` CloudTrail data selectors; replaced with `kiroAgent.agentAutonomy`, permission rules and Kiro console steps
- **Hooks:** command normalisation (`sh -c` wrappers, quoting, compound commands, `git -C` / `-c`); PEM pattern bug fixed (`grep -e`); the audit logger writes valid hash-chained JSONL without raw input
- **CDK:** EndpointNacl associated with the Endpoints subnets; no-MFA sign-in filter limited to successful IAM-user logins; IAM policy-change filter completed to CIS 4.4; lifecycle transitions always before expiration; build without `ts-node` (`tsc` to `build/`); redundant cdk-nag suppressions removed
- **Skills:** wrong code examples fixed (boto3 `put_bucket_encryption`, Secrets Manager client, rate limiter, missing import, account numbers in audit logs, balance race); nested code fences in the Skills Development Guide that rendered Sections 5–7 and 9 as code; corrected claims about how Kiro activates skills
- **Navigation:** the Part 1 table of contents links Sections 5–14 to Part 2, and the trailing "Document continues" placeholder is replaced by a link to Part 2

### Changed
- **Repository renamed** from `kiro-banking-best-practices` to `kiro-fsi-best-practices` to reflect that the MAS TRM Guidelines apply to all MAS-regulated financial institutions. Project titles and audience descriptions now say "FSI"; the banking reference implementation, file names and CDK physical resource names (`kiro-banking-*`) are unchanged. GitHub redirects the old URL.
- **Test fixtures:** the AWS documentation example secret key is now assembled at runtime in the hook and PII-pattern test fixtures, so repository secret scanning does not flag the example credential pair.
- **Kiro 1.x governance model:** runtime controls moved to the admin policy (`managed-settings.json` deny/ask rules and sign-in restriction), user `permissions.yaml`, v1 hook files and workspace trust; the reference agent migrated from `toolsSettings` to `permissions.rules`; MCP lockdown through MCP governance, a version-pinned registry and workspace trust
- **MDM:** `mdm/lockdown-*` deploy `managed-settings.json` to the official per-OS paths with validation (no `allow` rules), hash-verified hook deployment, a drift check and a dry-run mode; limits documented (a local administrator can still change the files)
- **Chaos harness:** safety gates (throwaway VM, no deletion of existing users); round 2 now exercises the shipped hooks, the shipped policy and `mdm/lockdown-linux.sh`
- **CDK:** `kiroProfileRegion` (Kiro interface endpoints are created only when the stack runs in the profile region); flow logs encrypted with a dedicated rotating CMK; WorkSpaces security-group egress explicitly restricted in the default egress mode; flags for account singletons (GuardDuty, Security Hub, Access Analyzer); configurable backup schedule (default 02:00 SGT). No existing resource is replaced; construct IDs, physical names, exports and Config rule names are unchanged. CDK tests 27 → 86
- **Skills and steering:** one tested PII pattern catalogue shared by the skill, its reference and the PDPA checklist; trigger phrases moved into skill descriptions; clear split between `mas-compliance-review` (regulatory and IaC mapping) and `banking-code-review` (application code); unified masking (`S****567D`); steering files have explicit frontmatter (`banking-standards`: always; `fairness`: fileMatch on model, scoring, decisioning and pricing code)
- **Diagrams:** the README architecture and security-layer diagrams are now Mermaid, rendered by GitHub and kept in sync with the text; they show the allowlisted egress, the Kiro service in the profile region and corrected TRM references. The outdated PNGs (Bedrock endpoint, TRM 8.5 / 15 labels) are removed, and `diagrams/generate_diagrams.py` is updated for optional PNG export
- **QUICK-REFERENCE.md:** the 6-week phase table is replaced by the effort and exit-criteria plan; the document map lists `managed-settings/`, `agent-hooks/README.md`, `mdm/` and the governance references
- **CI:** Node.js 22; a new governance job runs the hook regression tests, verifies `agent-hooks/SHA256SUMS`, validates the managed-settings and hook JSON and runs the MDM dry-run tests; the PII pattern tests and `./validate-repo.sh` also run in CI
- **`validate-repo.sh`:** read-only, resolves each link relative to the linking file's directory, broader scope (`managed-settings/`, `mdm/`, `security-tests/`, `diagrams/`)
- **Repo hygiene:** `.gitignore` covers secrets and key material, local tool state, Python caches and coverage output; `SECURITY.md`, `CONTRIBUTING.md` and `AGENTS.md` describe the current checks and the pull-request flow
- **Merged after 1.8, recorded here:** objective implementation plan with effort estimates and exit criteria instead of a fixed 6-week timeline (#29, 2026-06-05); data location described as a customer preference, not a MAS requirement (#31, 2026-06-30)

### Added
- Applicability table of MAS TRM and Cyber Hygiene notices across MAS-regulated sectors (FSM-N03 … FSM-N26); FSM-N05 availability / RTO and FSM-N06 cyber hygiene requirements; note on Consultation Paper P012-2026
- `managed-settings/`: reference admin policies (Option A IAM Identity Center, Option B external IdP), user `permissions.yaml` template, pinned MCP registry example and deployment guide
- `kiro-docs/permissions-and-managed-settings.md`; `agent-hooks/README.md`, the v1 hook file `agent-hooks/hooks/banking-guards.json` and `agent-hooks/SHA256SUMS`
- Opt-in CDK egress mode `nat-dns-firewall` (public /28 subnets, one NAT gateway, Route 53 Resolver DNS Firewall allowlist built from the official Kiro firewall list, block-all default); `-c region=<r>` and `-c egress=<mode>` context overrides; optional AWS Config recorder and delivery channel (`createConfigRecorder`, default `false`)
- CloudWatch alarms for root account usage (CIS 4.3), CloudTrail changes (CIS 4.5) and KMS key disable or scheduled deletion (CIS 4.7)
- Tests: 98 hook regression tests with exact exit codes, MDM dry-run tests (46 Linux, 35 macOS) and 346 PII pattern checks (`.kiro/skills/pii-detection/tests/patterns.test.sh`)

### Security
- Guard hooks fail closed: exit 2 on any error, on empty or invalid input and when `jq` is missing (the 1.8 hooks let these calls through); broader secret and NRIC/FIN coverage (S, T, F, G and M series)
- Admin `deny` / `ask` rules for force pushes, history rewrites, destructive commands, credential reads, `git push` and deploy commands; sign-in restricted to the corporate identity
- CloudWatch alarms now deliver: the audit KMS key grants `cloudwatch.amazonaws.com` and the SNS topic policy allows CloudWatch to publish (both scoped to the account)
- Audit-log bucket: Object Lock default retention (GOVERNANCE) and noncurrent version expiration; KMS key policies for CloudTrail, CloudWatch Logs and WorkSpaces scoped with source and encryption-context conditions
- A real AWS account ID removed from `cdk.context.json`
- Documented the client-side enforcement limit: a local administrator can bypass Kiro client controls, so endpoint controls and server-side boundaries (branch protection, IAM, egress allowlist) stay authoritative

### Corrections to earlier entries

The entries below are kept as written; these statements in them are superseded:
- **1.8:** the MDM lockdown is not "immutable, append-only, self-healing". It deploys the files read-only for standard users, detects drift and restores the files on the next scheduled run; a local administrator can still change them ([`kiro-docs/mdm-endpoint-enforcement.md`](kiro-docs/mdm-endpoint-enforcement.md))
- **1.8:** "round 2 closes 4/6 endpoint gaps" is withdrawn. The round-2 "closed" items were simulated by the harness (a purpose-written audit hook, a bash function imitating `denyByDefault`, a `noexec` home and a root-only file set up by the harness), and the shipped hooks failed open on errors and missed common variants ([`kiro-docs/chaos-pentest-evidence.md`](kiro-docs/chaos-pentest-evidence.md))
- **1.8:** `denyByDefault` is not the primary agent control: agent `toolsSettings`, including `denyByDefault`, is deprecated in Kiro 1.x and has no equivalent. The primary control is the admin policy in `managed-settings.json`
- **1.7:** #13 was never merged; the `AGENTS.md`, steering map and "Start Here" work landed in #14
- **1.3:** ComplianceStack defines 19 AWS Config managed rules (it always did; "18" was a miscount), and there are now 5 stacks (BackupStack was added on 2026-05-17 in #1, which no earlier entry recorded). The "8 PrivateLink endpoints" included `q`, `codewhisperer` and `bedrock-runtime` endpoints in `ap-southeast-1` that do not exist or were unused; 1.9 removes them
- **1.0, 1.3, 1.4:** "MAS-compliant" should read "MAS-aligned"; the 1.4 sources "MAS Outsourcing Guidelines (Jul 2016)" and "AI Risk Management Guidelines (2025 consultation paper)" are superseded by Notice 658 with the Guidelines on Outsourcing (effective 11 Dec 2024) and by the final AI Risk Management Guidelines (7 Oct 2026)

---

## [1.8] - 2026-06-05

### Added
- **MDM / endpoint-managed enforcement** `kiro-docs/mdm-endpoint-enforcement.md` + cross-platform lockdown references `mdm/lockdown-{linux.sh,macos.sh,windows.ps1}` (immutable, append-only, self-healing) with tests; `destructive-fs-guard` hook (#22)
- **Chaos / penetration test** `security-tests/chaos/` (non-privileged human + Kiro agent) + sanitized hash-chained evidence `kiro-docs/chaos-pentest-evidence.md`; round 2 closes 4/6 endpoint gaps with stronger local controls (#25, #26)
- README **Key Features**: Agent Runtime Governance, Endpoint Enforcement (MDM) & Defense-in-Depth, Adversarial Validation (#27)

### Changed
- Relocated OS-level MDM enforcement out of `agent-hooks/` into top-level `mdm/` (layering: MDM is not a Kiro feature) (#24)
- Hardening from chaos findings folded into best practices: declarative `denyByDefault` as the primary agent control; fixed/managed audit path; application allow-listing; server-side as the authoritative boundary

---

## [1.7] - 2026-06-04

### Added
- **Agent Runtime Governance** (Layer 4): `kiro-docs/agent-runtime-governance.md` + `agent-hooks/` reference hooks (`pii-guard`, `git-guard`, hash-chained `audit-logger`) and locked-down `banking-secure.agent.json` (#11, #12)
- Consolidated Kiro Security & Governance features reference `kiro-docs/security-governance-features.md` (#4, #7)
- `AGENTS.md`, steering map (`.kiro/steering/repo-map.md`), README "Start Here" + 15-minute quickstart for first-time Kiro users (#13, #14)

### Changed
- Renamed `README-Kiro-Banking-Best-Practices.md` to `QUICK-REFERENCE.md` (#16)
- Redirected `CLAUDE.md` to `AGENTS.md` — repo targets Kiro (#15)
- Aligned `CONTRIBUTING.md` `.kiro` commit policy: skills + steering committed; specs/hooks/settings ignored (#10)

### Fixed
- CI: `Validate Documentation` (allow tracked `.kiro/steering`; scope secret scan) and `Validate CDK` (lockfile sync + AZ context cache) now pass on `main` (#8, #9)

---

## [1.6] - 2026-03-11

### Added
- Architecture diagrams (PNG), `SECURITY.md`, steering samples, kiro-docs source/freshness tracking

### Changed
- README consolidation

---

## [1.5] - 2026-03-11

### Added
- Option B: Direct IdP federation architecture (Okta / Entra ID, no IAM Identity Center)

### Fixed
- CDK compilation and tests

---

## [1.4] - 2026-02-28

### Added
- **Working Kiro Skills** (`.kiro/skills/`):
  - `mas-compliance-review`: Automated MAS TRM + PDPA + AIRG compliance checking with 6-category review process, fail patterns, and compliance report output
  - `pii-detection`: Singapore-specific PII detection (NRIC, FIN, credit cards, bank accounts) with PDPA-aligned masking and remediation
  - `banking-code-review`: Structured banking code review with 6-section checklist (security, access control, data protection, audit, error handling, AI governance)
  - Reference files: MAS TRM quick reference, PDPA developer checklist
- **GitHub Actions CI/CD** (`.github/workflows/validate.yml`):
  - Documentation validation (required files, no PDFs, no secrets)
  - CDK validation (TypeScript compile, jest tests, cdk synth + CDK Nag)
  - Skill structure validation (SKILL.md exists, frontmatter fields, name matching)
- Updated `.gitignore` to track skills while excluding local Kiro config

### Changed
- Ingested MAS AI Risk Management Guidelines (2025 consultation paper)
- Ingested MAS Outsourcing Guidelines (Jul 2016)
- Ingested ABS Cloud Computing Implementation Guide 2.0
- Enterprise IdP confirmed as Microsoft Entra ID

---

## [1.3] - 2026-02-28

### Added
- **AWS CDK Infrastructure** (`cdk/`): TypeScript CDK modules for MAS-compliant deployment
  - `EncryptionStack`: 3 KMS customer-managed keys (audit, data, workspaces) with rotation
  - `NetworkStack`: VPC + 8 PrivateLink endpoints + security groups + NACLs + flow logs
  - `MonitoringStack`: CloudTrail + S3 log bucket + 4 CloudWatch security alarms + SNS
  - `ComplianceStack`: 18 AWS Config managed rules mapped to MAS TRM + PDPA
- CDK Nag (AwsSolutions) integration for automated security validation
- CDK test suite with assertions for all stacks
- Environment configs (dev/prod) with banking-specific defaults

---

## [1.2] - 2026-02-28

### Added
- **PDPA Compliance**: Personal Data Protection Act (Singapore) coverage with Kiro-specific controls
- **MAS Outsourcing Guidelines**: Third-party risk assessment for Kiro as AWS-managed service
- **MAS FEAT Principles**: AI/ML governance framework for AI-assisted development
- **ABS Guidelines References**: Cloud computing, penetration testing, and red team standards
- **Expanded TRM Mapping**: Deeper cross-references to specific MAS TRM sub-sections
- **CHANGELOG.md**: Version tracking for documentation changes
- **Approved MCP Server Tiers**: Added to README.md (previously only in quick reference)
- **Version History Table**: Added to README.md

### Changed
- **README.md**: Enhanced with MCP server tiers, expanded regulatory references, version history
- **README-Kiro-Banking-Best-Practices.md**: Converted from duplicate overview to concise quick-reference card
- **validate-repo.sh**: Enhanced with 8 validation checks (was 6), including broken links, secrets scanning, TODO detection, large file warnings, markdown structure
- **Part 2 Status**: Corrected from "In Progress" to "Complete"

### Removed
- Duplicate License/Disclaimer text from Kiro-Agentic-SDLC-Banking-Best-Practices.md and Kiro-Banking-Best-Practices-Part2.md (now reference LICENSE file)
- Content duplication between README.md and README-Kiro-Banking-Best-Practices.md

---

## [1.1] - 2026-02-26

### Added
- README.md with project overview, architecture diagrams, and documentation structure
- Updated .gitignore to exclude .vscode config files

---

## [1.0] - 2026-02-25

### Added
- Initial release: AWS Kiro Banking Best Practices for MAS-compliant SDLC
- Kiro-Agentic-SDLC-Banking-Best-Practices.md (Sections 1-4: Architecture, Identity, Network, VDI)
- Kiro-Banking-Best-Practices-Part2.md (Sections 5-10: MCP, SDLC, Data Protection, Compliance, Operations, Incident Response)
- Banking-Skills-Development-Guide.md (Kiro Skills for banking)
- kiro-docs/ technical reference (MCP configuration, security, servers, usage, privacy)
- validate-repo.sh validation script
- MIT License
- CONTRIBUTING.md guidelines
