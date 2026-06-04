# Kiro Security & Governance Features (Banking Reference)

A consolidated, banking-focused reference of Kiro's security and governance
capabilities across **CLI**, **IDE**, and **General/Enterprise** surfaces,
compiled from the official Kiro changelog. Use this alongside
`privacy-and-security.md` and `mcp-security.md` when designing a
MAS-compliant Kiro deployment.

> **Last reviewed:** 2026-06-04. Verify current behaviour against
> https://kiro.dev/changelog/ before relying on any single item.

---

## 1. Feature Inventory

Surface legend: **CLI** = Kiro CLI · **IDE** = Kiro IDE · **Gen** = General /
Enterprise (console, account, compliance).

### Governance (enterprise admin controls)

| Date | Surface | Version | Feature |
|------|---------|---------|---------|
| 2026-05-27 | Gen | — | `User_Email` column in daily user activity reports (S3 CSV) |
| 2026-04-24 | Gen | — | Per-model message counts in user activity reports |
| 2026-04-13 | Gen | — | User emails shown in Kiro console (IAM Identity Center) |
| 2026-04-13 | CLI | 2.0 | Admin control of API key generation (governance settings) |
| 2026-03-27 | Gen | — | Subscription data CSV export from console |
| 2026-03-11 | IDE | 0.11 | **MCP Registry Governance** — HTTPS-hosted JSON allow-list of approved MCP servers, version-pinned, 24h sync |
| 2026-03-11 | IDE | 0.11 | **Model Governance** — approved-model list + default model (data-residency control) |
| 2026-02-05 | IDE | 0.9 | Web Tools Governance (disable web search/fetch org-wide) |
| 2026-02-05 | IDE | 0.9 | Custom Extension Registry (private, vetted extensions vs Open VSX) |
| 2026-02-04 | CLI | 1.25.0 | Enterprise Web Tools Governance + Subagent Access Control (`availableAgents`/`trustedAgents`) |
| 2025-12-18 | CLI | 1.23.0 | MCP Registry Support (org-level MCP allow-list) |
| 2025-11-17 | IDE | 0.6 | Enterprise governance of telemetry and MCP settings |

### Identity & Authentication

| Date | Surface | Version | Feature |
|------|---------|---------|---------|
| 2026-02-12 | IDE/CLI | 0.9.40 / 1.25.1 | External IdP support (Okta, Microsoft Entra ID) + SCIM provisioning |
| 2026-04-24 | CLI | 2.1 | Device Flow auth for remote/SSH/container environments |
| 2026-01-16 | CLI | 1.24.0 | Remote Authentication (device code over SSH/SSM/containers) |

### Tool, Command & Web Access Control

| Date | Surface | Version | Feature |
|------|---------|---------|---------|
| 2026-05-12 | CLI | 2.3.0 | OAuth Client ID for MCP servers (`oauth.clientId`) |
| 2026-03-02 | CLI | 1.27 | Granular Tool Trust — tiered scopes for shell commands & file paths |
| 2026-02-05 | IDE | 0.9 | Pre/Post Tool Use Hooks — Pre hooks can *block* tools before execution |
| 2026-01-16 | CLI | 1.24.0 | Granular URL permissions for `web_fetch` (regex allow/block) |
| 2025-09-04 | IDE | 0.2.38 | Enhanced dangerous-shell-command detection (manual review required) |

### Compliance & Data Residency

| Date | Surface | Version | Feature |
|------|---------|---------|---------|
| 2026-05-26 | Gen | — | HIPAA eligible service (IDE + CLI; Web excluded) |
| 2026-02-18 | Gen | — | AWS GovCloud (US-East/West) support — IAM IdC, TLS 1.2+, in-region storage |
| 2025-09-23 | IDE | 0.2.68 | Security fixes: CVE-2025-10585 (V8) + PowerShell command-execution vuln |

---

## 2. Governance Controls for Banking

### 2.1 MCP Registry Governance (IDE 0.11 / CLI 1.23.0+)
Centrally restrict which MCP servers developers may use — the enforcement
mechanism behind the Tier 1/2/3 MCP model in the main SDLC guide.

- Host a JSON registry over **HTTPS**; configure its URL in the Kiro console.
- Supports remote (HTTP) and local (stdio) servers across npm, PyPI, OCI.
- **Version-pinned** entries prevent silent upgrades to unreviewed versions.
- Use `${VAR}` placeholders for user-specific values (e.g. auth tokens).
- Syncs every 24h; works with the existing MCP on/off toggle.

> **MAS mapping:** TRM 3.1 (Governance), 11.2 (Network Security — controls
> outbound integrations). Pin versions and require a change record per registry update.

### 2.2 Model Governance (IDE 0.11)
Curate an approved model list and set a default model org-wide.

- Console → Settings → Shared settings → Model availability.
- Critical for **data residency**: exclude experimental models that use
  *global* cross-region inference until they reach GA with regional inference.
- Only approved models appear in the selector across IDE and CLI.

> **MAS mapping:** TRM 10 (Cryptography/data handling), data-residency obligations.

### 2.3 Web Tools Governance (IDE 0.9 / CLI 1.25.0)
Disable `web_search` and `web_fetch` organization-wide to prevent
uncontrolled external data flows. Aligns with the Tier 3 "prohibited"
classification for web/browser tools in the main guide.

