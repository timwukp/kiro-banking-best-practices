# AWS Kiro Banking Best Practices - Part 2
## Sections 5-14: MCP Governance, SDLC, Data Protection, Operations & Regulatory Compliance

> **Audience:** security architects, compliance officers, banking developers · **Purpose:** Sections 5–14 — MCP governance, SDLC, PDPA, FEAT, operations · **Prerequisites:** read Part 1 (Sections 1–4) first · ↩ [README](README.md)

> **Kiro 1.x configuration (verified 2026-10-08 against the official Kiro docs).** Earlier versions of this part showed settings keys and commands that Kiro does not support. Remove them and use the documented mechanisms instead:
>
> | Removed (not a Kiro setting or command) | Use instead | Section |
> |------------------------------------------|-------------|---------|
> | `kiro.autopilot.enabled`, `kiro.supervised.requireApproval`, `kiro.mode`, `kiro.autoApprove`, `kiro.reviewRequired` | IDE autonomy setting `kiroAgent.agentAutonomy` plus permission rules | 6.1, 9.2 |
> | `kiro.trustedCommands` | `allow` rules in `permissions.yaml` (Kiro IDE 1.0 replaced Trusted Commands and the Command Denylist) | 6.1 |
> | `aws q update-encryption-configuration` | Kiro console > Settings > Encryption key | 7.1 |
> | `aws q update-organization-settings`; `kiro.telemetry.enabled`, `kiro.shareContentWithAWS`, `kiro.codeReferences.enabled` | Enterprise users are opted out automatically; client settings in [`kiro-docs/privacy-and-security.md`](kiro-docs/privacy-and-security.md) | 7.3 |
> | CloudTrail data resource `AWS::Q::Chat`; event name `InvokeMCPTool` | Management events, Kiro prompt logging, user activity reports and the local hook audit log | 5.3, 8.2 |
> | `aws q put-prompt-logging-configuration` | Kiro console > Settings > Kiro Settings > Logging | 9.3 |
> | `C:\ProgramData\Kiro\mcp.json` with `icacls` and a symlinked user file | MCP governance with a version-pinned registry, plus workspace trust | 5 |
> | `kiro.codeGeneration` | Branch protection and CODEOWNERS in source control; admin `ask` on `git push` | 13.2 |
> | YAML steering files (`banking-standards.yaml`) | Markdown steering files with frontmatter | 9.4, 13.4 |
>
> Deployable files: [`managed-settings/`](managed-settings/) (admin policy, user permissions template, MCP registry example) and [`agent-hooks/README.md`](agent-hooks/README.md) (hooks). Reference: [`kiro-docs/permissions-and-managed-settings.md`](kiro-docs/permissions-and-managed-settings.md).

---

## 5. MCP Server Security & Governance

MCP servers extend what the agent can reach, so treat each one as a third-party component (MAS TRM 3.4, 6.1.3). Kiro restricts MCP servers with these mechanisms:

| Control | What it does | Where |
|---------|--------------|-------|
| **MCP governance** | MCP on/off toggle and **MCP Registry URL**. Only servers listed in the registry load | Kiro console > Settings > Shared settings |
| **Workspace trust** | An untrusted workspace does not load its `.kiro/settings/mcp.json`, and Kiro asks before every MCP tool call there, even with `autoApprove` | Each Kiro client |
| **Admin permission rules** | `mcp` capability `deny` / `ask` rules; patterns are `<server>/<tool>` | `managed-settings.json` ([`managed-settings/`](managed-settings/)) |
| **Configuration files** | `~/.kiro/settings/mcp.json` (user) and `.kiro/settings/mcp.json` (workspace). The agent can never write either file (Kiro hardcoded deny); with a registry, users can only add overrides to listed servers | User profile; repository |

All of these are enforced by the Kiro client. A user with local administrator rights can circumvent them, so pair them with the endpoint controls in Part 1, Section 4.1.2 (no local admin rights, application allow-listing).

### 5.1 Centralized Whitelist Management (MCP Registry)

**Set up:** in the Kiro console, open **Settings**, and under **Shared settings** turn **Model Context Protocol (MCP)** on. Next to **MCP Registry URL** choose **Edit**, enter the HTTPS URL of the registry file, and choose **Save**.

**Registry file** (example with two local servers; [`managed-settings/mcp-registry.example.json`](managed-settings/mcp-registry.example.json) also shows environment variables, `registryBaseUrl` and a remote server entry). The versions are examples: pin the exact version that your third-party review approved.

```json
{
  "servers": [
    {
      "server": {
        "name": "aws-documentation",
        "title": "AWS Documentation",
        "description": "Search and read public AWS documentation",
        "version": "1.2.3",
        "packages": [
          {
            "registryType": "pypi",
            "identifier": "awslabs.aws-documentation-mcp-server",
            "transport": { "type": "stdio" }
          }
        ]
      }
    },
    {
      "server": {
        "name": "git",
        "title": "Git (read-only use)",
        "description": "Inspect local Git repositories",
        "version": "1.0.0",
        "packages": [
          {
            "registryType": "pypi",
            "identifier": "mcp-server-git",
            "transport": { "type": "stdio" }
          }
        ]
      }
    }
  ]
}
```

**How the registry behaves:**
- **Pin exact versions.** Kiro rejects version ranges such as `^1.2.3`, `~1.2.3`, `>=1.2.3`, `1.x` or `1.*`, and relaunches a locally installed server that runs a different version at the registry version. Kiro accepts non-semantic version strings, so it would not reject `latest`: never use it, and check for it in the publication pipeline (Section 5.2).
- **Hosting.** The file must be served over HTTPS with a certificate from a trusted CA (self-signed certificates are rejected). The URL can be private to the corporate network.
- **Refresh.** Kiro fetches the registry at startup and every 24 hours. A server removed from the registry is terminated.
- **Unlisted servers are hidden**, including entries in a user's own `mcp.json`. A user can only add environment variables, headers, a timeout, the server scope and tool trust on top of a registry entry; the package, command and version come from the registry.
- **Scope.** It applies to IAM Identity Center and API-key users in the Kiro IDE and CLI. It does not apply to AWS Builder ID or social sign-in users (block those sign-in methods; Part 1, Section 2.2) or to Kiro Web (keep Cloud Sessions off).
- **Unreachable governance API.** If the client cannot reach the governance API, MCP is disabled ("Failed to retrieve MCP settings — MCP disabled"). Keep the Kiro endpoints on the egress allowlist (Part 1, Section 3.3).
- **Runners.** Clients need `uvx` (PyPI), `npx` (npm) or `docker` (OCI) installed, and the package source must be reachable through the egress path or an internal mirror (`registryBaseUrl`).
- **Network needs of the server itself.** The registry controls which server runs, not what it connects to. The AWS Documentation server, for example, runs locally but fetches pages from AWS documentation hosts on the internet, so it only works if those hosts are on the egress allowlist. The alternative is a remote endpoint such as the AWS Knowledge MCP Server (`https://knowledge-mcp.global.api.aws`, no authentication, rate-limited), which needs egress to that host instead. Record the hosts each approved server needs in its change record.
- **Change control.** Treat every registry change as a change record: which server and version, who approved it, the third-party review, and how to roll back.

**User configuration referencing the registry** (`~/.kiro/settings/mcp.json`; overrides only):

```json
{
  "mcpServers": {
    "aws-documentation": { "type": "registry", "timeout": 60000 },
    "git": { "type": "registry" }
  }
}
```

**Restrict tools of an approved server** with an admin rule in `managed-settings.json` (add it to the `rules` array of the single file you deploy). The tool names below are those of the reference `mcp-server-git` server and are examples: list the tools of the exact version you pinned and update the rule when the version changes.

```json
{
  "capability": "mcp",
  "match": ["git/git_commit", "git/git_add", "git/git_reset", "git/git_create_branch", "git/git_checkout"],
  "effect": "deny"
}
```

**Filesystem MCP servers:** Kiro's built-in file tools already read and write files, and they are governed by the `fs_read` / `fs_write` rules (for example the admin deny on `**/.env`). File access by an MCP server is governed only by `mcp` rules, so a filesystem MCP server would bypass those file rules. Do not approve one unless there is a specific need and a security review.

### 5.2 MCP Configuration Validation

