# Kiro Security & Governance Features (Banking Reference)

A consolidated, banking-focused reference of Kiro's security and governance
capabilities across **CLI**, **IDE**, and **General/Enterprise** surfaces,
compiled from the official Kiro changelog. Use this alongside
`privacy-and-security.md`, `mcp-security.md` and
`permissions-and-managed-settings.md` when designing a
MAS-aligned Kiro deployment.

> **Last reviewed:** 2026-10-08. Verify current behaviour against
> https://kiro.dev/changelog/ before relying on any single item.
> Scope: security/governance-relevant changes only — productivity/UX-only
> releases (e.g. CLI 2.2/2.4, IDE 0.12) are intentionally not itemised.
> Latest versions on 2026-10-08: Kiro IDE 1.2.37 and Kiro CLI 2.28.0 (both 2026-10-05).

> **CLI "V3" is an engine, not a version.** There is no Kiro CLI 3.x binary.
> The V3 engine ships inside CLI 2.x (`kiro-cli --v3`; docs at
> https://kiro.dev/docs/cli/v3/). It uses the same agent harness as the IDE and
> Kiro Web and brings capability-based `permissions.yaml`, standalone
> `.kiro/hooks/*.json` hook files, Markdown agent configs, the Spec agent, plan
> mode and trusted workspaces; it removes `aws_tool`. CLI 2.26.0 shows a
> deprecation notice for Classic sessions, and CLI 2.28.0 offers to switch
> Classic sessions to 3.0.

---

## 1. Feature Inventory

Surface legend: **CLI** = Kiro CLI · **IDE** = Kiro IDE · **Gen** = General /
Enterprise (console, account, compliance) · **Models** = model launches.

### Governance (enterprise admin controls)

| Date | Surface | Version | Feature |
|------|---------|---------|---------|
| 2026-10-01 | Gen | — | **MCP registry** docs updated: exact version pinning (ranges rejected; a local server at another version is relaunched at the registry version); applies to the IDE and CLI, not Kiro Web |
| 2026-09-30 | IDE | 1.2 (1.2.4) | **Enterprise sign-in controls** in `managed-settings.json`; Workflows (off by default) |
| 2026-09-30 | CLI | 2.26.0 | Workflows (opt-in); deprecation notice for Classic sessions |
| 2026-09-01 | Gen | — | **OpenTelemetry usage export**: daily `kiro.daily.*` metrics to your OTLP collector (usage only, not an audit trail) |
| 2026-08-12 | CLI | 2.18.0 | **Cloud Sessions off unless an administrator turns them on** (organizations that already had them on stay on); cloud sessions run in us-east-1 only (Section 2.7) |
| 2026-08-11 | CLI | 2.17.0 | "Kiro Web (Preview)" toggle renamed **Cloud Sessions** (controls Kiro Web, Agent Focus cloud sessions and `kiro-cli --cloud`) |
| 2026-06-25 | IDE | 1.0.0 | **Admin permission policies** (`managed-settings.json`, `deny`/`ask` only) as part of the new permission system (see Tool table) |
| 2026-05-29 | CLI | 2.5.0 | Subagent Review Loops (self-correcting pipelines) + Display/Accessibility settings |
| 2026-05-27 | Gen | — | `User_Email` column in daily user activity reports (S3 CSV) |
| 2026-04-24 | Gen | — | Per-model message counts in user activity reports |
| 2026-04-13 | Gen | — | User emails shown in Kiro console (IAM Identity Center) |
| 2026-04-13 | CLI | 2.0 | Admin control of API key generation (governance settings) |
| 2026-03-27 | Gen | — | Subscription data CSV export from console |
| 2026-03-11 | IDE | 0.11 | **MCP Registry Governance** — HTTPS-hosted JSON allow-list of approved MCP servers, version-pinned, 24h sync |
| 2026-03-11 | IDE | 0.11 | **Model Governance** — approved-model list + default model (data-location control: exclude Global-scope models, whose inference may run in AWS Regions worldwide) |
| 2026-02-05 | IDE | 0.9 | Web Tools Governance (disable web search/fetch org-wide) |
| 2026-02-05 | IDE | 0.9 | Custom Extension Registry (private, vetted extensions vs Open VSX) |
| 2026-02-04 | CLI | 1.25.0 | Enterprise Web Tools Governance + Subagent Access Control (`availableAgents`/`trustedAgents`) |
| 2025-12-18 | CLI | 1.23.0 | MCP Registry Support (org-level MCP allow-list) |
| 2025-11-17 | IDE | 0.6 | Enterprise governance of telemetry and MCP settings |

### Models

| Date | Model | Status | Notes |
|------|-------|--------|-------|
| 2026-10-02 | Claude Sonnet 5.5 | Experimental support | us-east-1 and eu-central-1 profiles (Pro tiers and above); 1M context; 1.3x credits |
| 2026-09-28 | Claude Opus 5.5 | Experimental support | us-east-1 and eu-central-1 profiles (Pro tiers and above); 1M context; 2.0x credits |
| 2026-09-16 | Claude Fable 5.1 | Preview (Kiro Enterprise; enabled by administrators through model governance) | Inference in us-east-1 only; 1M context; 6x credits; all traffic retained for up to 30 days; classifier-flagged traffic may be reviewed by humans at AWS |
| 2026-09-14 | GPT-5.6 Sol / Terra / Luna | 1M context window rolling out gradually with experimental support | Global inference scope; two-tier credits (see Section 2.2.1) |

See the model approval matrix in Section 2.2.1.

### Identity & Authentication

| Date | Surface | Version | Feature |
|------|---------|---------|---------|
| 2026-09-30 | IDE | 1.2 (1.2.4) | **Sign-in method controls** (`signin_method` rule in `managed-settings.json`); authentication fixes |
| 2026-09-28 | CLI | 2.25.0 | Sign-in method controls honoured from CLI 2.25.0; authentication and security reliability updates |
| 2026-02-12 | IDE/CLI | 0.9.40 / 1.25.1 | External IdP support (Okta, Microsoft Entra ID) + SCIM provisioning |
| 2026-04-24 | CLI | 2.1 | Device Flow auth for remote/SSH/container environments |
| 2026-01-16 | CLI | 1.24.0 | Remote Authentication (device code over SSH/SSM/containers) |

### Tool, Command & Web Access Control

| Date | Surface | Version | Feature |
|------|---------|---------|---------|
| 2026-10-05 | CLI | 2.28.0 | Switch Classic sessions to 3.0 (upgrades agent configs, makes 3.0 the default); **V3 hooks can match by category** or a specific MCP server/tool |
| 2026-10-05 | IDE | 1.2.37 | Latest IDE 1.2 patch (the changelog lists no security-specific change) |
| 2026-10-01 | CLI | 2.27.0 | Tighter access to local Kiro state; steering file references follow the session's file-read policy |
| 2026-09-30 | IDE | 1.2 (1.2.4) | **Protected configuration**: asks before the agent edits agent, hook or Power files or Workflow recipes, even when broader permissions allow the write. **Safer untrusted workspaces**: asks before every command and every Kiro config change; recipes are not loaded |
| 2026-09-30 | CLI | 2.26.0 | **V3 approval safeguards**: stricter checks for hook and LSP file writes, for MCP tools and shell commands in untrusted workspaces, and for approvals that change while an action waits |
| 2026-09-28 | CLI | 2.25.0 | New `SessionEnd` hook trigger (V3) |
| 2026-09-23 | CLI | 2.24.0 | **`/tools trust-all`** (V3): session-wide tool approval after a warning; cannot override admin `deny`/`ask`. Project `.env` files are no longer loaded automatically into chats, MCP servers or tools |
| 2026-09-14 | IDE | 1.1 | Clearer MCP failure messages; more reliable hooks |
| 2026-06-25 | IDE | 1.0.0 | **Capability-based permissions** (`permissions.yaml`; `deny > ask > allow` across scopes) replace Trusted Commands and the Command Denylist (breaking change); unified v1 hook files (`.kiro/hooks/*.json`) |
| 2026-05-12 | CLI | 2.3.0 | OAuth Client ID for MCP servers (`oauth.clientId`) |
| 2026-04-24 | CLI | 2.1 | Tool Search — on-demand MCP tool loading (context-window hygiene) |
| 2026-03-02 | CLI | 1.27 | Granular Tool Trust — tiered scopes for shell commands & file paths (Classic; superseded by permissions in V3) |
| 2026-02-18 | IDE | 0.10 | MCP Prompts / Resource Templates / Elicitation (controlled context injection) |
| 2026-02-05 | IDE | 0.9 | Pre/Post Tool Use Hooks — Pre hooks can block tools before execution (current rule: only exit code 2 blocks; see 4.3) |
| 2026-01-16 | CLI | 1.24.0 | Granular URL permissions for `web_fetch` (regex allow/block in Classic agent config; superseded by the `web_fetch` capability, see 4.2) |
| 2025-09-04 | IDE | 0.2.38 | Enhanced dangerous-shell-command detection (manual review required) |

### Compliance & Data Location

| Date | Surface | Version | Feature |
|------|---------|---------|---------|
| 2026-09-30 | IDE | 1.2 (1.2.4) | Enterprise traffic, telemetry and activity data stay in the profile region |
| 2026-09-14 | IDE | 1.1 | Enterprise profiles route requests to the selected region |
| 2026-09-01 | Gen | — | Kiro included in the AWS ISO/IEC 27001:2022 certification scope |
| 2026-06-25 | Gen | — | FedRAMP High and DoD IL-4/5 authorization — **AWS GovCloud (US) only** |
| 2026-05-26 | Gen | — | HIPAA eligible service (IDE + CLI; Web excluded) |
| 2026-02-18 | Gen | — | AWS GovCloud (US-East/West) support — IAM IdC, TLS 1.2+, in-region storage |
| 2025-09-23 | IDE | 0.2.68 | Security fixes: CVE-2025-10585 (V8) + PowerShell command-execution vuln |

---

## 2. Governance Controls for Banking

### 2.1 MCP Registry Governance (IDE 0.11 / CLI 1.23.0+)
Centrally restrict which MCP servers developers may use — the enforcement
mechanism behind the Tier 1/2/3 MCP model in the main SDLC guide.

- Kiro console → Settings → Shared settings: turn MCP on and set the **MCP
  Registry URL**. The registry is a JSON file (`{"servers": [{"server": {...}}]}`,
  a subset of the MCP registry standard v0.1 server schema) hosted over **HTTPS**
  with a certificate from a trusted CA (self-signed certificates are rejected).
- Supports remote (`streamable-http` or `sse`) and local (stdio) servers from
  npm, PyPI and OCI (run with `npx`, `uvx` and `docker`).
- **Pin exact versions:** Kiro rejects ranges such as `^1.2.3`, `~1.2.3`, `1.x`,
  and relaunches a locally installed server at another version at the registry
  version. Non-semantic version strings are accepted, so Kiro would not reject
  `latest`: never use it.
- Servers not in the registry are hidden, including entries in users' own
  `mcp.json`; users can only add environment variables, headers, a timeout,
  scope and tool trust to a listed server. Use `${VAR}` placeholders for
  user-specific values (e.g. auth tokens).
- Fetched at startup and every 24 hours; servers removed from the registry are
  terminated. Works with the MCP on/off toggle.
- Applies to IAM Identity Center and API-key users in the IDE and CLI; not to
  Builder ID or social sign-in users, and not to Kiro Web. Client-enforced, so
  a local administrator can circumvent it. If the client cannot reach the
  governance API, MCP is disabled.
- Example file: [`../managed-settings/mcp-registry.example.json`](../managed-settings/mcp-registry.example.json);
  details in Part 2, Section 5.

> **MAS mapping:** TRM 3.4 (Management of Third Party Services), 6.1.3 (review and
> test third-party code before integration), 11.2 (Network Security — controls
> outbound integrations). Pin versions and require a change record per registry update.

### 2.2 Model Governance (IDE 0.11)
Curate an approved model list and set a default model org-wide.

- Console → Settings → Shared settings → Model availability → Manage approved list.
- Critical for **data location**: inference scope is set per model (Inference
  endpoint regions table on the [models page](https://kiro.dev/docs/models/)).
  Geography-scope models, which include all Claude models, use cross-region
  inference within the profile's geography (US or Europe). Global-scope models
  (currently GPT-5.6 Sol, Terra and Luna) may be processed in supported
  commercial AWS Regions worldwide and use the US endpoint even for
  `eu-central-1` profiles. Experimental or preview status does not determine
  routing. Kiro has no setting to disable cross-region inference, so the allow
  list is the control: exclude Global-scope models (and review preview terms
  such as Claude Fable 5.1's 30-day retention). See the matrix in Section 2.2.1.
- When the list is managed, new models are not available until an administrator
  adds them.
- Only approved models appear in the selector across IDE and CLI. Users restart
  or sign in again to pick up a change.

> **MAS mapping:** TRM 3.4 / 4.3 (third-party services and risk assessment of model
> providers), 11.1 (Data Security). The allow list also supports the PDPA Transfer
> Limitation Obligation (s26) assessment of where prompts are processed; MAS TRM
> itself imposes no data-localisation mandate.

#### 2.2.1 Model approval matrix

Based on the Kiro changelog, the [models page](https://kiro.dev/docs/models/)
(Inference endpoint regions table) and the
[data-protection page](https://kiro.dev/docs/privacy-and-security/data-protection/),
all checked on 2026-10-08. "Not documented" means Kiro publishes no
model-specific statement: enterprise content is not used for service
improvement, but "model-specific retention requirements for abuse detection
purposes may apply".

| Model | Inference location | Experimental / preview | Retention / human review | Credit multiplier | Recommended default for MAS institutions |
|-------|--------------------|------------------------|--------------------------|-------------------|------------------------------------------|
| Claude Fable 5.1 | Geography scope; us-east-1 only (no Frankfurt endpoint) | Preview (Kiro Enterprise; enabled by administrators) | All traffic retained for up to 30 days for automated abuse detection; classifier-flagged traffic may be reviewed by humans at AWS (an exception to the enterprise content opt-out) | 6x | **Exclude by default** |
| Claude Opus 5.5 | Geography scope: US endpoint for us-east-1 profiles, EU endpoint for eu-central-1 profiles | Experimental support (changelog, 2026-09-28) | Not documented | 2.0x | **Exclude by default** until it leaves experimental status and is assessed |
| Claude Sonnet 5.5 | Geography scope: US endpoint for us-east-1 profiles, EU endpoint for eu-central-1 profiles | Experimental support (changelog, 2026-10-02) | Not documented | 1.3x | **Exclude by default** until it leaves experimental status and is assessed |
| GPT-5.6 Sol / Terra / Luna | **Global** scope (AWS Regions worldwide); the US endpoint is used for eu-central-1 profiles too | 1M context window rolling out with experimental support (changelog, 2026-09-14) | Only classifier-flagged traffic retained (up to 30 days) | Up to 272K tokens: Sol 4.4x, Terra 2.2x, Luna 0.6x; larger requests at double the rate | **Exclude by default** |
| Other models | Per the Inference scope column of the models page (Geography for every other model listed on 2026-10-08) | Check the models page and changelog | Not documented per model | See the models page | **Approve** individually after third-party assessment (TRM 3.4) |

- **Lifecycle status and inference scope are independent** (models and
  data-protection pages, updated 2026-10-08): check the Inference scope column of
  the models page for each model, not its experimental or preview status.
  "Geography" means within the endpoint geography shown in the row; "Global"
  means across supported commercial AWS Regions worldwide, including outside the
  endpoint geography. Cross-region inference, including global routing, does not
  change where Kiro stores data, and global routing does not apply to AWS
  GovCloud (US).
- **Docs conflict:** the GPT-5.6 changelog entry (2026-09-14) gives Luna as 1.1x
  for requests up to 272K tokens; the newer models page (2026-10-08) gives 0.6x
  (1.2x above 272K). The models page is used here.
- Re-check the matrix at every model launch: with a managed list, a new model
  stays unavailable until an administrator adds it.

### 2.3 Web Tools Governance (IDE 0.9 / CLI 1.25.0)
Disable `web_search` and `web_fetch` organization-wide to prevent
uncontrolled external data flows. Aligns with the Tier 3 "prohibited"
classification for web/browser tools in the main guide. Web search and web
fetch are on by default; turn them off under Shared settings, or set them to
`ask` / `deny` in the admin policy (Section 4.2).

### 2.4 Subagent Access Control (CLI 1.25.0)
Restrict which agents may be spawned as subagents via `availableAgents` and
`trustedAgents` (glob patterns supported, e.g. `test-*`). Prevents
unreviewed custom agents from executing in regulated workspaces. In the
permission system of IDE 1.0 and CLI V3, the `subagent` capability can also be
set to `ask` or `deny` in the admin policy.

### 2.5 Activity & Subscription Reporting (General)
Daily activity reports (S3 CSV) now include `User_Email` and per-model
message counts; console shows user emails; subscription data is CSV-exportable.

> **MAS mapping:** TRM 12.2 (Cyber Event Monitoring and Detection); the reports also
> serve as evidence for the independent IT audit function (TRM 15.1). Feed reports
> into your SIEM and retain per your audit-retention policy (≥ the guide's 90-day minimum).

### 2.6 Admin Policy: `managed-settings.json` (IDE 1.0+ / CLI V3; sign-in controls IDE 1.2+ / CLI 2.25.0+)
- Deployed by MDM or GPO to `/Library/Application Support/Kiro/managed-settings.json`
  (macOS), `C:\ProgramData\Kiro\managed-settings.json` (Windows, UTF-8 without BOM)
  or `/etc/kiro/managed-settings.json` (Linux); restart Kiro to apply.
- Admin rules may only `deny` or `ask`, and win over every user, workspace,
  agent and session `allow` (`deny > ask > allow`). Headless runs treat `ask` as
  `deny`.
- Permission rules fail closed (a malformed file, an `allow` effect or an unknown
  field blocks all tool calls); sign-in controls fail open.
- Client-enforced: a user with local administrator rights can circumvent it.
- Reference: [`permissions-and-managed-settings.md`](permissions-and-managed-settings.md);
  deployable files: [`../managed-settings/`](../managed-settings/).

### 2.7 API Keys and Cloud Sessions
- **API keys** (CLI 2.0): generation is off by default; keep it off unless a use
  case is assessed.
- **Cloud Sessions** (CLI 2.17.0 rename; off unless an administrator turns it on
  since CLI 2.18.0): controls Kiro Web, Agent Focus cloud sessions and
  `kiro-cli --cloud`. Cloud sessions run in us-east-1 only, and the customer
  managed KMS key, MCP configuration, MCP registry and model availability do not
  apply to them. Keep Cloud Sessions **off** for MAS institutions and review the
  decision periodically.

### 2.8 Prompt Logging, Activity Reports and OpenTelemetry
- **Prompt logging:** console → Kiro Settings → Logging → "Log Kiro prompts with
  metadata". Logs prompts and responses (chat and inline suggestions) from the IDE
  and CLI to an S3 bucket in the profile region and the subscribing account.
  Bucket policy principal `q.amazonaws.com`, action `s3:PutObject`, condition
  `aws:SourceArn` = `arn:aws:codewhisperer:<region>:<account-id>:*` (Part 2,
  Section 9.3).
- **User activity reports:** daily CSV per client type (02:00 UTC), same region
  and account, prefix required.
- **OpenTelemetry usage export** (2026-09-01): daily `kiro.daily.*` metrics. It
  needs a KMS key, a Secrets Manager secret (`OTEL_EXPORTER_OTLP_ENDPOINT`,
  `OTEL_EXPORTER_OTLP_HEADERS`) and the profile in the same region, and a collector
  that is publicly reachable with a public TLS certificate. It is a usage feed,
  **not an audit trail**.
- **CloudTrail:** Kiro docs say only that CloudTrail "captures API calls"; they do
  not document Kiro event source names or data events. Verify in your own account.
  MCP tools run on the client and do not appear in CloudTrail.

---

## 3. Identity & Authentication

- **External IdP (Okta / Entra ID) + SCIM** (IDE 0.9.40 / CLI 1.25.1):
  Connect alongside AWS IAM Identity Center; auto-sync users/groups via SCIM.
  Configure once for both IDE and CLI. Restrict sign-in to IAM Identity Center
  with the managed-settings `signin_method` rule (client-enforced; IDE 1.2+ /
  CLI 2.25+) and block the social sign-in host
  (`cognito-identity.us-east-1.amazonaws.com`) at the firewall. Do not block
  `prod.us-east-1.auth.desktop.kiro.dev`: all sign-in methods use it.
  Sign-in controls fail open and do not apply to Kiro Web.
- **Device Flow / Remote Auth** (CLI 1.24.0, 2.1): For SSH/SSM/container/VDI
  sessions without port forwarding. Useful for Amazon WorkSpaces VDI.

> **MAS mapping:** TRM 9.1 (User Access Management). Enforce MFA at the IdP; rely on
> SCIM deprovisioning for leavers. Banks: MAS Notice FSM-N06 para 4.6 requires MFA
> for all administrative accounts on critical systems.

---

## 4. Tool, Command & Web Access Controls

### 4.1 Permissions (IDE 1.0+ / CLI V3; replaces Trusted Commands and Granular Tool Trust)
Capability-based rules (`capability`, `match`, `exclude`, `effect`) in
`~/.kiro/settings/permissions.yaml` (user), `~/.kiro/workspace-roots/<hash>/permissions.yaml`
(workspace, stored outside the repository), the agent `permissions` field,
session decisions, and the admin policy (Section 2.6).

- Capabilities: `fs_read`, `fs_write`, `shell`, `web_fetch`, `web_search`, `mcp`,
  `subagent`, `skill`, `power`, `context`, `diagnostics`, `sandbox_network`.
- `deny > ask > allow` with no precedence between scopes; admin rules cannot be
  weakened by `--trust-all-tools` or `/tools trust-all`.
- Kiro hardcoded invariants: the agent can never write `~/.kiro/settings/`,
  `.kiro/settings/` or `~/.kiro/workspace-roots/`, and Kiro always asks before
  it writes `.git/**` or the agents, hooks, workflows and powers directories.
- IDE autonomy `kiroAgent.agentAutonomy` (`Autopilot` or `Supervised`) is decided
  first; the permission rules apply after it.
- Legacy: CLI 1.27 Granular Tool Trust and Classic agent `toolsSettings` are
  superseded; convert with `kiro-cli agent migrate`. `autoAllowReadonly` and
  `denyByDefault` have no equivalent.

Prefer the **narrowest** scope; avoid `capability: all` and blanket session
trust in banking workspaces.

### 4.2 `web_fetch` / `web_search` Permissions
Use the `web_fetch` and `web_search` capabilities of the permission system. In
the admin policy only `deny` and `ask` are allowed; the official example below
denies every domain except the excluded ones (excluded domains fall through to
the user's own rules):

```json
{
  "rules": [
    { "capability": "web_fetch", "exclude": ["docs.aws.amazon.com"], "effect": "deny" },
    { "capability": "web_search", "effect": "deny" }
  ]
}
```

Shell, web and MCP patterns support only `*` (any sequence of characters), not
regular expressions. The CLI 1.24.0 `toolsSettings.web_fetch` regex lists apply
to Classic agent configs only: `toolsSettings` is deprecated in CLI 3.0 and IDE
1.0 (the V3 agent-configuration page says it is removed in V3 — docs conflict).
Where web tools are off in the Kiro console (Section 2.3), keep an admin `deny`
or `ask` as a second layer.

### 4.3 Hooks (IDE 0.9; v1 hook files since IDE 1.0 / CLI V3)
Hook files (`.kiro/hooks/*.json`, `~/.kiro/hooks/`) run commands or agent
prompts on triggers such as `PreToolUse`, `PostToolUse`, `UserPromptSubmit`,
`Stop`, `SessionStart` and `SessionEnd` (CLI 2.25.0). Filter by category
(`read`, `write`, `shell`, `web`, `@mcp`) or tool name; CLI 2.28.0 lets V3 hooks
match by category.

- **Only exit code 2 blocks**, and only for `PreToolUse`, `UserPromptSubmit` and
  `PreTaskExec`; STDERR is returned to the model. Any other non-zero exit is
  treated as an error, not a block: the tool call proceeds with a warning.
- **Docs conflict:** an older Hook actions page (2026-08-04) says any non-zero
  exit blocks. Write guard hooks to exit 2 on a policy block **and** on any
  internal error, so that they block under either reading.
- Timeouts: v1 files `timeout` in seconds (default 60); CLI 2.x embedded agent
  hooks `timeout_ms` (default 30000). Kiro does not document that a timed-out
  hook blocks the call.
- Use Pre hooks as a **defence-in-depth** guardrail, not as the primary control;
  Post hooks emit audit entries, which are supplementary (not tamper-proof).
- Repository hooks: [`../agent-hooks/README.md`](../agent-hooks/README.md).

### 4.4 MCP OAuth Client ID (CLI 2.3.0)
For HTTP MCP servers lacking Dynamic Client Registration, set a pre-registered
`oauth.clientId` instead of running a custom proxy — keeps the auth path
auditable for approved Tier 2 servers.

---

## 5. Compliance & Data Location

- **Profile region** (verified 2026-10-08 against
  https://kiro.dev/docs/enterprise/supported-regions/ and
  https://kiro.dev/docs/privacy-and-security/data-protection/): commercial
  Kiro profiles exist only in `us-east-1` and `eu-central-1` (plus AWS GovCloud
  (US)); there is no Singapore profile region. Content, prompt logs and user
  activity reports are stored in the profile region; IAM Identity Center can
  stay in `ap-southeast-1`. Inference may run in other regions of the same
  geography; Global-scope models (currently GPT-5.6 Sol, Terra and Luna) may be
  processed in AWS Regions worldwide (Section 2.2). For a Singapore
  institution this is a cross-border transfer: see Part 2, Section 7.2.
- **Telemetry location** (IDE 1.2): telemetry and activity data go to an endpoint
  in the profile region; if there is none, the IDE drops the telemetry.
- **Compliance validation** (https://kiro.dev/docs/privacy-and-security/compliance-validation/):
  Kiro lists HIPAA eligibility and inclusion in the AWS ISO/IEC 27001:2022 scope
  (since 2026-09-01). No SOC or MTCS report is listed for Kiro; check AWS Artifact
  before relying on one. FedRAMP High and DoD IL-4/5 (2026-06-25) apply to AWS
  GovCloud (US) only.
- **HIPAA eligible** (2026-05-26): Kiro IDE and CLI only. **Kiro Web is not
  HIPAA eligible** — exclude it from regulated workloads.
- **AWS GovCloud (US)** (2026-02-18): IAM Identity Center auth (GovCloud Start
  URL); inference via Amazon Bedrock in GovCloud (US-West); content stays in
  your profile's region; cross-region traffic encrypted TLS 1.2+. Social /
  Builder ID logins are unavailable in GovCloud.
- **Customer managed KMS key:** Kiro console → Settings → Encryption key;
  symmetric keys only; not supported for Kiro Web. Which features the key covers
  and its region constraint are not documented — verify.
- Keep clients patched — security fixes ship via client releases
  (e.g. IDE 0.2.68 addressed CVE-2025-10585).

---

## 6. Recommended Banking Baseline

| Control | Setting | Rationale |
|---------|---------|-----------|
| Admin policy | `managed-settings.json` deployed by MDM/GPO (deny/ask rules + sign-in restriction) | Client-enforced baseline that user and session settings cannot weaken |
| MCP servers | MCP governance on; registry allow-list with exact pinned versions | Tier 1/2/3 enforcement |
| Models | Approved list; exclude Global-scope, preview and experimental models by default (Section 2.2.1) | Data location: most models use geography-level cross-region inference, Global-scope models may be processed worldwide; preview retention terms |
| Web tools | Disabled org-wide, or admin `ask`/`deny` on `web_fetch` / `web_search` | Prevent data egress |
| Subagents | `subagent` rules (IDE 1.0 / CLI V3) or `availableAgents`/`trustedAgents` (Classic) | Block unvetted agents |
| Tool trust | Narrow user `allow` rules; no `capability: all`; no `--trust-all-tools` / `/tools trust-all` in regulated repositories | Least privilege |
| Workspace trust | Leave unknown repositories untrusted | Repository content cannot load agents, steering or MCP config |
| API keys / Cloud Sessions | Off | Cloud Sessions bypass CMK, MCP registry and model availability settings |
| Identity | IdP + SCIM, MFA, no social/Builder ID | Access control |
| Telemetry/content | Enterprise users are opted out automatically; exclude models with retention exceptions | Confidentiality |
| Reporting | Prompt logging + activity CSV → SIEM, retain ≥ 90 days | Audit trail |

---

## 7. Adoption Checklist

- [ ] `managed-settings.json` deployed to the official path on every device; validated; read-only for users
- [ ] MCP governance on; registry published over HTTPS and configured in console (exact versions)
- [ ] Approved-model list set; Global-scope, preview and experimental models excluded unless assessed (Section 2.2.1)
- [ ] Web search/fetch disabled, or `web_fetch` restricted to approved domains
- [ ] Subagent rules or `availableAgents`/`trustedAgents` allow-lists defined
- [ ] User permission templates documented for standard workflows
- [ ] API key generation and Cloud Sessions off
- [ ] External IdP + SCIM configured; MFA enforced; social/Builder ID blocked
- [ ] Prompt logging, activity & subscription reports flowing to SIEM with retention policy
- [ ] Clients on supported versions (IDE 1.2+, CLI 2.25.0+ with V3 sessions); patch cadence defined
- [ ] Kiro Web excluded from regulated (HIPAA / MAS) workloads

---

## 8. References

- [Kiro Changelog](https://kiro.dev/changelog/) · [CLI Changelog](https://kiro.dev/changelog/cli/)
- [Permissions](https://kiro.dev/docs/permissions/) · [Permission policies](https://kiro.dev/docs/enterprise/governance/permissions/) · [Sign-in controls](https://kiro.dev/docs/enterprise/governance/sign-in/)
- [Enterprise governance](https://kiro.dev/docs/enterprise/governance/) · [MCP governance](https://kiro.dev/docs/enterprise/governance/mcp/) · [MCP registry](https://kiro.dev/docs/mcp/registry/) · [Model governance](https://kiro.dev/docs/enterprise/governance/model/)
- [Prompt logging](https://kiro.dev/docs/enterprise/monitor-and-track/prompt-logging/) · [Hooks](https://kiro.dev/docs/hooks/) · [CLI V3](https://kiro.dev/docs/cli/v3/)
- `kiro-docs/privacy-and-security.md`, `kiro-docs/mcp-security.md`, `kiro-docs/permissions-and-managed-settings.md`
- `Kiro-Agentic-SDLC-Banking-Best-Practices.md` (MAS TRM mapping)
- [MAS TRM Guidelines](https://www.mas.gov.sg/regulation/guidelines/technology-risk-management-guidelines)

> **Disclaimer:** Informational only; not legal/compliance advice. Validate
> all controls against your own regulatory obligations. Feature availability
> varies by subscription tier and sign-in method.