### 2.4 Subagent Access Control (CLI 1.25.0)
Restrict which agents may be spawned as subagents via `availableAgents` and
`trustedAgents` (glob patterns supported, e.g. `test-*`). Prevents
unreviewed custom agents from executing in regulated workspaces.

### 2.5 Activity & Subscription Reporting (General)
Daily activity reports (S3 CSV) now include `User_Email` and per-model
message counts; console shows user emails; subscription data is CSV-exportable.

> **MAS mapping:** TRM 15 (IT Audit). Feed reports into your SIEM and retain
> per your audit-retention policy (≥ the guide's 90-day minimum).

---

## 3. Identity & Authentication

- **External IdP (Okta / Entra ID) + SCIM** (IDE 0.9.40 / CLI 1.25.1):
  Connect alongside AWS IAM Identity Center; auto-sync users/groups via SCIM.
  Configure once for both IDE and CLI. Continue to block social logins and
  AWS Builder ID at the firewall per the main guide.
- **Device Flow / Remote Auth** (CLI 1.24.0, 2.1): For SSH/SSM/container/VDI
  sessions without port forwarding. Useful for Amazon WorkSpaces VDI.

> **MAS mapping:** TRM 9.1 (Access Control). Enforce MFA at the IdP; rely on
> SCIM deprovisioning for leavers.

---

## 4. Tool, Command & Web Access Controls

### 4.1 Granular Tool Trust (CLI 1.27)
Per-action trust tiers instead of blanket approval:

- **Shell:** trust exact command / command + any args / base command wildcard.
- **Read/Write:** scope to a specific file, its directory, or the whole tool.
- Chained shell commands are handled automatically.

Prefer the **narrowest** scope; avoid universal `*` trust in banking workspaces.

### 4.2 `web_fetch` URL Permissions (CLI 1.24.0)
Regex allow/block lists in agent config; **block patterns take precedence**.
Unmatched URLs prompt for approval.

```json
{
  "tools": ["web_fetch"],
  "toolsSettings": {
    "web_fetch": {
      "allowedUrls": ["^https://docs\\.aws\\.amazon\\.com/.*"],
      "blockedUrls": [".*"]
    }
  }
}
```

### 4.3 Pre/Post Tool Use Hooks (IDE 0.9)
Pre Tool Use hooks can **block** a tool or inject context before it runs;
Post Tool Use hooks enable logging/formatting after. Filter by category
(read/write/shell/web) or specific tool names. Use Pre hooks as a
defence-in-depth guardrail; Post hooks to emit audit log entries.

### 4.4 MCP OAuth Client ID (CLI 2.3.0)
For HTTP MCP servers lacking Dynamic Client Registration, set a pre-registered
`oauth.clientId` instead of running a custom proxy — keeps the auth path
auditable for approved Tier 2 servers.

---

## 5. Compliance & Data Residency

- **HIPAA eligible** (2026-05-26): Kiro IDE and CLI only. **Kiro Web is not
  HIPAA eligible** — exclude it from regulated workloads.
- **AWS GovCloud (US)** (2026-02-18): IAM Identity Center auth (GovCloud Start
  URL); inference via Amazon Bedrock in GovCloud (US-West); content stays in
  your profile's region; cross-region traffic encrypted TLS 1.2+. Social /
  Builder ID logins are unavailable in GovCloud.
- Keep clients patched — security fixes ship via client releases
  (e.g. IDE 0.2.68 addressed CVE-2025-10585).

---

## 6. Recommended Banking Baseline

| Control | Setting | Rationale |
|---------|---------|-----------|
| MCP servers | Registry allow-list, version-pinned | Tier 1/2/3 enforcement |
| Models | Approved list, regional inference only | Data residency |
| Web tools | Disabled org-wide (or strict `web_fetch` regex) | Prevent data egress |
| Subagents | `availableAgents`/`trustedAgents` allow-list | Block unvetted agents |
| Tool trust | Narrowest scope; no universal `*` | Least privilege |
| Identity | IdP + SCIM, MFA, no social/Builder ID | Access control |
| Telemetry/content | Opt out (enterprise content not used) | Confidentiality |
| Reporting | Export activity CSV → SIEM, retain ≥ 90 days | Audit trail |

---

## 7. Adoption Checklist

- [ ] MCP registry published over HTTPS and configured in console (version-pinned)
- [ ] Approved-model list set; experimental/global-inference models excluded
- [ ] Web search/fetch disabled or `web_fetch` restricted to AWS docs domains
- [ ] `availableAgents`/`trustedAgents` allow-lists defined
- [ ] Granular tool-trust scopes documented for standard workflows
- [ ] External IdP + SCIM configured; MFA enforced; social/Builder ID blocked
- [ ] Activity & subscription reports flowing to SIEM with retention policy
- [ ] Clients on supported versions; patch cadence defined
- [ ] Kiro Web excluded from regulated (HIPAA / MAS) workloads

---

## 8. References

- [Kiro Changelog](https://kiro.dev/changelog/) · [CLI Changelog](https://kiro.dev/changelog/cli/)
- `kiro-docs/privacy-and-security.md`, `kiro-docs/mcp-security.md`
- `Kiro-Agentic-SDLC-Banking-Best-Practices.md` (MAS TRM mapping)
- [MAS TRM Guidelines](https://www.mas.gov.sg/regulation/guidelines/technology-risk-management-guidelines)

> **Disclaimer:** Informational only; not legal/compliance advice. Validate
> all controls against your own regulatory obligations. Feature availability
> varies by subscription tier and sign-in method.