Kiro itself rejects malformed registry entries and version ranges. Run an additional pre-publication check in the pipeline that publishes the registry, so that only servers with an approved change record reach the HTTPS location. The `jq` checks in [`managed-settings/README.md`](managed-settings/README.md#validation) cover the format; the sketch below also checks the approved list.

**Validation Script (sketch):**
```python
import json
import re
import sys

# Approved servers from the change records: registry name -> package identifier or remote URL
APPROVED = {
    "aws-documentation": "awslabs.aws-documentation-mcp-server",
    "git": "mcp-server-git",
}
EXACT_VERSION = re.compile(r"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$")
NAME = re.compile(r"^[a-zA-Z0-9._-]{3,200}$")


def validate_registry(path):
    with open(path, encoding="utf-8") as f:
        registry = json.load(f)

    errors, seen = [], set()
    for entry in registry.get("servers", []):
        server = entry.get("server", {})
        name = server.get("name", "")
        version = server.get("version", "")
        packages = server.get("packages", [])
        remotes = server.get("remotes", [])

        if not NAME.match(name):
            errors.append(f"invalid name: {name!r}")
        if name in seen:
            errors.append(f"duplicate name: {name}")
        seen.add(name)
        if name not in APPROVED:
            errors.append(f"{name}: no approved change record")
        if not EXACT_VERSION.match(version):
            errors.append(f"{name}: version must be exact, got {version!r}")
        if len(packages) + len(remotes) != 1:
            errors.append(f"{name}: needs exactly one package or one remote")
        for package in packages:
            if package.get("identifier") != APPROVED.get(name):
                errors.append(f"{name}: package {package.get('identifier')!r} is not the approved one")
        for remote in remotes:
            if not remote.get("url", "").startswith("https://"):
                errors.append(f"{name}: remote URL must use HTTPS")
            elif remote.get("url") != APPROVED.get(name):
                errors.append(f"{name}: remote URL is not the approved one")
    return errors


if __name__ == "__main__":
    problems = validate_registry(sys.argv[1])
    for problem in problems:
        print(f"ERROR: {problem}")
    sys.exit(1 if problems else 0)
```

### 5.3 MCP Usage Monitoring

MCP tools run on the client: a local (stdio) server runs on the developer's machine, and the client calls a remote server directly. Kiro does not document a CloudTrail event for MCP tool calls, so CloudTrail cannot show MCP usage. Use these sources instead:

- **Hook audit log:** a `PostToolUse` hook records each tool call on the device, including MCP tools (see [`agent-hooks/README.md`](agent-hooks/README.md)). Ship it to CloudWatch Logs with the CloudWatch agent. It is supplementary evidence: the file is user-writable unless the OS makes it append-only, and it is not tamper-proof.
- **Remote MCP servers you host:** the server's own access logs are the authoritative record of calls to it.
- **Client MCP logs:** Kiro panel → Output → "Kiro - MCP Logs" (troubleshooting, not audit).
- **Prompt logs** (Section 9.3) show the conversation; Kiro does not document that they list every tool call.

**CloudWatch Logs Insights query (sketch)** over the log group that receives the hook audit log. Adjust the `parse` expression to the record format of your audit hook:
```sql
fields @timestamp, @message
| parse @message /"tool":"(?<tool>[^"]+)"/
| filter tool like /\//
| stats count() as calls by tool
| sort calls desc
```

---

## 6. SDLC Security Controls

### 6.1 Secure Development Workflow

**Agent autonomy and permissions (Kiro IDE 1.0+ and the Kiro CLI V3 engine):**

Kiro decides each agent action in two steps. In the IDE, the autonomy setting decides whether Kiro proceeds or prompts; the permission rules then allow, prompt for, or deny the tool call. The admin rules are the enforced part; autonomy and user rules are convenience settings.

| Control | Setting | Set by |
|---------|---------|--------|
| IDE autonomy | `kiroAgent.agentAutonomy`: `Autopilot` (proceed with allowed operations; **the default unless changed**) or `Supervised` (prompt before any action) | User; pre-set `Supervised` in the default user settings of the VDI image |
| Admin permission rules | `deny` / `ask` rules in `managed-settings.json` (admin rules cannot use `allow`) | Administrator, deployed by MDM or GPO ([`managed-settings/README.md`](managed-settings/README.md)) |
| User permission rules | `allow` / `ask` / `deny` rules in `~/.kiro/settings/permissions.yaml` | User (template: [`managed-settings/permissions.banking.yaml`](managed-settings/permissions.banking.yaml)) |
| Workspace trust | Leave unknown repositories untrusted | User |

**IDE user setting:**
```json
{
  "kiroAgent.agentAutonomy": "Supervised"
}
```

**Admin rules** (abridged from [`managed-settings/managed-settings.banking.json`](managed-settings/managed-settings.banking.json), which also carries the sign-in restriction):
```json
{
  "rules": [
    { "capability": "shell", "match": ["git push *--force*", "git push -f*", "git reset *--hard*", "sudo *", "curl *", "wget *"], "effect": "deny" },
    { "capability": "shell", "match": ["git push*", "npm publish*", "cdk deploy*", "terraform apply*"], "effect": "ask" },
    { "capability": "fs_read", "match": ["**/.env", "**/.env.*", "**/*.pem", "~/.aws/credentials", "~/.ssh/**"], "effect": "deny" }
  ]
}
```

**User rules** (abridged from the user template):
```yaml
# ~/.kiro/settings/permissions.yaml
rules:
  - capability: shell
    effect: allow
    match: ["npm test*", "npm run lint*", "npx cdk synth*"]
  - capability: fs_write
    effect: allow
    match: ["src/**", "test/**", "tests/**", "docs/**"]
```

**How the rules combine:**
- **Deny wins.** `deny > ask > allow` across all scopes, with no precedence between scopes. A user, workspace, agent or session `allow` (including `kiro-cli --trust-all-tools` and `/tools trust-all`) cannot remove an admin `deny` or `ask`.
- **Headless runs** (no interactive client) treat every `ask` as `deny`, so a pipeline that runs Kiro cannot push, publish or deploy under this policy.
- **Do not auto-allow `npm install`, `npm ci`, `pip install`, `terraform init` or `terraform plan`.** They run third-party code (package lifecycle scripts, Terraform providers and `external` data sources). Leave them at the default prompt.
- **Replaced settings.** Kiro IDE 1.0 replaced Trusted Commands and the Command Denylist with these rules: trusted command prefixes become `allow` rules and denylist entries become `deny` rules (`kiroAgent.trustedCommands` and `kiroAgent.commandDenylist` are no longer used). In the CLI, convert legacy agent `toolsSettings` with `kiro-cli agent migrate` (or `/upgrade-agent`); `autoAllowReadonly` and `denyByDefault` have no equivalent and must be written as explicit rules.
- **Hardcoded invariants.** Kiro always denies agent writes to `~/.kiro/settings/` and `.kiro/settings/` (so the agent cannot edit its own permission or MCP files), and always asks before writes to `.git/**` and to the agents, hooks, workflows and powers directories under `.kiro` and `~/.kiro`.
- **Limits.** Shell globs match the command text and can be evaded (for example by quoting or indirection), and all of these rules are enforced by the client, so a local administrator can remove them. Hooks ([`agent-hooks/README.md`](agent-hooks/README.md)), the VDI controls in Part 1, Section 4 and server-side branch protection (Section 13.2) are the further layers. See [`managed-settings/README.md`](managed-settings/README.md#glob-limitations).

### 6.2 Secrets Management

**AWS Secrets Manager Integration:**
```bash
# Store secrets
aws secretsmanager create-secret \
  --name /banking/dev/db-password \
  --secret-string "$(openssl rand -base64 32)" \
  --kms-key-id arn:aws:kms:region:account:key/xxxxx
```

```python
# Retrieve in code (never hardcode)
import boto3

secret = boto3.client("secretsmanager").get_secret_value(SecretId="/banking/dev/db-password")
```

The admin policy in [`managed-settings/`](managed-settings/) denies `aws secretsmanager get-secret-value*` in the agent's shell tool; application code reads secrets at run time with its own IAM role. Because glob rules can be evaded, also keep the developer's own AWS credentials least-privilege.

**Kiro Prompt Guidance:**
```
"Use AWS Secrets Manager for credentials. Never hardcode secrets. 
Reference: secretsmanager.get_secret_value(SecretId='...')"
```

### 6.3 Code Review Gates

**Pre-commit Hook:**
```bash
#!/bin/bash
# .git/hooks/pre-commit

# Scan for secrets
if git diff --cached | grep -E '(AWS_ACCESS_KEY|password\s*=|api_key\s*=)'; then
    echo "ERROR: Potential secret detected"
    exit 1
fi

# Validate Kiro-generated code
if git diff --cached --name-only | grep -E '\.(py|js|java)$'; then
    echo "Code review required for Kiro-generated changes"
fi
```

### 6.4 Artifact Security

**S3 Bucket Policy (Code Artifacts):**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:*",
    "Resource": "arn:aws:s3:::banking-artifacts/*",
    "Condition": {
      "Bool": {"aws:SecureTransport": "false"}
    }
  }]
}
```

---

## 7. Data Protection & Encryption

### 7.1 Customer-Managed KMS Keys

**1. Create the KMS key** (symmetric; create it in the Kiro profile region, Section 7.2):
```bash
aws kms create-key \
  --region us-east-1 \
  --key-spec SYMMETRIC_DEFAULT \
  --key-usage ENCRYPT_DECRYPT \
  --description "Kiro data encryption" \
  --key-policy '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "Enable IAM policies",
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::<account-id>:root"},
      "Action": "kms:*",
      "Resource": "*"
    }]
  }'

