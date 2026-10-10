# Agent Runtime Governance (Layer 4)

Layer 4 (Application) of the Security Architecture in the root `README.md`: the controls that decide what the Kiro agent may read, write, execute and send while a session runs. Layers 1-3 and 5 (identity, network, VDI, monitoring) secure everything around Kiro; this layer governs the agent itself.

> **Last verified:** 2026-10-08 against the official Kiro documentation (links in [References](#references)). Applies to Kiro IDE 1.x and the Kiro CLI V3 engine (`kiro-cli --v3`, shipped in CLI 2.x; there is no CLI 3.x binary). Latest versions on that date: IDE 1.2.37 and CLI 2.28.0. Kiro changes quickly: re-check the pages and pilot every upgrade.

## Read this first: the enforcement boundary

Kiro's admin policy file, `managed-settings.json`, is the administrator layer of the permission system. Kiro enforces it in the installed client, and the official page says it "can be circumvented by users, e.g., via administrative access to their local machine". The same applies to every other control in this layer. Four things therefore have to be true for Layer 4 to mean anything:

1. Developers work as **standard users** (no local administrator or root), ideally on a managed VDI such as Amazon WorkSpaces.
2. MDM deploys the policy to the official path, keeps it administrator-owned, and **detects drift** by re-running and comparing hashes ([`mdm-endpoint-enforcement.md`](mdm-endpoint-enforcement.md)).
3. The **authoritative boundaries stay outside Kiro**: Git server branch protection and required reviews, least-privilege IAM, egress filtering (the `cdk/` network stack), and subscription management in the IdP and the Kiro console.
4. Kiro Web (Cloud Sessions) is turned off, because the admin policy does not apply to it.

> **Correction (2026-10-08).** Earlier versions of this page said that Kiro has "no un-removable managed settings layer" and that the boundary had to be built by making `~/.kiro/agents`, `~/.kiro/steering` and `~/.kiro/settings/cli.json` read-only. That is superseded. `managed-settings.json` is the client-enforced admin layer: a standard user cannot change it and no user, workspace, agent or session rule can weaken it. An administrator or root user still can, which is why the four conditions above remain necessary. Agent `toolsSettings` (including `denyByDefault`) is deprecated; see [4d](#4d-user-and-agent-permissions).

## The layered model

Strongest first. Each layer assumes the ones above it are in place.

| Layer | Control | Configured in | Enforced by | Fails |
|-------|---------|---------------|-------------|-------|
| **4a** | Admin policy: `managed-settings.json` (deny/ask rules, sign-in restriction) | [`../managed-settings/`](../managed-settings/), deployed by MDM | Kiro client (IDE and CLI on the machine) | Permission rules closed; sign-in rules open |
| **4b** | Organization settings: model allow list, MCP governance and registry, web tools, API keys, Cloud Sessions, prompt logging | Kiro console > Settings | Kiro service and client | MCP closed if the governance API is unreachable |
| **4c** | Workspace trust: unknown repositories stay untrusted | Each user's Kiro client (stored outside the repository) | Kiro client | n/a |
| **4d** | User and agent permissions (convenience; never weaker than 4a) | `~/.kiro/settings/permissions.yaml`, agent `permissions.rules` | Kiro client | n/a |
| **4e** | Hooks: secret/PII scanning, git and destructive-command guards (defense in depth) | [`../agent-hooks/`](../agent-hooks/) | Hook scripts run by the client | Designed to block on any internal error (exit 2) |
| **4f** | Audit: Kiro prompt logging and user activity reports to S3, then SIEM; CloudTrail for the AWS account | Kiro console, SIEM | AWS (server side) | n/a |

### 4a. Admin policy (`managed-settings.json`)

| OS | Official path |
|----|---------------|
| Linux | `/etc/kiro/managed-settings.json` |
| macOS | `/Library/Application Support/Kiro/managed-settings.json` |
| Windows | `C:\ProgramData\Kiro\managed-settings.json` (UTF-8 **without** BOM; Windows PowerShell `Out-File` writes UTF-16 by default, which Kiro rejects) |

- **One file for every surface on the machine.** The IDE and the CLI read the same file at start-up; restart Kiro after a change. It does not apply to Kiro Web. Administration scope is an enterprise feature.
- **Schema:** `{"rules": [...], "settings": {...}}`. Rule fields are `capability`, `match`, `exclude`, `effect`, and admin rules may only use `deny` or `ask`.
- **Failure behaviour.** Permission rules fail **closed**: malformed JSON, any `"effect": "allow"` or an unknown field makes Kiro reject the whole file and deny all tool calls until it is fixed. An unknown capability is skipped with a warning. Sign-in rules fail **open**: an invalid or unreadable file drops the restriction and offers every sign-in method. The MDM scripts in `mdm/` validate the file and refuse `allow` rules before deploying it.
- **Deny-overrides.** Kiro evaluates the Kiro (hardcoded), administration, user, workspace, agent and session scopes together; the result is `deny > ask > allow` with no precedence between scopes. A denial caused by the policy names its source as "administration".
- **Session overrides cannot weaken it.** `kiro-cli --trust-all-tools`, `/tools trust-all` (CLI V3, 2.24.0), "Always allow ... This session", policy presets requested by ACP clients, user `permissions.yaml` and agent `permissions` rules are all `allow` sources. They remove Kiro's default prompts, but an admin `deny` still blocks and an admin `ask` still prompts. What they do remove is the default prompt for everything the admin policy does not mention, so add admin `ask` rules for any category a human must always see. A launcher wrapper that rejects `--trust-all-tools` is a weak control, because the developer can call the binary directly.
- **Headless runs** treat every `ask` as `deny`.
- **IDE autonomy** (`kiroAgent.agentAutonomy`, Autopilot or Supervised) is decided first; permission rules apply after it. Autopilot does not bypass admin rules.
- **The bundled policy** ([`../managed-settings/managed-settings.banking.json`](../managed-settings/managed-settings.banking.json), Option A with IAM Identity Center sign-in; `managed-settings.option-b.json` for direct IdP federation) denies force-push and history rewriting, hook skipping, catastrophic deletion, privilege escalation, nested shells and `eval`, raw network transfer tools, IAM and secret retrieval, and reads of key and credential files; it asks before pushes, releases, deployments, AWS write operations, bulk deletion, inline interpreter code, CI/CD and review-ownership files, steering and skills, web fetch and web search. The rule-by-rule rationale is in [`../managed-settings/README.md`](../managed-settings/README.md).
- **Glob limits.** Rules match command text, not effect. Quoting (`r""m -rf /`), wrappers, variables, aliases and scripts the agent writes and then runs can evade a glob. Hooks (4e) are the second layer and OS, VDI, IAM and server-side controls the third.

### 4b. Organization settings (Kiro console)

Set these in Kiro console > Settings > Shared settings. Details and changelog references: [`security-governance-features.md`](security-governance-features.md).

- **Models:** use a managed approved list; with a managed list, new models are unavailable until added. Exclude by default: Global-scope models (GPT-5.6 Sol, Terra and Luna; processed in AWS Regions worldwide, through the US endpoint even for `eu-central-1` profiles); preview models such as Claude Fable 5.1 Preview (us-east-1 only), which has a 30-day retention exception for abuse detection; and experimental models such as Claude Opus 5.5 and Sonnet 5.5, which have Geography inference scope like all Claude models. See the model approval matrix in [`security-governance-features.md`](security-governance-features.md) (Section 2.2.1).
- **MCP:** turn on MCP governance and point the MCP Registry URL at an HTTPS registry with **exact pinned versions** ([`../managed-settings/mcp-registry.example.json`](../managed-settings/mcp-registry.example.json), [`mcp-security.md`](mcp-security.md)). Servers not in the registry are hidden; MCP fails closed if the client cannot reach the governance API. It applies to IAM Identity Center and API-key users, in the IDE and CLI, not to Builder ID or social sign-in, and not to Kiro Web.
- **Web tools:** web search and web fetch are on by default; turn them off, or keep the admin `ask` rules.
- **API keys:** generation is off by default; keep it off unless a use case is assessed.
- **Cloud Sessions:** keep **off**. They run in us-east-1 only, and the customer managed KMS key, MCP configuration, MCP registry, model availability and `managed-settings.json` do not apply to Kiro Web.
- **Prompt logging:** turn on (see 4f).

### 4c. Workspace trust

A workspace is untrusted until the user trusts it. The decision is stored outside the workspace, so a repository cannot trust itself. While a workspace is untrusted, Kiro does not load its custom agents, steering, MCP configuration, skills or workflow files; asks before every shell command (even if a rule allows it), every MCP tool call and every Power activation (even with `autoApprove`); and refuses writes to `~/.kiro/memories/` and the session store. Admin rules still apply.

Guidance: trust only repositories from your organization's Git server after review; open third-party code, pull requests from forks and downloaded samples untrusted. Do not add a blanket `fs_write` allow (no `match`) to a user `permissions.yaml`: it is the one rule that lifts the untrusted-only `.kiro` write prompts. The untrusted list on the official page does not mention workspace hook files (`.kiro/hooks/`); verify on your Kiro version whether they run in an untrusted workspace, and review `.kiro/hooks/` in third-party repositories before opening them.

### 4d. User and agent permissions

- **User scope:** `~/.kiro/settings/permissions.yaml`. The template [`../managed-settings/permissions.banking.yaml`](../managed-settings/permissions.banking.yaml) removes prompts for low-risk local work (read-only commands, tests, lint, synth, writes under `src/`, `test/`, `tests/`, `docs/`).
- **Workspace scope:** created through the "Always allow ... This workspace" picker and stored per user outside the repository in `~/.kiro/workspace-roots/<hash>/permissions.yaml`, so a cloned repository cannot inject rules.
- **Agent scope:** the `permissions` field (`{"rules": [...]}`) of an agent such as `banking-secure` ([`../agent-hooks/banking-secure.agent.json`](../agent-hooks/banking-secure.agent.json)).
- These scopes are a convenience. They can add `deny` and `ask` rules, but their `allow` rules can never override 4a, because deny wins.
- **`toolsSettings` is deprecated** ("deprecated in CLI 3.0 and IDE 1.0. Use the permissions field"; the V3 agent page says it is removed in V3). `kiro-cli agent migrate` (or `/upgrade-agent`) converts allowed and denied commands and paths to `permissions.rules`. `autoAllowReadonly` and `denyByDefault` have **no equivalent**: express them as explicit rules. Earlier versions of this repository recommended `denyByDefault` as the primary agent control; that advice no longer applies, and the primary control is now 4a.

### 4e. Hooks

| File | Purpose | Installed to |
|------|---------|--------------|
| `agent-hooks/pii-guard.sh` | PreToolUse: blocks tool input that contains card numbers, AWS access keys, private keys, Singapore NRIC/FIN or credential assignments | Root-owned hook directory (below) |
| `agent-hooks/git-guard.sh` | PreToolUse (shell): blocks force-push variants, pushes to protected branches and history-destroying commands | Same |
| `agent-hooks/destructive-fs-guard.sh` | PreToolUse (shell): blocks recursive deletion of root, home, workspace or `.git`, bulk `find -delete`, `mkfs` and raw device writes | Same |
| `agent-hooks/audit-logger.sh` | PostToolUse: appends a hash-chained JSONL record to `${KIRO_AUDIT_LOG:-$HOME/.kiro/audit/kiro-hooks.jsonl}` | Same |
| `agent-hooks/hooks/banking-guards.json` | v1 hook file that wires the scripts (IDE 1.0+, CLI V3) | `~/.kiro/hooks/` (global) or `.kiro/hooks/` (workspace) |
| `agent-hooks/banking-secure.agent.json` | Agent with `permissions.rules` and CLI 2.x embedded hooks | `~/.kiro/agents/banking-secure.json` |
| `agent-hooks/SHA256SUMS` | Pinned hashes of the four scripts | Verified by the MDM scripts before deployment |

The shipped JSON references `/opt/kiro/hooks/<script>.sh`. `mdm/lockdown-linux.sh --hooks` deploys the scripts there (root-owned, 0755) after verifying `SHA256SUMS`; `mdm/lockdown-macos.sh` deploys them to `/Library/Application Support/Kiro/hooks` and rewrites the path in the copies it installs. On Windows the scripts need Git Bash or WSL; managed-settings is the primary control there.

**Exit-code contract.** Hook commands receive the event JSON on STDIN (`hook_event_name`, `cwd`, `session_id`, `tool_name`, `tool_input`; PostToolUse adds `tool_response`). For PreToolUse, UserPromptSubmit and PreTaskExec, **exit 2 blocks** and STDERR is returned to the model. According to the Hook triggers page (2026-09-30), any other non-zero exit is treated as an **error, not a block**: execution proceeds and STDERR is shown as a warning.

> **Docs conflict.** The older Hook actions page (2026-08-04) says any non-zero exit blocks a Pre Tool Use or Prompt Submit hook. This repository follows the newer page and designs every guard to exit 2 both on a policy match **and** on any internal failure (missing `jq`, unparsable input, unexpected errors), so the guard blocks under either reading.

- **Timeouts:** v1 hook files use `timeout` in seconds (default 60; 0 disables); CLI 2.x embedded agent hooks use `timeout_ms` (default 30000). The documentation does not say that a timeout blocks the call, so keep guards fast and do not rely on a timeout to stop anything.
- **Matchers:** the IDE uses categories (`read`, `write`, `shell`, `web`, `spec`, `*`, plus `@mcp`, `@powers`, `@builtin`); the CLI uses canonical tool names (`fs_read`, `fs_write`, `execute_bash`, `use_aws`) and aliases (`read`, `write`, `shell`, `aws`). Embedded agent hooks are a CLI feature; IDE support varies by version, so use the v1 hook file for the IDE. If the agent hooks and the global v1 file are both installed, a CLI session can run the guards twice; that is harmless.
- **Limits.** Guards are pattern-based: encoded or obfuscated payloads (for example base64 piped to a shell) can pass. They run as the developer, who can read them, and the v1 hook file and agent live in user-owned `~/.kiro` directories. Kiro always asks before the **agent** writes to the hooks or agents directories, but the **developer** can edit or delete those files; MDM `--check` reports that drift. The guarantee therefore comes from 4a, not from the hook files.
- **Skills are guidance.** The `pii-detection` skill (`.kiro/skills/pii-detection/`) advises the model; `pii-guard.sh` is the enforcing counterpart. Steering files are guidance too.

### 4f. Audit

- **Kiro prompt logging** (console: Kiro Settings > Logging > "Log Kiro prompts with metadata") writes every chat conversation and inline suggestion from the IDE and CLI to an S3 bucket in the profile region and the subscribing account. Bucket policy: principal `q.amazonaws.com`, action `s3:PutObject`, condition `aws:SourceArn` = `arn:aws:codewhisperer:<region>:<accountId>:*`. This is the audit record of what was asked and answered.
- **User activity reports:** daily CSV per client type to `s3://<bucket>/<prefix>/AWSLogs/<account>/KiroLogs/user_report/<region>/...`; same region and account; prefix required.
- **OpenTelemetry usage export:** daily `kiro.daily.*` metrics; useful for capacity, **not** an audit trail.
- **CloudTrail** covers the AWS account. Kiro documentation says only that CloudTrail "captures API calls" and does not name event sources or data events; verify in your own account (candidates such as `codewhisperer.amazonaws.com` or `q.amazonaws.com` are unverified). MCP tools run on the client and do not appear in CloudTrail.
- **Local hook log** (`audit-logger.sh`): supplementary only. The SHA-256 chain makes accidental edits visible, but it is **not tamper-proof**: there is no secret key, the developer can redirect it with `KIRO_AUDIT_LOG` or rename the user-owned directory, and the file is only append-only if the OS makes it so (`chattr +a` on Linux; `chflags uappnd` on macOS, which the owner can clear, or `sappnd` with `--audit-sappnd`). Ship it off the machine in near real time if you use it.

## Kiro hardcoded invariants

These cannot be configured and apply in every scope:

- **Always denied** to the agent: writes to `~/.kiro/settings/`, `.kiro/settings/`, `~/.kiro/workspace-roots/`, an installed Power's `mcp.json`, and Kiro state stores. The agent can never edit its own permission or MCP configuration.
- **Always ask** (no allow rule from any scope removes the prompt): writes to `.git/**`, `.vscode/**`, `**/*.code-workspace`, `.kiroignore`, and the agents, hooks, workflows and powers directories of the workspace `.kiro` and of `~/.kiro`.
- **Protected configuration** (IDE 1.2): Kiro asks before the agent changes agent, hook or Power files or `.kiro/workflows/` recipes, even when broader file permissions allow the write.

These protect against a prompt-injected agent, not against the developer, who can edit the same files directly.

## Where Kiro reads each file

| Artifact | Location Kiro reads | Owner | Notes |
|----------|---------------------|-------|-------|
| Admin policy | Official path per OS (see 4a) | root / Administrators | Deployed by `mdm/lockdown-*`; the only file a standard user cannot change |
| User permissions | `~/.kiro/settings/permissions.yaml` | User | The agent can never write it |
| Workspace permissions | `~/.kiro/workspace-roots/<hash>/permissions.yaml` | User | Outside the repository |
| Custom agents | `~/.kiro/agents/<name>.json` or `.md`; workspace `.kiro/agents/` (trusted workspaces only) | User | Not loaded from `/opt`, `/Library` or any other path. A workspace agent with the same name wins, with a warning |
| v1 hook files | `~/.kiro/hooks/*.json`; workspace `.kiro/hooks/*.json` | User | Any `.json` name; several hooks per file |
| Hook scripts | Wherever the hook `command` points | root (repo convention) | `/opt/kiro/hooks` (Linux), `/Library/Application Support/Kiro/hooks` (macOS) |
| Steering | `~/.kiro/steering/`, `.kiro/steering/`, `AGENTS.md` | User / repository | Guidance, not enforcement |
| MCP configuration | `~/.kiro/settings/mcp.json`, `.kiro/settings/mcp.json` | User / repository | Governed by the console registry; the agent cannot write these files |
| Hook audit log | `${KIRO_AUDIT_LOG:-$HOME/.kiro/audit/kiro-hooks.jsonl}` | User | Supplementary |

## Control mapping

| Control | Mechanism | Enforced by | Bypass risk | MAS TRM |
|---------|-----------|-------------|-------------|---------|
| Corporate sign-in only | `signin_method` deny rule (keep `idc` or `external_idp`) plus prefilled start URL and Region | Kiro client, at sign-in | Fails open on an invalid file; local admin; Kiro Web and older clients not covered. Who may use Kiro is still decided in the IdP and Kiro subscriptions | 9.1 |
| No privilege escalation or identity changes by the agent | Admin deny: `sudo *`, `su *`, `chown *`, `aws iam *`, `aws sts assume-role*`, `aws secretsmanager get-secret-value*` | Kiro client (deny > ask > allow) | Glob evasion (quoting, variables, scripts); local admin. IAM least privilege is the real limit | 9.1, 9.2 |
| Session overrides cannot weaken policy | Admin scope allows only deny/ask; deny-overrides across scopes | Kiro client | None from inside Kiro; removing the file needs admin rights (detected by MDM) | 9.2 |
| Secrets and credentials kept out of prompts | Admin `fs_read` deny on `.env`, key files, keystores, `~/.ssh`, `~/.aws/credentials` and token caches; `pii-guard.sh` | Kiro client + hook | Encoded content; secrets in paths that no pattern matches; local admin | 11.1 |
| No raw exfiltration from the workstation | Admin deny on `curl`, `wget`, `nc`, `scp`, `sftp`; ask on `web_fetch`, `web_search`; console web tools; VPC egress filtering | Kiro client + network | Interpreters and indirection (inline code is only `ask`); the network layer is the boundary | 11.1, 11.2 |
| MCP supply chain | Console MCP governance and registry with exact versions; workspace trust | Kiro client (closed if the governance API is unreachable) | Builder ID and social users not covered; client-side | 11.2 |
| Source integrity, no history rewrite | Admin deny on force-push variants, `reset --hard`, `filter-branch`, remote branch deletion, `--no-verify`; `git-guard.sh`; Git server branch protection | Kiro client + hook + Git server (authoritative) | A human in a shell can push with any git binary; glob evasion. Server-side protection is the boundary | 6.1, 6.3 |
| Segregation of duties for pipelines and review ownership | Admin ask on CI/CD definitions, `CODEOWNERS`, pre-commit config; required reviews on the Git server | Kiro client + Git server | The developer can approve their own prompt; required reviews must be server-side | 6.3 |
| Change management for releases and infrastructure | Admin ask on `cdk deploy`, `terraform apply`, `npm publish`, `docker push`, AWS write operations; `ask` becomes `deny` in headless runs | Kiro client + pipeline approvals | Human approval in the prompt; production changes must still go through the pipeline | 7.5 |
| Agent cannot rewrite its own configuration or instructions | Hardcoded deny on settings, always-ask on agents and hooks; admin ask on steering, skills and `AGENTS.md`; protected configuration | Kiro client | The developer can edit the files directly | 6.3, 7.5 |
| Untrusted repositories cannot run their own agents, MCP servers or steering | Workspace trust | Kiro client | The user trusts the workspace; workspace hooks in untrusted workspaces not documented | 6.1 |
| Destructive commands | Admin deny on `rm -rf` of `/`, `~`, `$HOME`, `..`, `.git`, `mkfs`, `dd` to devices; ask on other recursive deletion; `destructive-fs-guard.sh`; backups | Kiro client + hook + backups | Indirection; the developer in a plain shell; recovery depends on backups | 11.1 |
| Audit trail | Kiro prompt logging and user activity reports to S3, then SIEM; CloudTrail; local hook log (supplementary) | AWS, server side | Only if enabled; the local log can be redirected or renamed | 12.2 |
| Policy drift detection | MDM re-run and `--check` / `-Check` hash comparison (exit 3 on drift) | MDM | Detects rather than prevents; an administrator can stop the MDM agent | 12.2, 7.5 |

## Testing

- Hooks: `bash agent-hooks/tests/run-tests.sh`, including regression tests for the PR3 review findings. CI (`validate-governance`) runs them.
- MDM scripts: `bash mdm/tests/test-lockdown.sh` and `bash mdm/tests/test-lockdown-macos.sh` run non-root dry-run tests by default (policy validation, `SHA256SUMS` verification, planned actions, no system changes). Root and administrator tests are opt-in and only for disposable hosts. CI runs the Linux dry run.
- Adversarial: `bash security-tests/chaos/run-chaos.sh --hooks-only` and `run-chaos-hardened.sh --hooks-only` feed crafted events to the shipped hooks without root or system changes. The full runs need a throwaway Linux VM and `CHAOS_ALLOW_SYSTEM_CHANGES=1`. They exercise hook-level and OS-level controls only and do not drive a Kiro client.
- Pilot: restart Kiro, ask the agent to run a denied command (for example `git push --force`) and confirm that the denial names "administration"; sign out and confirm that only the permitted sign-in method is offered.

Results for the current hooks, MDM scripts and chaos harness (disposable EC2 instances, 2026-10-10) are in [`aws-integration-test-evidence.md`](aws-integration-test-evidence.md). They do not include a live Kiro session, because the end-to-end prompts were skipped without an API key. Historical results ([`chaos-pentest-evidence.md`](chaos-pentest-evidence.md), [`mdm-test-evidence.md`](mdm-test-evidence.md)) predate this model; read their dated notes.

## References

Official Kiro documentation (verified 2026-10-08):

- Permissions: https://kiro.dev/docs/permissions/ (workspace trust: https://kiro.dev/docs/permissions/#workspace-trust)
- Permission policies (`managed-settings.json`): https://kiro.dev/docs/enterprise/governance/permissions/
- Sign-in controls: https://kiro.dev/docs/enterprise/governance/sign-in/
- Enterprise governance: https://kiro.dev/docs/enterprise/governance/
- Model governance: https://kiro.dev/docs/enterprise/governance/model/
- MCP governance and registry: https://kiro.dev/docs/enterprise/governance/mcp/ and https://kiro.dev/docs/mcp/registry/
- Web tools governance: https://kiro.dev/docs/enterprise/governance/web-tools/
- Hooks: https://kiro.dev/docs/hooks/ and https://kiro.dev/docs/hooks/types/
- Custom agents: https://kiro.dev/docs/custom-agents/ and https://kiro.dev/docs/custom-agents/configuration-reference/
- Kiro CLI V3: https://kiro.dev/docs/cli/v3/
- Prompt logging: https://kiro.dev/docs/enterprise/monitor-and-track/prompt-logging/
- Managed updates: https://kiro.dev/docs/enterprise/managed-updates/

In this repository: [`permissions-and-managed-settings.md`](permissions-and-managed-settings.md) (reference snapshot), [`../managed-settings/README.md`](../managed-settings/README.md) (policy and rationale), [`mdm-endpoint-enforcement.md`](mdm-endpoint-enforcement.md) (deployment and drift), [`security-governance-features.md`](security-governance-features.md) (console settings and changelog).