aws kms enable-key-rotation --region us-east-1 --key-id <key-id>
```

**2. Select the key in the Kiro console:** open **Settings** > **Encryption key** and choose the customer managed key. There is no CLI command for this step.

**Caveats:**
- Only symmetric keys are supported.
- Customer managed keys are not supported for Kiro Web (Cloud Sessions), which is another reason to keep Cloud Sessions off.
- Kiro docs do not say which data and features the key covers, or whether the key must be in the profile region. Verify both with AWS before you rely on the key in your risk assessment, and record the answer.

**Least-privilege notes for the key policy:**
- The `Enable IAM policies` statement lets IAM policies in the account grant access to the key. It grants nothing by itself, but any IAM principal with a broad `kms:*` policy could then use or delete the key, so do not grant `kms:*` in IAM.
- Add separate statements for key administrators (key management without `kms:Encrypt` / `kms:Decrypt`) and for the role that configures Kiro (the KMS permissions in Kiro's example IAM policy). Kiro does not document a service principal or `kms:ViaService` value for the key policy; do not guess one.
- Allow `kms:DisableKey` and `kms:ScheduleKeyDeletion` only to a break-glass role: disabling or deleting the key makes the data encrypted with it unavailable.
- Alert on key policy changes and on key use (`kms.amazonaws.com` events in CloudTrail).

Example key-administrator statement (no use of the key, no deletion):
```json
{
  "Sid": "KeyAdministrators",
  "Effect": "Allow",
  "Principal": {"AWS": "arn:aws:iam::<account-id>:role/KmsKeyAdmin"},
  "Action": [
    "kms:Describe*", "kms:List*", "kms:Get*", "kms:Create*", "kms:Enable*",
    "kms:Put*", "kms:Update*", "kms:Revoke*", "kms:TagResource", "kms:UntagResource"
  ],
  "Resource": "*"
}
```

### 7.2 Data Location & Residency

> **⚠️ Data Location Note:** Kiro profiles exist only in **us-east-1 (N. Virginia)** and **eu-central-1 (Frankfurt)**, plus AWS GovCloud (US-East) and AWS GovCloud (US-West) for US public-sector customers. There is **no** Singapore (`ap-southeast-1`) profile option. Your content, prompt logs, and user activity reports are stored in the profile region by architectural requirement. MAS TRM Guidelines do **not** impose a data localisation mandate — data residency in Singapore is a customer preference, not a regulatory requirement.

**Clarification: Data Residency vs. Regulatory Requirement**

MAS TRM Guidelines focus on **data protection controls** (encryption, access control, audit trails) rather than prescribing where data must physically reside. Financial institutions may choose to keep data in Singapore for business, contractual, or risk-appetite reasons, but this is not a MAS-imposed localisation mandate.

**Two regions to keep apart:**
- **Workload region (`ap-southeast-1`):** the institution's own infrastructure — VPC, WorkSpaces VDI, CloudTrail, AWS Config and AWS Backup (the CDK stacks in this repo). IAM Identity Center can also be in `ap-southeast-1`, so identities and subscriptions can stay in Singapore.
- **Kiro profile region (`us-east-1` or `eu-central-1`):** where Kiro stores and processes prompts, code context and responses, and where the prompt-log bucket and the user activity report bucket must be created. Create the Kiro customer-managed KMS key here as well (Section 7.1; the region constraint for the key is not documented, so verify it).

**Regional Reality for Kiro:**
- **Profile / Service Region:** Kiro profiles are hosted in `us-east-1` or `eu-central-1` (or AWS GovCloud (US)). Content (including customizations) is stored in the profile region. There is no `ap-southeast-1` profile. The Identity Center region can differ from the profile region.
- **Logging:** Prompt log and user activity report S3 buckets **must** reside in the AWS Region where the Kiro profile was installed. Cross-account buckets are not supported. From Kiro IDE 1.2, telemetry and activity data are also sent to the profile region.
- **Inference:** Kiro is powered by Amazon Bedrock and uses cross-region inference. For Geography-scope models (including all Claude models), requests stay within the AWS Regions of the profile's geography: a US profile uses US Regions (`us-east-1`, `us-west-2`, `us-east-2`) and a Europe profile uses Europe Regions (`eu-central-1`, `eu-west-1`, `eu-west-3`, `eu-north-1`, `eu-south-1`, `eu-south-2`). There is no Asia Pacific geography, so these requests do **not** route to Singapore. Global-scope models are the exception (next bullet).
- **Inference scope (Kiro models page, updated 2026-10-08):** inference scope is set per model in the Inference endpoint regions table of the [Kiro models page](https://kiro.dev/docs/models/). Geography-scope models, which include all Claude models, use the US endpoint for `us-east-1` profiles and the EU endpoint for `eu-central-1` profiles and stay within that geography. Global-scope models (currently GPT-5.6 Sol, Terra and Luna) may be processed in supported commercial AWS Regions worldwide, including outside the endpoint geography, and use the US endpoint even for `eu-central-1` profiles. Cross-region inference does not change where Kiro stores data, and lifecycle status and inference scope are independent: Claude Opus 5.5 and Sonnet 5.5 launched with "experimental support" and have Geography scope. Kiro has no setting to disable cross-region inference. The control is model governance: manage the approved model list (Kiro console > Settings > Shared settings > Model availability) so that Global-scope models, and preview or experimental models, are not available until an administrator approves them (review preview terms such as Claude Fable 5.1's 30-day retention). See the model approval matrix in [`kiro-docs/security-governance-features.md`](kiro-docs/security-governance-features.md).
- **Cloud Sessions (Kiro Web):** run in `us-east-1` only, and customer-managed KMS keys, MCP configuration and model availability settings do not apply to them. They are off by default for IAM Identity Center organisations; keep them off unless they have been assessed.
- **Mitigation (if residency is preferred):** Use S3 Cross-Region Replication (CRR) to replicate the profile-region log bucket to `ap-southeast-1` for local access. This produces a regional **copy**; the authoritative log location remains the profile region.
- **VPC / network:** There are no Kiro VPC endpoints in `ap-southeast-1`. Kiro interface endpoints (`com.amazonaws.us-east-1.q`, `com.amazonaws.us-east-1.codewhisperer`, `com.amazonaws.eu-central-1.q`) exist only in the profile region, and sign-in and downloads use public HTTPS endpoints that must be allowlisted. See Part 1, Section 3 for the connectivity options. The network path does not change where Kiro processes or stores data.

**What this means for a Singapore institution:** identity can stay in Singapore, but prompts, code context and responses are stored and processed in the Kiro profile region and may be processed in other regions of the same geography (or worldwide for Global-scope models such as GPT-5.6). Treat Kiro use as a cross-border transfer:
- Apply the PDPA Transfer Limitation Obligation (s26) to any personal data that can reach Kiro (Section 11).
- Assess Kiro as a third-party service under MAS TRM 3.4 and the MAS outsourcing requirements (Section 12).
- Keep customer information out of prompts and code context (banks: FSM-N05 para 9 and banking secrecy); use masked or synthetic test data.
- Use model governance to exclude Global-scope models (and review preview terms such as Claude Fable 5.1's 30-day retention).

**References (verified 2026-10-08):**
- [Kiro Docs: Supported regions](https://kiro.dev/docs/enterprise/supported-regions/)
- [Kiro Docs: Data protection — storage and cross-region inference](https://kiro.dev/docs/privacy-and-security/data-protection/)
- [Kiro Docs: VPC endpoints](https://kiro.dev/docs/privacy-and-security/vpc-endpoints/)
- [Kiro Docs: Viewing per-user activity](https://kiro.dev/docs/cli/enterprise/monitor-and-track/user-activity/)
- [Amazon S3 Cross-Region Replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)

### 7.3 Opt-Out Configuration

No command or setting is needed for Kiro enterprise users (IAM Identity Center or external IdP subscriptions):

- **Service improvement:** enterprise content is not used for service improvement, and enterprise users are automatically opted out of telemetry and content collection by AWS. The administrator controls the telemetry used for user activity reports; enterprise users cannot change it.
- **Telemetry location:** from Kiro IDE 1.2, telemetry and activity data are sent to an endpoint in the profile region. If the profile region has no endpoint, the IDE drops the telemetry rather than sending it to another region.
- **Exception: model-specific retention.** Some models retain traffic for abuse detection. Claude Fable 5.1 (Preview) retains all traffic for up to 30 days, and traffic flagged by classifiers may be reviewed by humans at AWS. For GPT models, only classifier-flagged traffic is retained for 30 days. Keep such models off the approved model list unless you have assessed them (see the model approval matrix in [`kiro-docs/security-governance-features.md`](kiro-docs/security-governance-features.md)).
- **Client opt-out settings:** the IDE and CLI telemetry and content settings matter for Free Tier and individual subscribers; in a managed VDI image they are an optional second layer. See [`kiro-docs/privacy-and-security.md`](kiro-docs/privacy-and-security.md) (Opt Out of Data Sharing).
- **Code references:** keep the reference tracker on, so that suggestions that resemble open-source code are logged with their license (this supports the review of third-party and open-source code, TRM 6.1.3), or opt out of suggestions with references for all users in the Kiro console. See [`kiro-docs/privacy-and-security.md`](kiro-docs/privacy-and-security.md) (Code References).

---

## 8. Compliance & Audit

### 8.1 MAS TRM Compliance Matrix

| Control | MAS Section | Implementation | Evidence |
|---------|-------------|----------------|----------|
| Access Control | 9.1 | IAM IDC + MFA | CloudTrail logs |
| Encryption | 10.1 (TLS), 10.2 (key management) | TLS 1.2+ + KMS customer-managed keys with rotation | KMS key policy |
| Data Security | 11.1 | DLP + Encryption | DLP reports |
| Network Security | 11.2 | Private VPC + egress allowlist (PrivateLink to Kiro only in the profile region) | VPC flow logs |
| Audit Logging & Monitoring | 12.2 | Kiro prompt logging + user activity reports + CloudTrail + CloudWatch | S3 log buckets (profile region and workload region) |

TRM 15.1 (IT Audit) covers the independent audit function, which uses these logs as evidence; it is not the logging control itself. The matrix shows where controls support each TRM section. Each institution remains responsible for its own compliance assessment.

> **Upcoming: proposed TRM Notice amendments (MAS Consultation Paper P012-2026, 10 June 2026, not yet finalised).** MAS proposes requiring a comprehensive IT asset inventory that includes open-source and third-party components (with direct and indirect dependencies), IT risk assessments that cover the IT supply chain and the use of AI, change-management controls that prevent unauthorised changes and test all changes to critical systems, and immutable or offline backups. For AI coding assistants, this means recording Kiro, its MCP servers and the dependencies it introduces in the asset inventory, and routing Kiro-generated changes through the normal change-management controls. ([consultation paper](https://www.mas.gov.sg/publications/consultations/2026/consultation-paper-on-proposed-amendments-to-notices-on-technology-risk-management))

### 8.2 Audit Trail Requirements

**Audit sources for Kiro:**

| Source | What it records | Where | Notes |
|--------|-----------------|-------|-------|
| **Kiro prompt logging** (Section 9.3) | Prompts and responses in the IDE and CLI (chat and inline suggestions), with user ID, timestamps and conversation IDs | S3 bucket in the profile region | Primary record of AI-assisted activity |
| **User activity reports** | Daily per-user CSV, one per client type (generated at 02:00 UTC) | S3 in the profile region (`.../AWSLogs/<account>/KiroLogs/user_report/<region>/yyyy/mm/dd/00/`) | Same region and account as the profile; a prefix is required |
| **CloudTrail** | AWS API calls in the account: IAM Identity Center, KMS, S3, IAM and console changes | Trail bucket (workload account) | Kiro docs say only that CloudTrail "captures API calls"; Kiro event sources are not documented |
| **OpenTelemetry usage export** | Daily `kiro.daily.*` usage metrics | Your OTLP collector | Usage metrics only, not an audit trail |
| **Local hook audit log** | Each tool call on the device, including MCP tools (Section 5.3) | Device, shipped to the SIEM | Supplementary: user-writable unless the OS makes it append-only; not tamper-proof |

**CloudTrail Configuration:**
```bash
# Management events. Kiro does not document CloudTrail data events, so do not
# configure data resources for Kiro.
aws cloudtrail put-event-selectors \
  --trail-name kiro-audit \
  --event-selectors '[{
    "ReadWriteType": "All",
    "IncludeManagementEvents": true
  }]'

# Enable log file validation
aws cloudtrail update-trail \
  --name kiro-audit \
  --enable-log-file-validation
```

- The trail must also cover the Kiro profile region (a multi-region or organization trail; the Monitoring stack in [`cdk/`](cdk/) creates a multi-region trail).
- **Verify the event sources in your own account** before you build detections: open CloudTrail Event history in the profile region after some Kiro use and look for events from `codewhisperer.amazonaws.com` or `q.amazonaws.com` (candidates; not documented for Kiro).
- MCP tools run on the client, so MCP tool calls do not create CloudTrail events (Section 5.3).

**S3 Lifecycle Policy (example institutional policy, not prescribed by MAS TRM: move to Glacier after 90 days, expire after ~7 years; set the expiry per your record-keeping obligations, commonly 5–7 years):**
```json
{
  "Rules": [{
    "Id": "ArchiveAuditLogs",
    "Status": "Enabled",
    "Transitions": [{
      "Days": 30,
      "StorageClass": "STANDARD_IA"
    }, {
      "Days": 90,
      "StorageClass": "GLACIER"
    }],
    "Expiration": {"Days": 2555}
  }]
}
```

### 8.3 Compliance Reporting

**Monthly Compliance Report Script (sketch):** summarizes Kiro-related CloudTrail management events. Verify the event source names in your account first (Section 8.2). `LookupEvents` returns management events of the last 90 days in one region only, so query the Kiro profile region; for longer periods or larger volumes, query the trail bucket with Athena or use CloudTrail Lake. Per-user Kiro usage comes from the user activity reports, and sign-in failures from IAM Identity Center (in its own region) or your IdP, not from this query.

```python
"""Sketch: monthly summary of Kiro-related CloudTrail management events."""
import json
from collections import Counter
from datetime import datetime, timedelta, timezone

import boto3

PROFILE_REGION = "us-east-1"                      # Kiro profile region
EVENT_SOURCES = ["codewhisperer.amazonaws.com"]   # candidate; verify in your account


def generate_compliance_report(days=30):
    cloudtrail = boto3.client("cloudtrail", region_name=PROFILE_REGION)
    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(days=days)
    paginator = cloudtrail.get_paginator("lookup_events")

    total = 0
    principals = set()
    event_names = Counter()
    error_codes = Counter()
    for source in EVENT_SOURCES:
        pages = paginator.paginate(
            LookupAttributes=[{"AttributeKey": "EventSource", "AttributeValue": source}],
            StartTime=start_time,
            EndTime=end_time,
        )
        for page in pages:
            for event in page.get("Events", []):
                total += 1
                principals.add(event.get("Username", "unknown"))
                event_names[event.get("EventName", "unknown")] += 1
                # Error details are inside the CloudTrailEvent JSON, not at the top level
                detail = json.loads(event.get("CloudTrailEvent") or "{}")
                if detail.get("errorCode"):
                    error_codes[detail["errorCode"]] += 1

    return {
        "period": f"{start_time.date()} to {end_time.date()}",
        "region": PROFILE_REGION,
        "event_sources": EVENT_SOURCES,
        "total_events": total,
        "unique_principals": len(principals),
        "top_event_names": event_names.most_common(10),
        "errors_by_code": dict(error_codes),
    }
```

---

## 9. Operational Best Practices

### 9.1 Developer Onboarding

**Day 1 Checklist:**
1. ✅ IAM IDC account provisioned
2. ✅ MFA device registered
3. ✅ WorkSpaces assigned
4. ✅ Security training completed
5. ✅ Kiro access tested

**Training Topics:**
- Agent autonomy (Supervised vs Autopilot), permission prompts and why admin rules cannot be overridden
- Workspace trust: when to trust a repository and when to leave it untrusted
- MCP registry and approved MCP servers
- Secrets management
- Code review requirements
- DLP policies

### 9.2 Kiro Usage Guidelines

Set the posture per repository; the mechanisms are described in Section 6.1.

| Repository | Autonomy (`kiroAgent.agentAutonomy`) | Permissions |
|------------|--------------------------------------|-------------|
| Sandbox or prototype with synthetic data | `Autopilot` acceptable | Admin baseline + user template |
| Code that reaches production pipelines | `Supervised` | Admin baseline; no user `allow` rules for shell commands beyond test, lint and build |
| Third-party code, forks, downloaded samples | Leave the workspace untrusted | Admin baseline; Kiro asks before every shell command and MCP tool call |

**Minimal allow list (user scope):** keep `allow` rules to local, read-only or test commands, for example `git status`, `git diff`, `git log` (already allowed by default), `npm test`, linters and `cdk synth`. Do not add `npm install` or `terraform plan`: they execute third-party code. Never add `capability: all`, or a `shell` or `fs_read` rule without a `match` list. The template is [`managed-settings/permissions.banking.yaml`](managed-settings/permissions.banking.yaml).

### 9.3 Prompt Logging

**Enable prompt logging (Kiro console):** open **Settings** > **Kiro Settings** > **Logging**, turn on **Log Kiro prompts with metadata**, and enter the S3 location, for example `s3://kiro-prompts-<account-id>-<profile-region>/kiro-prompt-logs/`. There is no CLI command for this step.

- **Bucket location:** the bucket must be in the Kiro profile region (where the profile was installed when users were first subscribed; Section 7.2) and in the account where users are subscribed. Cross-account buckets are not supported.
- **Content:** user prompts and Kiro responses from the IDE and the CLI. Inline suggestions are logged with their context, file name, accepted completions, user ID and timestamp; chat with the prompt, response, conversation ID, code references, web links, user ID and timestamp.
- **User activity reports:** turn them on as well (daily CSV per client type to the same region and account; a prefix is required). See [Kiro Docs: Viewing per-user activity](https://kiro.dev/docs/cli/enterprise/monitor-and-track/user-activity/).

**S3 Bucket Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "KiroLogsWrite",
      "Effect": "Allow",
      "Principal": {"Service": "q.amazonaws.com"},
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::<bucket>/<prefix>/*",
      "Condition": {
        "StringEquals": {"aws:SourceAccount": "<account-id>"},
        "ArnLike": {"aws:SourceArn": "arn:aws:codewhisperer:<profile-region>:<account-id>:*"}
      }
    },
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": ["arn:aws:s3:::<bucket>", "arn:aws:s3:::<bucket>/*"],
      "Condition": {"Bool": {"aws:SecureTransport": "false"}}
    }
  ]
}
```

- The service principal is `q.amazonaws.com` and the source ARN uses the `codewhisperer` service prefix, as in the Kiro docs.
- Use default bucket encryption instead of a policy condition that requires an encryption header: the documented policy has no such condition, and a condition that the log delivery does not meet blocks delivery. Kiro docs mention optional KMS encryption of the bucket but do not document the key permissions that delivery needs; if you use SSE-KMS with a customer managed key, test delivery after you enable it.
- Turn on S3 Block Public Access and Versioning, and S3 Object Lock if your record-keeping policy requires immutable logs. Replicate to `ap-southeast-1` with Cross-Region Replication if you want a regional copy (Section 7.2).
- Source: [Kiro Docs: Prompt logging](https://kiro.dev/docs/enterprise/monitor-and-track/prompt-logging/) (verified 2026-10-08).

### 9.4 Performance Optimization

**Context Window Management:**
- Limit file context to relevant code only
- Use `.kiro/steering` for project-specific guidance
- Avoid uploading large binary files

**Steering File Example:** steering files are Markdown files in `.kiro/steering/` (workspace) or `~/.kiro/steering/` (global). Optional frontmatter must be at the very top of the file; `inclusion: always` is the default. The real file is [`.kiro/steering/banking-standards.md`](.kiro/steering/banking-standards.md), which declares `inclusion: always` explicitly.

```markdown
---
inclusion: always
---
# Banking Development Standards

## Security Requirements
- Follow the MAS Technology Risk Management Guidelines
- Use AWS Secrets Manager for credentials
- All database queries must use parameterized statements
- Log all financial transactions

## Prohibited Patterns
- Never hardcode credentials
- No direct database connections from frontend code
- No unencrypted data transmission
```

Steering is guidance for the agent, not an enforced control.

---

## 10. Incident Response

### 10.1 Security Incident Procedures

**Incident Classification:**

| Severity | Example | Response Time |
|----------|---------|---------------|
| **Critical** | Credential exposure | Immediate (15 min) |
| **High** | Unauthorized MCP server | 1 hour |
| **Medium** | DLP policy violation | 4 hours |
| **Low** | Failed authentication | 24 hours |

These response times are example internal SLAs (institutional policy). Regulatory notification deadlines are separate; see Section 10.3.

### 10.2 MCP Server Compromise Response

**Immediate Actions:**
1. Remove the server from the MCP registry. Clients terminate removed servers when they next fetch the registry (at startup and every 24 hours), so also ask users to restart Kiro. If you need more, turn MCP off in the Kiro console (Settings > Shared settings), or push an admin `mcp` deny rule for the server (`"match": ["<server>/*"]`) through MDM; managed-settings changes apply when Kiro restarts.
2. Revoke the API tokens and credentials the server used.
3. Review the hook audit log (Section 5.3), the prompt logs of the affected users, the server's own logs (for remote servers) and CloudTrail activity of any AWS credentials the server held.
4. Isolate affected WorkSpaces.

**Investigation Script:**
```bash
# MCP tool calls do not appear in CloudTrail (they run on the client). Search the
# hook audit log in the SIEM (Section 5.3) and the prompt logs for the time window.

# AWS API calls made with credentials the MCP server could use (last 24 hours).
# GNU date shown; on macOS use: date -u -v-24H +%Y-%m-%dT%H:%M:%SZ
aws cloudtrail lookup-events \
  --region <region> \
  --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=<access-key-id> \
  --start-time "$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --query 'Events[*].[EventTime,EventSource,EventName,Username]' \
  --output json > mcp-investigation-cloudtrail.json
```

### 10.3 Data Breach Protocol

**Containment:**
1. **Kiro access:** remove the user's Kiro subscription in the Kiro console (or remove the user from the group that holds the subscription), disable the user in the IdP (SCIM propagates the change), and revoke the user's active sessions in IAM Identity Center. Option B: disable the user in the external IdP.
2. **AWS account access:** remove the user's permission-set assignments. This does not affect the Kiro subscription.
3. **Secrets:** rotate the secrets the user or the affected workload could reach.

```bash
# Remove AWS account access (permission set assignment) for the user
aws sso-admin delete-account-assignment \
  --instance-arn <instance-arn> \
  --target-id <account-id> \
  --target-type AWS_ACCOUNT \
  --permission-set-arn <permission-set-arn> \
  --principal-type USER \
  --principal-id <user-id>

# Rotate every secret whose name starts with /banking/. rotate-secret takes one
# secret ID per call and does not accept wildcards. Secrets without rotation
# configured must be changed at the source and updated with put-secret-value.
aws secretsmanager list-secrets \
  --filters Key=name,Values=/banking/ \
  --query 'SecretList[].ARN' --output text | tr '\t' '\n' |
while read -r arn; do
  aws secretsmanager rotate-secret --secret-id "$arn"
done
```

**Notification:**
- Security team: Immediate
- Compliance team: Immediately, in parallel with the security team, so that a relevant-incident decision can be made inside the MAS 1-hour window
- MAS (banks, [MAS Notice FSM-N05](https://www.mas.gov.sg/regulation/notices/notice-fsm-n05) para 7): as soon as possible, and **not later than 1 hour** after discovery of a relevant incident
- MAS root cause and impact analysis report (FSM-N05 para 8): within **14 days** of discovery of the relevant incident, or a longer period if MAS allows
- PDPC: if personal data is involved, run the PDPA breach assessment in Section 11.4 (separate clock)

A **relevant incident** under FSM-N05 is a system malfunction or IT security incident that has a severe and widespread impact on the bank's operations or materially impacts the bank's service to its customers. Most Kiro-specific events (for example a DLP violation) will not meet this threshold, but a credential exposure or a compromised pipeline that affects critical systems or customer services could.

> **Other FIs:** FSM-N05 applies to banks. Merchant banks and non-bank FIs follow their own sector TRM notice (for example FSM-N11 for merchant banks, FSM-N03 for insurers, FSM-N13 for designated payment systems and digital payment token service providers, FSM-N21 for capital markets FIs, FSM-N23 for licensed financial advisers). Verify the wording of your sector notice. The former sector notices (such as Notice 644) were cancelled with effect from 10 May 2024. The MAS Circular on FI incident reporting (effective 1 February 2026) changes the reporting template and channel, not the deadlines.

### 10.4 Escalation Matrix

```
Level 1: Developer → Team Lead (15 min)
Level 2: Team Lead → Security Team (30 min)
Level 3: Security Team → CISO (1 hour)
Level 4: CISO → MAS (relevant incident: as soon as possible, ≤1 hour from discovery; RCA report ≤14 days)
```

The MAS 1-hour clock runs from discovery, not from CISO escalation. If an incident may be a relevant incident, escalate Levels 1–4 in parallel rather than one after another.

### 10.5 Availability and Recovery (MAS Notice FSM-N05 paras 5–6)

Consider whether Kiro is part of a critical system. Usually it is not, but the CI/CD pipeline and repositories it writes to may be. For each critical system, banks must meet:

- **Availability (para 5):** maximum unscheduled downtime of 4 hours in any 12-month period.
- **Recovery (para 6):** recovery time objective (RTO) of no more than 4 hours, validated at least once every 12 months.

---

## Appendix A: Quick Reference Commands

### IAM IDC
```bash
# List users
aws identitystore list-users --identity-store-id d-xxxxx

# Grant AWS account access (permission set assignment).
# This does NOT assign a Kiro subscription.
aws sso-admin create-account-assignment \
  --instance-arn <arn> --target-id <account> --target-type AWS_ACCOUNT \
  --permission-set-arn <arn> --principal-type USER --principal-id <id>
```

Kiro subscriptions are assigned to IAM Identity Center users or groups in the Kiro console, not with `create-account-assignment`. Account assignments only grant access to AWS accounts (for example for WorkSpaces administration).

### VPC Endpoints
```bash
# Create a Kiro endpoint in a VPC in the Kiro profile region (Part 1, Section 3.4)
aws ec2 create-vpc-endpoint \
  --region us-east-1 \
  --vpc-id vpc-xxxxx \
  --service-name com.amazonaws.us-east-1.q \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-xxxxx \
  --security-group-ids sg-xxxxx
```

### CloudTrail
```bash
# Query Kiro-related events in the profile region. Kiro does not document its
# event sources: verify them in Event history first (candidates:
# codewhisperer.amazonaws.com, q.amazonaws.com).
aws cloudtrail lookup-events \
  --region us-east-1 \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=codewhisperer.amazonaws.com \
  --max-results 50
```

### Kiro Managed Settings
```bash
# Official paths (restart Kiro after a change)
#   macOS:   /Library/Application Support/Kiro/managed-settings.json
#   Linux:   /etc/kiro/managed-settings.json
#   Windows: C:\ProgramData\Kiro\managed-settings.json (UTF-8 without BOM)

# Validate before rollout: valid JSON, and admin rules use only deny or ask
jq -e '[.rules[].effect] | all(. == "deny" or . == "ask")' managed-settings.json
```

```powershell
# Windows: the first byte must be 123 ('{'); 239 means a UTF-8 BOM, 255 or 254 means UTF-16
[System.IO.File]::ReadAllBytes('C:\ProgramData\Kiro\managed-settings.json')[0]
```

More checks: [`managed-settings/README.md`](managed-settings/README.md#validation).

### WorkSpaces
```bash
# List WorkSpaces
aws workspaces describe-workspaces

# Reboot WorkSpace
aws workspaces reboot-workspaces --reboot-workspace-requests WorkspaceId=ws-xxxxx
```

---

## Appendix B: Compliance Checklist

### Pre-Production Checklist

- [ ] IAM IDC integrated with Enterprise IdP
- [ ] MFA enabled for all users
- [ ] Sign-in restricted with `managed-settings.json` (Part 1, Section 2.2.1); social sign-in host denied on the egress allowlist
- [ ] `managed-settings.json` deployed to the official path on every device, read-only for users, validated (no BOM, no `allow` rules)
- [ ] Minimum client versions enforced (Kiro IDE 1.2+, Kiro CLI 2.25.0+ with V3 sessions)
- [ ] VPC endpoints created and tested
- [ ] WorkSpaces deployed with encryption
- [ ] DLP agents installed and configured
- [ ] MCP governance on, MCP Registry URL set, registry entries pinned to exact versions
- [ ] Model allow list managed; experimental and preview models excluded unless assessed
- [ ] Web tools, API key generation and Cloud Sessions off (or assessed and documented)
- [ ] CloudTrail logging enabled (covering the Kiro profile region)
- [ ] KMS customer-managed keys configured
- [ ] Prompt logging and user activity reports enabled, delivered to the SIEM
- [ ] Hooks installed (`agent-hooks/README.md`) as defense in depth
- [ ] Security training completed
- [ ] Incident response plan documented
- [ ] Compliance report template created

### Monthly Audit Checklist

- [ ] Review CloudTrail logs for anomalies
- [ ] Review MCP registry changes against change records; check that clients are not reporting "MCP disabled"
- [ ] Review new Kiro model launches and the approved model list (new models stay unavailable until added)
- [ ] Check MDM compliance reports for devices with a missing or changed `managed-settings.json`
- [ ] Check DLP policy violations
- [ ] Review failed authentication attempts
- [ ] Verify encryption key rotation
- [ ] Test incident response procedures
- [ ] Update security documentation
- [ ] Generate compliance report for management

---

## Appendix C: Troubleshooting

### Issue: Cannot connect to Kiro from WorkSpaces

**Check:**
1. VPC endpoint status: `aws ec2 describe-vpc-endpoints`
2. Security group rules allow port 443
3. Private DNS enabled on endpoint
4. DNS resolution: `nslookup q.us-east-1.amazonaws.com`

### Issue: MCP server not loading

**Check:**
1. MCP governance: MCP is on and the client can reach the governance API. The `/mcp` panel shows "Failed to retrieve MCP settings — MCP disabled" when it cannot; check the egress allowlist.
2. Registry: the server name in `mcp.json` matches a registry entry (unlisted servers are hidden; the IDE shows "N servers hidden"), and the registry is served over HTTPS with a trusted certificate.
3. Configuration files: `~/.kiro/settings/mcp.json` (user) and `.kiro/settings/mcp.json` (workspace). A workspace file is not loaded while the workspace is untrusted.
4. Runner and package source: `uvx`, `npx` or `docker` installed, and PyPI, npm or the internal mirror reachable.
5. MCP logs: Kiro panel → Output → "Kiro - MCP Logs"
6. Network connectivity to the MCP server endpoint (remote servers)

### Issue: All agent tool calls are denied, or a managed-settings warning appears

**Check:**
1. `managed-settings.json` is valid JSON, uses only `deny` / `ask` effects and only documented fields; an invalid file makes Kiro deny all tool calls until it is fixed.
2. Windows: the file is UTF-8 without BOM (Appendix A).
3. Restart Kiro after every change to the file.

### Issue: DLP blocking legitimate operations

**Resolution:**
1. Review DLP policy exceptions
2. Add file path to whitelist
3. Document business justification
4. Update DLP policy via GPO

---

## 11. Personal Data Protection Act (PDPA) Compliance

### 11.1 PDPA Overview for Kiro Usage

**Applicability:** The Personal Data Protection Act 2012 (PDPA) governs the collection, use, disclosure, and care of personal data in Singapore. When developers use Kiro to write, review, or debug code that handles personal data, PDPA obligations apply.

**Key PDPA Obligations Relevant to Kiro:**

| PDPA Obligation | Kiro Context | Implementation |
|-----------------|--------------|----------------|
| **Accountability** | The organisation is responsible for personal data in its possession or under its control, including data that Kiro/AWS processes on its behalf | Designated DPO; data protection policies that cover AI-assisted development |
| **Consent** | Code processing personal data must have valid consent basis | Kiro prompts should reference consent requirements |
| **Purpose Limitation** | Personal data used only for stated purposes | DLP policies block unauthorized data access |
| **Notification** | Individuals informed of data collection purposes | Audit logs track what data Kiro accesses |
| **Access & Correction** | Individuals can request access to their data | Data handling code must support DSAR workflows |
| **Accuracy** | Reasonable effort to ensure data is accurate | Validation logic in Kiro-generated code |
| **Protection** | Reasonable security to protect personal data | Encryption, DLP, VPC isolation |
| **Retention Limitation** | Data not kept longer than necessary | Kiro prompt logs subject to retention policy |
| **Transfer Limitation** | Cross-border transfer restrictions; Kiro stores and processes prompts and code context in its profile region (`us-east-1` or `eu-central-1`), not Singapore (Section 7.2) | Keep personal data out of prompts; s26 safeguards for any personal data that reaches Kiro (see below) |
| **Data Breach Notification** | Assess expeditiously whether a breach is notifiable; notify PDPC no later than 3 calendar days after determining it is notifiable (see 11.4) | Incident response plan must include PDPC notification |

- **Transfer Limitation Obligation (PDPA s26):** if personal data is transferred outside Singapore (for example, personal data in prompts or code context that Kiro processes in another region; see Section 7.2), the organisation must ensure the recipient protects it to a standard comparable to the PDPA. Under the PDP Regulations 2021 this is done through legally enforceable obligations (such as contract clauses that specify the destination countries, or binding corporate rules), specified certifications (APEC/Global CBPR, or PRP for data intermediaries), or one of the deemed-compliance cases. The organisation remains responsible when its data intermediary or cloud provider transfers the data overseas (PDPC Advisory Guidelines on Key Concepts, ch. 19).

### 11.2 PDPA Controls for Kiro Environments

**Data Classification for Kiro Context:**

```json
{
  "dataClassification": {
    "prohibited_in_prompts": [
      "NRIC numbers",
      "Credit card numbers (full)",
      "Bank account numbers (full)",
      "Medical records",
      "Passwords or authentication credentials"
    ],
    "restricted_in_prompts": [
      "Customer names (use pseudonyms)",
      "Email addresses (use examples)",
      "Phone numbers (use masked format)",
      "Transaction amounts (use sample data)"
    ],
    "permitted_in_prompts": [
      "Code patterns and logic",
      "Architecture descriptions",
      "Error messages (sanitized)",
      "Configuration templates"
    ]
  }
}
```

This block and the DLP rules below are illustrative policy definitions for your data classification standard and your DLP product. They are not Kiro configuration files: Kiro does not read them.

**DLP Policy Enhancement for PDPA:**

> The patterns below are vendor-neutral examples. The maintained, tested catalogue (NRIC/FIN incl. M-series, cards with separators and the Mastercard 2-series, Luhn and checksum notes) is [`.kiro/skills/pii-detection/references/singapore-pii-patterns.md`](.kiro/skills/pii-detection/references/singapore-pii-patterns.md).

```json
{
  "pdpa_dlp_rules": [
    {
      "name": "Block NRIC in Kiro Prompts",
      "pattern": "\\b[STFGM]\\d{7}[A-Z]\\b",
      "action": "block_and_alert",
      "notification": "PDPA violation: NRIC detected in AI prompt"
    },
    {
      "name": "Block Credit Card in Kiro Prompts",
      "pattern": "\\b(?:4\\d{3}(?:[ -]?\\d{4}){2}[ -]?\\d{1,7}|(?:5[1-5]\\d{2}|2(?:2(?:2[1-9]|[3-9]\\d)|[3-6]\\d{2}|7(?:[01]\\d|20)))(?:[ -]?\\d{4}){3}|3[47]\\d{2}[ -]?\\d{6}[ -]?\\d{5})\\b",
      "action": "block_and_alert",
      "notification": "PDPA violation: Credit card number detected"
    },
    {
      "name": "Warn on Email in Prompts",
      "pattern": "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",
      "action": "warn_and_log",
      "notification": "PDPA advisory: Email address in AI prompt"
    }
  ]
}
```

> **NRIC used for authentication:** in a joint advisory (PDPC press release, 2 February 2026), PDPC and CSA advised that organisations cease using NRIC numbers for authentication by **31 December 2026**. Code reviews of Kiro-generated code should flag any use of an NRIC number as a password, default password or other authenticator. The PDPC Advisory Guidelines on NRIC and other national identification numbers (31 August 2018) continue to apply to collection, use and disclosure.

### 11.3 PDPA Compliance Checklist for Kiro

- [ ] Data classification policy defined for AI-assisted development
- [ ] DLP rules enforce PDPA data categories in Kiro prompts
- [ ] Developer training covers PDPA obligations when using AI tools
- [ ] Prompt logging enabled with a documented, purpose-based retention period (PDPA s25 sets no fixed maximum; keep logs only as long as needed for legal or business purposes)
- [ ] Data location documented: workload data in `ap-southeast-1` (if required by policy); Kiro content, prompt logs and user activity reports in the Kiro profile region (`us-east-1` or `eu-central-1`), with possible processing in other regions of the same geography (Section 7.2)
- [ ] Approved model list managed so that Global-scope models (inference in AWS Regions worldwide) are excluded unless assessed, and preview terms such as Claude Fable 5.1's 30-day retention are reviewed; Kiro has no setting to disable cross-region inference
- [ ] Transfer limitation (s26) safeguards documented for any personal data processed outside Singapore
- [ ] Data breach notification process includes PDPC (assessment generally within 30 days; notify PDPC ≤3 calendar days after determining the breach is notifiable)
- [ ] Code review flags NRIC numbers used for authentication (cease by 31 December 2026)
- [ ] Privacy impact assessment completed for Kiro deployment
- [ ] Data intermediary obligations assessed (Kiro/AWS as data intermediary)

### 11.4 PDPA Breach Notification

**Timeline (PDPA Part 6A, introduced by the PDPA Amendment 2020; PDPC Advisory Guidelines on Key Concepts, ch. 20):**

```
Data breach discovered
  └─ Assess expeditiously whether the breach is notifiable
     (PDPC guidance: generally within 30 calendar days)
     └─ Notifiable if EITHER test is met:
        (a) significant harm: prescribed classes of personal data in the
            PDP (Notification of Data Breaches) Regulations 2021, or
        (b) significant scale: 500 or more affected individuals
        └─ Notify PDPC as soon as practicable, no later than
           3 calendar days after determining the breach is notifiable
        └─ Notify affected individuals as soon as practicable, at the same
           time as or after notifying PDPC (where significant harm is likely)
```

**Integration with Incident Response (Section 10):**
- Severity "Critical" and "High" incidents must trigger PDPA breach assessment
- Security team must assess PDPA notification requirements alongside MAS reporting (the MAS 1-hour and PDPC 3-day clocks run independently)

---

## 12. MAS Outsourcing and Third-Party Services

### 12.1 Kiro as an Outsourced Service

**Context:** AWS Kiro is an AWS-managed AI development service. Each financial institution must assess whether using it is an outsourcing arrangement and, if so, whether it is material, under the current MAS outsourcing regime (effective 11 December 2024):

- **Banks:** [MAS Notice 658](https://www.mas.gov.sg/regulation/notices/notice-658) (Management of Outsourced Relevant Services for Banks) and the [Guidelines on Outsourcing (Banks)](https://www.mas.gov.sg/regulation/guidelines/guidelines-on-outsourcing-banks) (Annex 2 covers cloud computing). Merchant banks: Notice 1121.
- **Other FIs:** [Guidelines on Outsourcing (Financial Institutions other than Banks)](https://www.mas.gov.sg/regulation/guidelines/guidelines-on-outsourcing-financial-institutions-other-than-banks) (last revised 24 January 2025; Annex 5 covers cloud computing).
- The previous Guidelines on Outsourcing (July 2016, revised October 2018) are cancelled; they applied only until 10 December 2024. Do not rely on their section numbers.

**Third-party services (MAS TRM 3.4):** TRM 3.4 (Management of Third Party Services) applies whether or not Kiro is an outsourcing arrangement. TRM 3.4.1 recognises that not every third-party service constitutes outsourcing, so perform and document a materiality assessment instead of assuming either outcome. The same applies to MCP servers and to the model providers behind Kiro.

**Outsourcing Classification:**

| Factor | Assessment |
|--------|------------|
| **Service Provider** | Amazon Web Services (AWS) |
| **Service** | AI-assisted software development (Kiro IDE/CLI) |
| **Materiality** | Assess based on: impact on business operations, data sensitivity, customer impact |
| **Data Involved** | Source code, development prompts, configuration data |
| **Jurisdiction** | Kiro profile region `us-east-1` or `eu-central-1` (no Singapore option); inference may use other regions of the same geography, and Global-scope models (currently GPT-5.6) may be processed in AWS Regions worldwide; IAM Identity Center can stay in `ap-southeast-1`. Treat as offshore processing and a cross-border transfer (Sections 7.2 and 11) |

### 12.2 MAS Outsourcing Requirements Mapping

| MAS Outsourcing Requirement | Kiro Implementation | Evidence |
|-----------------------------|---------------------|----------|
| **Materiality & Risk Assessment** | Materiality assessment plus technology risk assessment of Kiro deployment | Risk register entry |
| **Third-Party Services (TRM 3.4)** | Third-party risk management for Kiro, MCP servers and model providers, even where not outsourcing | Third-party register entry |
| **Due Diligence** | Review AWS assurance reports and confirm which ones cover Kiro (see 12.3) | AWS Artifact reports |
| **Contractual Protections** | AWS Enterprise Agreement / Addendum | Legal review |
| **Data Protection** | Encryption (customer-managed KMS key in the profile region), DLP, VPC isolation of the workload region, model allow list, documented data location (Section 7.2) | Technical controls documented |
| **Business Continuity** | Fallback to non-AI development if Kiro unavailable | BCP documentation |
| **Audit and Access Rights** | Contractual audit and access rights for the FI and MAS; AWS compliance reports via AWS Artifact | Quarterly review |
| **Concentration Risk** | Assess dependency on single AI coding tool | Risk assessment |
| **Sub-outsourcing** | AWS use of Amazon Bedrock foundation models | Sub-contractor review |
| **Exit Strategy** | Ability to operate SDLC without Kiro | Documented procedures |
| **MAS Notification** | Notify MAS if arrangement is material outsourcing | Regulatory filing |

### 12.3 Due Diligence Checklist

> **Scope check:** Kiro's own [compliance validation page](https://kiro.dev/docs/privacy-and-security/compliance-validation/) lists only HIPAA eligibility and inclusion in AWS's ISO/IEC 27001:2022 scope. Do not assume AWS SOC 2 / MTCS L3 reports cover Kiro; check AWS Artifact and the AWS services-in-scope pages.

- [ ] Materiality assessment documented (outsourcing or other third-party service; TRM 3.4.1)
- [ ] AWS SOC 2 Type II report reviewed (via AWS Artifact) and Kiro scope checked
- [ ] AWS ISO/IEC 27001 certificate reviewed and Kiro scope checked
- [ ] AWS CSA STAR scope checked for Kiro
- [ ] AWS MTCS (Multi-Tier Cloud Security) Level 3 scope checked for Kiro (do not assume coverage)
- [ ] Data processing agreement (DPA) in place with AWS
- [ ] Sub-processor list reviewed (Bedrock model providers)
- [ ] Service Level Agreement (SLA) reviewed for Kiro availability
- [ ] Right to audit clause confirmed in enterprise agreement
- [ ] Exit/transition plan documented

### 12.4 Concentration Risk & Exit Strategy

**Concentration Risk Mitigation:**
- Developers maintain proficiency in non-AI development workflows
- Critical code reviews performed without AI assistance as validation
- No single-point dependency on Kiro for production deployments

**Exit Strategy:**
```
If Kiro service discontinued or contract terminated:
1. Export all locally-stored configurations and MCP settings
2. Preserve prompt logs for audit trail continuity
3. Transition to standard IDE without AI assistance
4. Retrain developers on manual code review processes
5. Update SDLC procedures to remove Kiro-specific steps
6. Notify MAS if material outsourcing arrangement changes
```

---

## 13. AI/ML Governance: MAS FEAT Principles and AI Risk Management Guidelines

### 13.1 FEAT Framework for AI-Assisted Development

The Monetary Authority of Singapore published the **Principles to Promote Fairness, Ethics, Accountability and Transparency (FEAT) in the Use of Artificial Intelligence and Data Analytics in Singapore's Financial Sector** (12 November 2018; para 1.4 revised 7 February 2019). FEAT applies to AI and data analytics (AIDA) used in decision-making in the provision of financial products and services. It is not a direct requirement for coding assistants. This guide applies the FEAT principles **by analogy** to AI-assisted development with Kiro, and more directly to code that Kiro helps build for customer-facing decision systems (for example credit scoring or pricing). FEAT is non-prescriptive, so calibrate these controls to materiality. For MAS's supervisory expectations on AI risk management, which cover all forms of AI including generative AI and AI agents, see Section 13.5.

| FEAT Principle | Application to Kiro | Controls |
|----------------|---------------------|----------|
| **Fairness** | AI-generated code should not introduce discriminatory logic | Code review gates for bias detection |
| **Ethics** | AI tool usage should align with ethical standards | Developer training + usage guidelines |
| **Accountability** | Clear accountability for AI-generated code quality | Human review required before merge |
| **Transparency** | AI involvement in code generation must be traceable | Prompt logging + code annotation |

### 13.2 Accountability Controls

**Principle:** A human developer is always accountable for code quality, regardless of whether it was AI-generated.

**Implementation:** Kiro has no setting that enforces human review before merge. Enforce it where the merge happens, in source control, and use Kiro permissions so that the agent cannot push without a person approving the command.

1. **Branch protection or rulesets** on the default and release branches (server-side, so they hold even if a client-side control is bypassed):
   - require a pull request before merging, with at least two approvals (example institutional policy) and approval from code owners;
   - dismiss stale approvals when new commits are pushed;
   - require status checks to pass (tests, SAST, secret scanning);
   - block force pushes and branch deletion, and apply the rules to administrators too.
2. **CODEOWNERS** routes changes to accountable reviewers:
   ```
   # .github/CODEOWNERS (example)
   *                       @example-bank/app-reviewers
   /src/**/credit/         @example-bank/credit-risk-reviewers
   /.github/workflows/     @example-bank/platform-security
   /cdk/                   @example-bank/cloud-platform
   ```
3. **Kiro permissions:** the admin policy in [`managed-settings/`](managed-settings/) asks before `git push*` and denies force pushes and history rewrites, and it asks before the agent writes CI pipeline files or `CODEOWNERS`. In headless runs the `ask` becomes a `deny`.

**Code Attribution:**
- All Kiro-generated code must pass through standard code review
- Pull requests should indicate AI-assisted sections (recommended, not mandatory), for example with an `Assisted-by: Kiro` commit trailer
- Traceability comes from the pull request record and the Kiro prompt logs (Section 9.3). CloudTrail records AWS API calls, not the content of AI-assisted changes.

### 13.3 Transparency & Auditability

**Prompt Logging for Audit:** enable it in the Kiro console (Settings > Kiro Settings > Logging > **Log Kiro prompts with metadata**) with the bucket policy in Section 9.3. The S3 bucket must be in the Kiro profile region (`us-east-1` or `eu-central-1`) and in the subscribing account, not in the `ap-southeast-1` workload region (Section 7.2).

**What is Logged:**
- Prompts sent to Kiro and Kiro's responses, in the IDE and the CLI (chat and inline suggestions)
- User ID, timestamps, conversation IDs, code references and web links
- MCP tool calls are not documented as part of prompt logs; record them with a `PostToolUse` hook (Section 5.3)
- Daily per-user activity comes from the user activity reports (Section 8.2)

**Audit Trail Retention:** Example institutional policy (not prescribed by MAS TRM): set the retention period per your record-keeping obligations (commonly 5–7 years).

### 13.4 Fairness & Bias Considerations

**Risk:** AI-generated code could inadvertently introduce biased logic in:
- Credit scoring algorithms
- Customer segmentation
- Risk assessment models
- Fee calculation logic

**Mitigation:**
- Kiro-generated financial logic must undergo additional review by domain experts
- Automated bias testing in CI/CD pipeline for models and decision logic
- Steering files should include bias-awareness instructions. The repository's file is [`.kiro/steering/fairness.md`](.kiro/steering/fairness.md), which uses `inclusion: fileMatch` so it loads only for model, scoring, decisioning, pricing, credit and underwriting files. To include such a file only when the agent works on matching files, use `fileMatch` frontmatter:

```markdown
---
inclusion: fileMatch
fileMatchPattern: "src/**/credit/**"
---
# Fairness & Bias Guidelines (MAS FEAT Principles)

- Flag any code that makes decisions based on protected characteristics
- Ensure fee calculations are applied consistently across customer segments
- Credit scoring logic must be explainable and auditable
- Alert if ML model inputs include demographic proxies
```

Steering is guidance, not enforcement: the review gates above are the control.

### 13.5 MAS Guidelines on AI Risk Management (2026)

MAS published the final [Guidelines on Artificial Intelligence Risk Management](https://www.mas.gov.sg/regulation/guidelines/guidelines-on-artificial-intelligence-risk-management-for-financial-institutions) for financial institutions on **7 October 2026**, after consultation paper P017-2025 (13 November 2025).

- **Effective dates (para 1.8):** Sections 3–4 from 7 October 2027; Sections 5–6 by 7 October 2028.
- **Scope:** all FIs and all forms of AI, explicitly including generative AI / LLMs and AI agents (response paper para 2.8). The FEAT principles continue to apply (para 1.2).
- **Proportionality (para 2.3):** an FI may apply only basic AI governance policies where poor performance or unavailability of the AI tool is unlikely to have a material adverse impact; otherwise the full set of expectations (Sections 3–6) applies.
- **Coding assistants are not among the basic-tier examples.** Para 2.4 lists emails, summarising, document review, formulas/charts, image generation and internal chatbots. Kiro is an agentic coding assistant that writes and executes code, so assess its materiality yourself; do not assume the basic tier.
- **Footnote 12:** for copilots that assist in writing, some life-cycle controls may be less relevant, but controls on data management, safety and cybersecurity remain relevant and should be applied proportionately.
- **Para 2.5(b)** gives an example basic policy: prohibit inputting confidential, proprietary or client information into public AI tools. The prompt data classification in Section 11.2 supports this.
- **Agentic AI:** MAS will consult separately on additional guidance for agentic AI (response paper para 12.9). IMDA's Model AI Governance Framework for Agentic AI is cited as a reference.

**How this guide's controls support the Guidelines' themes:**

| Guidelines theme | Supporting controls in this guide | Section |
|------------------|-----------------------------------|---------|
| Governance and oversight | Senior management oversight of AI tool adoption (TRM 3.1); named owner for Kiro; AI usage policy | 12.1, 13.2 |
| AI inventory and risk materiality | Record Kiro, its models, MCP servers and custom agents in the AI inventory; document the para 2.3 materiality assessment | 12.1, 12.3 |
| Data management | Prompt data classification, DLP rules, PDPA controls | 11.1–11.3 |
| Safety and cybersecurity | MCP registry, admin permission rules, network isolation, VDI, monitoring, penetration testing | 5, 6.1, 8, 14; Part 1, Sections 3–4 |
| Human oversight / review of AI-generated code | Human review before merge, code review gates (TRM 6.1, 6.3), prompt logging | 6.3, 13.2, 13.3 |

---

## 14. Industry Standards: ABS Guidelines

### 14.1 ABS Cloud Computing Implementation Guide

The **Association of Banks in Singapore (ABS)** published the Cloud Computing Implementation Guide to help financial institutions adopt cloud services securely. Key requirements relevant to Kiro:

| ABS Requirement | Kiro Implementation |
|-----------------|---------------------|
| Data classification before cloud adoption | Classify code/data touched by Kiro per bank's data policy |
| Cloud service provider due diligence | AWS due diligence; confirm which assurance reports cover Kiro (Section 12.3) |
| Data residency and sovereignty | Workload infrastructure in `ap-southeast-1`; Kiro profile region is `us-east-1` or `eu-central-1` (no Singapore option, no setting to disable cross-region inference). Document the data location, apply PDPA s26 safeguards, keep customer data out of prompts, and exclude Global-scope models via the model allow list (Section 7.2) |
| Access control and identity management | IAM Identity Center + Enterprise IdP + MFA |
| Encryption requirements | TLS 1.2+ in transit, KMS at rest |
| Incident management | Incident response plan (Section 10) |
| Exit strategy | Documented exit plan (Section 12.4) |

### 14.2 Penetration Testing (MAS TRM 13.2; ABS Penetration Testing Guidelines)

**Relevance:** If Kiro environments (WorkSpaces, VPC endpoints, MCP servers) are in scope for penetration testing:

- **Frequency:** At least annually for internet-facing systems; risk-based for internal (MAS TRM 13.2)
- **Scope:** Include VPC endpoint security, WorkSpaces access controls, MCP server attack surface
- **Types:** Combination of blackbox and greybox testing (MAS TRM 13.2.1)
- **Production testing:** Proper safeguards required (MAS TRM 13.2.3)

### 14.3 ABS Red Team Guidelines

**Applicability:** For adversarial attack simulation of Kiro environments (MAS TRM 13.4):

- Test if attackers can bypass MCP server restrictions
- Test if DLP controls can be circumvented via AI prompts
- Test if unauthorized MCP servers can be used despite MCP governance (for example by editing `~/.kiro/settings/mcp.json`, opening an untrusted repository that ships `.kiro/settings/mcp.json`, or with local administrator rights)
- Test if admin permission rules in `managed-settings.json` can be evaded (for example with quoted or indirect shell commands) and whether hooks and VDI controls catch what the globs miss
- Validate incident detection and response capabilities for Kiro-related threats

---

## Expanded Compliance Matrix

### Comprehensive Regulatory Mapping

TRM section numbers follow the MAS Technology Risk Management Guidelines (January 2021). Each row shows where this guide's controls support a requirement; each institution remains responsible for its own compliance assessment.

| Regulation | Section | Control Area | Kiro Implementation | Document Reference |
|------------|---------|--------------|---------------------|-------------------|
| **MAS TRM** | 3.1, 3.2 | Governance & Oversight; Policies | Senior management oversight of Kiro adoption + AI usage policy | Part 2, Section 13.5 |
| **MAS TRM** | 3.4 | Management of Third Party Services | Kiro, MCP servers and model providers assessed as third-party services | Part 2, Section 12 |
| **MAS TRM** | 3.6 | Security Awareness and Training | Developer training on Kiro, MCP and PDPA | Part 2, Section 9.1 |
| **MAS TRM** | 5.4 | SDLC and Security-by-Design | Skills + steering files (guidance) | Skills Guide |
| **MAS TRM** | 6.1 | Secure Coding, Source Code Review and Application Security Testing | Code review of AI-generated code (incl. third-party/open-source code, 6.1.3) + secret scanning | Part 2, Section 6 |
| **MAS TRM** | 6.3 | DevSecOps Management | Admin permission rules (`ask` on `git push`, deny on force push) + branch protection and CODEOWNERS (human approval before merge, segregation of duties) | Part 2, Sections 6.1, 13.2 |
| **MAS TRM** | 7.5 | Change Management | Change management workflow | Part 2, Section 6.3 |
| **MAS TRM** | 9.1 | User Access Management | Enterprise IdP + IAM IDC + MFA + session management + RBAC | Part 1, Section 2 |
| **MAS TRM** | 9.3 | Remote Access Management | WorkSpaces VDI as the remote access path | Part 1, Section 4 |
| **MAS TRM** | 10.1 | Cryptographic Algorithm and Protocol | TLS 1.2+ in transit | Part 2, Section 7 |
| **MAS TRM** | 10.2 | Cryptographic Key Management | KMS customer-managed keys + rotation | Part 2, Section 7.1 |
| **MAS TRM** | 11.1 | Data Security | DLP + encryption + PDPA controls | Part 1, Section 4.1.3 |
| **MAS TRM** | 11.2 | Network Security | VPC endpoints + SG + NACLs + egress allowlist (PrivateLink to Kiro only in the profile region) | Part 1, Section 3 |
| **MAS TRM** | 11.3, 11.4 | System Security; Virtualisation Security | WorkSpaces VDI hardening | Part 1, Section 4 |
| **MAS TRM** | 12.2 | Cyber Event Monitoring and Detection | Kiro prompt logging + user activity reports + CloudTrail + CloudWatch | Part 2, Sections 8, 9.3 |
| **MAS TRM** | 12.3 | Incident Response | Escalation matrix + MAS notification | Part 2, Section 10 |
| **MAS TRM** | 13.1 | Vulnerability Assessment | Annual VA of Kiro environments | Part 2, Section 14.2 |
| **MAS TRM** | 13.2 | Penetration Testing | Annual PT of VPC + WorkSpaces | Part 2, Section 14.2 |
| **MAS TRM** | 13.4 | Adversarial Attack Simulation Exercise | Red team of Kiro environments | Part 2, Section 14.3 |
| **MAS TRM** | 14.1 | Online Financial Services | Not directly applicable (dev tool) | N/A |
| **MAS TRM** | 15.1 | IT Audit | Independent IT audit of Kiro controls, using prompt logs, user activity reports, CloudTrail logs and compliance reports as evidence | Part 2, Section 8 |
| **MAS Notice FSM-N05** (banks) | paras 5–8 | Availability, recovery, incident notification | ≤4h downtime / RTO ≤4h for critical systems; notify MAS ≤1h; RCA report ≤14 days | Part 2, Section 10 |
| **PDPA** | s11–12 | Accountability | DPO + data protection policies covering AI-assisted development | Part 2, Section 11.1 |
| **PDPA** | s24 (Protection), s25 (Retention), s26 (Transfer Limitation) | Care of Personal Data (Part 6) | DLP + data classification + encryption + purpose-based retention + transfer safeguards | Part 2, Section 11 |
| **PDPA** | Part 6A | Data Breach Notification | Assess (generally ≤30 days); notify PDPC ≤3 calendar days after determining notifiable | Part 2, Section 11.4 |
| **MAS Outsourcing** | Materiality & risk assessment | Risk Assessment | Materiality assessment + outsourcing/third-party risk register | Part 2, Section 12 |
| **MAS Outsourcing** | Due diligence | Due Diligence | Review AWS assurance reports; confirm Kiro is in scope | Part 2, Section 12.3 |
| **MAS Outsourcing** | Exit / termination | Exit Strategy | Documented transition plan | Part 2, Section 12.4 |
| **MAS FEAT** | All | AI Governance (applied by analogy) | FEAT controls for Kiro | Part 2, Section 13 |
| **MAS AI Risk Management Guidelines** | Sections 3–6 | AI governance, inventory, materiality, life-cycle controls | Proportionate controls for Kiro | Part 2, Section 13.5 |
| **ABS Cloud** | All | Cloud Security | Defense-in-depth for Kiro | Part 2, Section 14.1 |

"MAS Outsourcing" means MAS Notice 658 and the Guidelines on Outsourcing (Banks) for banks, and the Guidelines on Outsourcing (Financial Institutions other than Banks) for other FIs, all effective 11 December 2024. Requirements are cited by topic because the section numbers of the cancelled 2016/2018 guidelines no longer apply.

---

## Document Complete

**Total Coverage:**
- Sections 1-4: Architecture, Identity, Network, VDI (Part 1)
- Sections 5-10: MCP Governance, SDLC, Data Protection, Compliance, Operations, Incident Response (Part 2)
- Sections 11-14: PDPA, Outsourcing, AI/ML Governance, ABS Industry Standards (Part 2, Enhanced)

**Reference Material:** All sections include reference configurations, scripts, and compliance mappings for Singapore banking environments. They are designed to support alignment with MAS and PDPA expectations and are not a substitute for your own testing; each institution remains responsible for its own compliance assessment.

---

## License & Disclaimer

This documentation is licensed under the [MIT License](LICENSE).

> **Disclaimer:** This documentation is provided for informational and educational purposes only. It does not constitute legal advice, regulatory guidance, or professional security consulting. Organizations must conduct independent security assessments, consult qualified professionals, and validate all implementations against their specific regulatory requirements. See [README.md](README.md#disclaimer) for full disclaimer.
