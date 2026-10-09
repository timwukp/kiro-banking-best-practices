# Kiro Managed Settings for Banking (Layer 4a)

Reference administrator policy, user permission template and MCP registry example for running Kiro 1.x (IDE 1.0+, CLI V3 engine) in a MAS-regulated software development environment.

> **Last verified:** 2026-10-08 against the official Kiro documentation (links at the end). Kiro changes quickly: re-check the pages and test on a pilot machine before each fleet rollout.

## Contents

| File | Deploy to | Purpose |
|------|-----------|---------|
| [`managed-settings.banking.json`](managed-settings.banking.json) | OS-protected admin path (see [Deployment paths](#deployment-paths)) | **Option A** (sign-in through IAM Identity Center). Admin deny/ask rules plus a sign-in restriction to `idc` |
| [`managed-settings.option-b.json`](managed-settings.option-b.json) | Same path | **Option B** (direct external IdP federation). Same rules; sign-in restricted to `external_idp` |
| [`permissions.banking.yaml`](permissions.banking.yaml) | `~/.kiro/settings/permissions.yaml` (per user) | User-scope convenience template: silent approval for routine read-only, test, lint and synth commands and for writes to `src/`, `test/`, `tests/`, `docs/` |
| [`mcp-registry.example.json`](mcp-registry.example.json) | An HTTPS URL entered in the Kiro console (MCP Registry URL) | MCP allow list in the official registry format, with exact pinned versions |

Deploy only one `managed-settings.*.json` per machine, renamed to `managed-settings.json`. Replace every placeholder first: `d-xxxxxxxxxx`, `it.example.com`, `bank.example.com`, `idp.example.com`, `mcp.internal.example.com`, and the example MCP versions.

## Where this fits in the governance stack

| Layer | Control | Where |
|-------|---------|-------|
| 4a | Admin policy: `managed-settings.json` (deny/ask rules + sign-in restriction) | This folder, deployed by MDM |
| 4b | Organization settings: model allow list, MCP governance and registry, web tools, API keys off, Cloud Sessions off, prompt logging on | Kiro console > Settings |
| 4c | Workspace trust: leave unknown repositories untrusted | Each user's Kiro client |
| 4d | User and agent permissions (convenience, never weaker than 4a because deny wins) | `permissions.banking.yaml`, agent `permissions.rules` in [`../agent-hooks/`](../agent-hooks/) |
| 4e | Hooks: secret/PII scanning, git and destructive-command guards (defense in depth) | [`../agent-hooks/`](../agent-hooks/) |
| 4f | Audit: Kiro prompt logging and user activity reports to S3, CloudTrail for the AWS account | Kiro console, SIEM |

## Requirements and scope

- **Plan:** the administration scope (`managed-settings.json`) is an enterprise feature. Users must sign in with an enterprise identity for the organization settings in layer 4b to apply.
- **Client versions:** permission rules use the capability-based permission system of Kiro IDE 1.0+ and the Kiro CLI V3 engine (`kiro-cli --v3`, shipped in CLI 2.x; there is no CLI 3.x binary). Sign-in controls need **IDE 1.2+ and CLI 2.25.0+**; older clients ignore them. Recommended minimum for this policy: IDE 1.2 and CLI 2.25.0 (latest on 2026-10-08: IDE 1.2.37, CLI 2.28.0). Use V3 sessions in the CLI: whether Classic (2.x engine) sessions honour admin permission rules is not documented, so verify on a pilot machine or block Classic sessions operationally.
- **Surfaces:** one file applies to every Kiro surface on the machine; the IDE and the CLI read the same file. It does **not** apply to Kiro Web (Cloud Sessions). Keep Cloud Sessions turned off in the Kiro console.
- **Restart:** permission rules are read when Kiro starts. Restart the IDE and all CLI sessions after every change. Sign-in controls are read when a sign-in starts, so they take effect at the next sign-in.

## Deployment paths

| OS | Path (official) | Write access |
|----|-----------------|--------------|
| macOS | `/Library/Application Support/Kiro/managed-settings.json` | root only |
| Windows | `C:\ProgramData\Kiro\managed-settings.json` | Administrators and SYSTEM only |
| Linux | `/etc/kiro/managed-settings.json` | root only |

Users need read access to the file. They must not have local administrator or root rights, otherwise they can change or delete it (see [Client-side enforcement](#client-side-enforcement)).

**macOS**

```bash
sudo mkdir -p "/Library/Application Support/Kiro"
sudo install -m 0644 -o root -g wheel managed-settings/managed-settings.banking.json \
  "/Library/Application Support/Kiro/managed-settings.json"
```

**Linux**

```bash
sudo install -D -m 0644 -o root -g root managed-settings/managed-settings.banking.json \
  /etc/kiro/managed-settings.json
```

**Windows (elevated PowerShell)**

Kiro requires **UTF-8 without a byte order mark (BOM)**. It rejects UTF-16 files, which Windows PowerShell `Out-File` (and `>` redirection) writes by default, and files that start with a BOM. An invalid file blocks all agent tools (see [Failure behaviour](#failure-behaviour)). Write the file with .NET instead:

```powershell
$dir  = 'C:\ProgramData\Kiro'
$path = Join-Path $dir 'managed-settings.json'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$content = Get-Content -Raw -Encoding UTF8 -Path '.\managed-settings\managed-settings.banking.json'
[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding $false))
# Administrators (S-1-5-32-544) and SYSTEM (S-1-5-18) full control; Users (S-1-5-32-545) read only
icacls $dir /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX'
# Verify there is no BOM: the first byte must be 123 ('{'), not 239
[System.IO.File]::ReadAllBytes($path)[0]
```

**At scale:** deploy with MDM (Jamf, Kandji, Intune), Group Policy or SCCM, or bake the file into the WorkSpaces/VDI image. The scripts in [`../mdm/`](../mdm/) (`lockdown-macos.sh`, `lockdown-linux.sh`, `lockdown-windows.ps1`) deploy the policy to these official paths with administrator-only write access (the Option A file by default; see each script's usage text for selecting Option B or another source); see [`../kiro-docs/mdm-endpoint-enforcement.md`](../kiro-docs/mdm-endpoint-enforcement.md). Use the MDM's compliance reporting to detect devices where the file is missing or changed.

## What the bundled policy does

The JSON files cannot carry comments, so every rule is explained here. Rules are listed in file order. Shell patterns follow the official glob rules: `*` matches any sequence of characters (including spaces and `/`), and compound commands (`;`, `&&`, `||`, `|`) are split and checked one by one. Every shell pattern ends with `*`, so it behaves the same whether Kiro matches the whole command or a command prefix. Filesystem patterns: `*` stays in one path component, `**` crosses directories.

| # | Capability / effect | Patterns (summary) | Rationale | MAS TRM |
|---|---------------------|--------------------|-----------|---------|
| 1 | `signin_method` / deny | `match: ["*"]`, `exclude: ["idc"]` (Option B: `["external_idp"]`) | Only the corporate identity is offered; Builder ID, Google and GitHub sign-in are removed, and a denied method is refused before a token is issued. Settings prefill the Identity Center start URL and Region (`ap-southeast-1` here) and show an internal help link. This is a client guardrail, not access control: who may use Kiro is still decided by subscriptions in the IdP and Kiro console | 9.1 |
| 2 | `shell` / deny | `git push *--force*`, `git push -f*`, `git push * -f*`, `git push *+*`, `git push * :*`, `--mirror`, `--delete`, `-d`, `--prune`, `git reset *--hard*`, `git clean -*f*`, `git branch *-D*`, `git filter-branch*`, `git filter-repo*`, `git update-ref -d*`, `git reflog expire*` | Prevents the agent from rewriting or deleting shared history, deleting remote branches, or destroying uncommitted work. Source integrity and an auditable change trail | 6.3, 7.5 |
| 3 | `shell` / deny | `git commit *--no-verify*`, `git commit -n*`, `git push *--no-verify*`, `git config *core.hooksPath*` | Stops the agent from skipping or redirecting pre-commit and pre-push hooks (secret scanning, linting, tests) | 6.1, 6.3 |
| 4 | `shell` / deny | `rm -rf` and `rm -fr` of `/…`, `~…`, `$HOME…`, `..…`, `.git…`, `./.git…`; `mkfs*`; `dd *of=/dev/*` | Blocks catastrophic deletion outside the workspace or of the repository itself, and raw disk writes. Note that recursive force deletion of any absolute path is denied; use relative paths inside the workspace (rule 12 asks for those) | 11.3 |
| 5 | `shell` / deny | `sudo *`, `su *`, `doas *`, `chown *`, `chmod 777 *`, `chmod * 777 *` | No privilege escalation or ownership changes by the agent; no world-writable permissions | 9.2, 11.3 |
| 6 | `shell` / deny | `bash -c *`, `bash -lc *`, `sh -c *`, `zsh -c *`, `/bin/bash -c *`, `/bin/sh -c *`, `/bin/zsh -c *`, `eval *` | The agent already runs commands in a shell. Nested shells and `eval` hide the real command from glob rules and from reviewers | 11.3 |
| 7 | `shell` / deny | `curl *`, `wget *`, `nc *`, `ncat *`, `netcat *`, `telnet *`, `ftp *`, `scp *`, `sftp *` | Raw network transfer tools are the simplest exfiltration path for source code and customer data. Fetching documentation goes through `web_fetch` (rule 18), which prompts | 11.1, 11.2 |
| 8 | `shell` / deny | `aws iam *`, `aws organizations *`, `aws sts assume-role*`, `aws secretsmanager get-secret-value*`, `aws ssm get-parameter*--with-decryption*`, `aws kms decrypt*` | No identity changes, role chaining or secret retrieval by the agent, even when the developer's credentials would allow it | 9.2, 10.2, 11.1 |
| 9 | `shell` / ask | `git push*`, `git remote add*`, `git remote set-url*`, `gh *`, `ssh *` | Anything that leaves the workstation or changes where code is pushed needs a human decision. Branch protection on the Git server remains the authoritative control | 6.3, 9.3 |
| 10 | `shell` / ask | `npm publish*`, `npm unpublish*`, `yarn publish*`, `pnpm publish*`, `twine upload*`, `docker push*`, `mvn deploy*`, `cdk deploy*`, `cdk destroy*`, `npx cdk deploy*`, `npx cdk destroy*`, `terraform apply*`, `terraform destroy*` | Releases and infrastructure changes go through change management; the agent can prepare them but a human approves each one. In headless runs `ask` becomes `deny` | 7.5, 7.6, 6.3 |
| 11 | `shell` / ask | `aws * create-*`, `aws * delete-*`, `aws * put-*`, `aws * update-*`, `aws * terminate-*`, `aws s3 cp*`, `aws s3 mv*`, `aws s3 rm*`, `aws s3 rb*`, `aws s3 sync*` | AWS write operations and S3 transfers (a data-movement path) prompt. Read-only AWS CLI calls are not covered by this rule and fall back to Kiro's default (ask) unless a user rule allows them | 7.5, 9.2, 11.1 |
| 12 | `shell` / ask | `rm -r*`, `rm -R*`, `rm -f*`, `rm *--recursive*`, `xargs *`, `find * -exec*`, `find * -delete*`, `python -c *`, `python3 -c *`, `node -e *`, `perl -e *`, `ruby -e *` | Bulk deletion and inline interpreter code are legitimate but can hide destructive or network actions; a human sees the full command first | 11.3, 6.3 |
| 13 | `fs_read` / deny | `**/.env`, `**/.env.*` (excluding `.env.example`, `.env.sample`, `.env.template`) | Environment files usually hold credentials and connection strings; keep them out of prompts. A single `fs_read` deny blocks all read tools (read, glob, grep, code) for the path | 11.1 |
| 14 | `fs_read` / deny | `**/*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`, `**/id_rsa*`, `id_ecdsa*`, `id_ed25519*`, `secrets/**`, `**/secrets/**`, `~/.ssh/**`, `~/.aws/credentials`, `~/.aws/sso/cache/**`, `~/.aws/cli/cache/**`, `~/.kube/config`, `~/.docker/config.json`, `~/.netrc`, `~/.git-credentials`, `~/.npmrc`, `~/.config/gh/hosts.yml` | Private keys, keystores and local credential or token caches must never be read into a prompt (prompts are stored and processed in the Kiro profile region) | 10.2, 11.1, 9.2 |
| 15 | `fs_write` / deny | Key files (`*.pem`, `*.key`, `*.p12`, `*.pfx`), `~/.ssh/**`, `~/.aws/**`, shell start-up files (`~/.bashrc`, `~/.bash_profile`, `~/.profile`, `~/.zshrc`, `~/.zprofile`, `~/.zshenv`), `~/.gitconfig`, `~/.npmrc`, `~/Library/LaunchAgents/**`, `~/.config/autostart/**` | Prevents credential tampering and persistence (start-up files, launch agents, global git config such as `core.hooksPath`) outside the workspace | 11.3, 9.2 |
| 16 | `fs_write` / ask | `**/.github/workflows/**`, `**/.github/actions/**`, `**/.gitlab-ci.yml`, `**/Jenkinsfile`, `**/buildspec*.yml`, `**/azure-pipelines*.yml`, `**/CODEOWNERS`, `**/.pre-commit-config.yaml` | CI/CD definitions and review-ownership files control what runs with pipeline credentials and who must approve; changes need explicit human approval and peer review | 6.3, 7.5 |
| 17 | `fs_write` / ask | `.kiro/steering/**`, `.kiro/skills/**`, `~/.kiro/steering/**`, `~/.kiro/skills/**`, `**/AGENTS.md` | Steering, skills and `AGENTS.md` change how the agent behaves in later sessions; a prompt-injected agent must not be able to rewrite its own instructions silently. (Kiro already asks for agents, hooks, workflows and powers directories.) | 7.5, 6.3 |
| 18 | `web_fetch` / ask | all URLs | Every fetch is visible to the developer; fetched pages can carry prompt-injection content and URLs can carry data out. If web tools are disabled in the Kiro console, this rule is redundant but harmless | 11.1, 11.2 |
| 19 | `web_search` / ask | all queries | Search queries can leak code or customer context to an external search provider | 11.1 |

Optional stricter rules (not enabled by default): `{"capability": "mcp", "effect": "ask"}` forces a prompt for every MCP tool call, even when users or `autoApprove` allow it; `{"capability": "web_fetch", "exclude": ["docs.aws.amazon.com", "kiro.dev"], "effect": "deny"}` turns rule 18 into a domain allow list (excluded domains fall through to the user's own rules).

## How admin rules combine with other permission sources

- **Deny-overrides.** Kiro evaluates the Kiro (hardcoded), administration, user, workspace, agent and session scopes together. The result is `deny > ask > allow`, regardless of scope. Admin rules may only use `deny` or `ask`: they restrict but never grant.
- **Session overrides cannot weaken admin rules.** `kiro-cli --trust-all-tools`, `/tools trust-all` (CLI V3), "Always allow … This session", policy presets requested by ACP clients, user `permissions.yaml` and agent `permissions` rules are all allow sources. They remove Kiro's default prompts, but an admin `deny` still blocks and an admin `ask` still prompts. Denials show the rule source as "administration".
- **Headless runs** (no interactive client) treat every `ask` as `deny`. A pipeline that runs Kiro headless therefore cannot push, publish, deploy or fetch under this policy. That is intended.
- **Kiro hardcoded invariants** (cannot be configured): the agent is always denied writes to `~/.kiro/settings/`, `.kiro/settings/`, `~/.kiro/workspace-roots/`, an installed Power's `mcp.json` and Kiro's state stores, so it cannot edit its own permission or MCP files. Writes to `.git/**`, `.vscode/**`, `**/*.code-workspace`, `.kiroignore` and the agents, hooks, workflows and powers directories under `.kiro` and `~/.kiro` always ask; no allow rule from any scope removes that prompt.
- **IDE autonomy.** `kiroAgent.agentAutonomy` (Autopilot or Supervised) decides whether the IDE proceeds or prompts; the permission rules apply after that decision. Supervised mode does not replace admin rules, and Autopilot does not bypass them.

## Failure behaviour

| Part of the file | Behaviour on error | Examples |
|------------------|--------------------|----------|
| Permission rules | **Fails closed.** The whole file is rejected and **all tool calls are denied** until it is fixed or removed | Malformed JSON; any rule with `"effect": "allow"`; unknown fields (for example `effct`); a BOM or UTF-16 encoding |
| Permission rules: unknown capability | That rule is skipped with a warning; the other rules load | A capability name added in a newer Kiro version |
| Sign-in controls | **Fail open.** The restriction is dropped and every sign-in method is offered (a warning names the cause) | Invalid or unreadable file; effect other than `deny`; unrecognized name in `exclude`; rules that deny every method; more than 16 entries in a rule |
| Settings keys | Invalid value dropped on its own; unknown keys ignored | Non-https URL; value over 2,048 characters |

An invalid file therefore removes the sign-in restriction **and** blocks the agent's tools at the same time. Validate before every deployment and monitor for the warning.

## Client-side enforcement

Kiro documents both permission policies and sign-in controls as **enforced by the installed client**: they "can be circumvented by users, e.g., via administrative access to their local machine". Treat them as strong guardrails, not as a boundary:

- Developers work as standard users (no local admin or root), ideally on a managed VDI such as Amazon WorkSpaces.
- MDM keeps the file in place and reports drift; file-integrity monitoring alerts on changes.
- The real boundaries stay outside Kiro: Git server branch protection and required reviews, least-privilege IAM roles for developers, egress filtering (see `cdk/` network stack), and subscription management in the IdP and Kiro console.
- Kiro Web (Cloud Sessions) and devices without the file are not covered. Keep Cloud Sessions off.

## Workspace trust

Kiro treats a workspace as untrusted until the user trusts it, and stores the decision outside the repository, so a repository cannot trust itself. While a workspace is untrusted Kiro does not load its custom agents, steering, MCP configuration, skills or workflow files; asks before every shell command (even if a rule allows it), before every MCP tool call and Power activation (even with `autoApprove`); and refuses writes to `~/.kiro/memories/` and the session store. Admin rules still apply in untrusted workspaces.

Guidance: trust only repositories from your organization's Git server after review; open third-party code, pull requests from forks and downloaded samples untrusted; do not grant a blanket `fs_write` allow (no `match`) in user `permissions.yaml`, because that is the one rule that lifts the untrusted-only `.kiro` write prompts.

## Glob limitations

Glob rules match the command text, not its effect. They stop the obvious forms and make intent explicit, but they can be evaded, for example:

- quoting or escaping: `r""m -rf /`, `\rm -rf /`, `command rm -rf /`, `env rm -rf /`;
- options before the subcommand: `git -c color.ui=false push --force`, or combined flags such as `git push -uf`;
- indirection not listed here: shell variables (`X=rm; $X -rf /`), aliases, `npm run <script>` or `make` targets that run the denied command, a script file written by the agent and then executed.

Defense in depth therefore continues after this file: PreToolUse hooks in [`../agent-hooks/`](../agent-hooks/) inspect the full tool input (and block with exit code 2, including on internal errors), and OS/VDI controls, server-side branch protection, IAM and egress filtering enforce the outcome regardless of how a command is written.

## Validation

Run from the repository root before every change and in CI:

```bash
# 1. Valid JSON (all files)
jq -e . managed-settings/*.json > /dev/null

# 2. Admin rules use only deny or ask (an allow rule makes Kiro reject the whole file)
jq -e '[.rules[].effect] | all(. == "deny" or . == "ask")' managed-settings/managed-settings.*.json

# 3. Only the documented keys (unknown fields make Kiro reject the whole file)
jq -e '(keys - ["rules","settings"]) == [] and ([.rules[] | keys[]] - ["capability","match","exclude","effect"]) == []' \
  managed-settings/managed-settings.*.json

# 4. Sign-in rule: effect deny, at most 16 names, https URLs only
jq -e '[.rules[] | select(.capability == "signin_method") | (.effect == "deny" and ((.match // []) + (.exclude // []) | length) <= 16)] | all' \
  managed-settings/managed-settings.*.json
jq -e '[(.settings // {}) | to_entries[] | select(.key | endswith("_url")) | .value | startswith("https://")] | all' \
  managed-settings/managed-settings.*.json

# 5. No UTF-8 BOM (first byte must be "{")
for f in managed-settings/*.json; do [ "$(head -c 1 "$f")" = "{" ] || echo "BOM or bad start: $f"; done

# 6. User template parses as YAML
ruby -ryaml -e 'YAML.load_file("managed-settings/permissions.banking.yaml")'

# 7. Registry: exact versions only (no ^, ~, >=, x or * ranges)
jq -e '[.servers[].server.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")] | all' managed-settings/mcp-registry.example.json
```

Then verify on a pilot machine: restart Kiro, confirm that no policy warning appears, ask the agent to run a denied command (for example `git push --force`) and confirm the denial names "administration", sign out and confirm that only the permitted sign-in method is offered with the start URL and Region prefilled.

## User permissions template

[`permissions.banking.yaml`](permissions.banking.yaml) is the user scope (`~/.kiro/settings/permissions.yaml`). Users copy it themselves, or MDM places it in each profile (the agent itself can never write `~/.kiro/settings/`). Its allow rules only remove prompts for low-risk local work; every admin deny/ask above still applies. Workspace-scope rules are created through the "Always allow … This workspace" picker and stored per user outside the repository in `~/.kiro/workspace-roots/<hash>/permissions.yaml`, so a cloned repository cannot inject rules. In the CLI, convert legacy agent `toolsSettings` with `kiro-cli agent migrate` (or `/upgrade-agent`); `autoAllowReadonly` and `denyByDefault` have no equivalent in the new model.

## MCP registry example

[`mcp-registry.example.json`](mcp-registry.example.json) follows the registry file format on the official MCP governance page (a subset of the MCP registry standard v0.1 server schema) and validates against the JSON schema published there.

- **Entries:** `aws-documentation` (local stdio server from PyPI, run with `uvx`) and `bank-internal-standards` (remote `streamable-http` server). Both versions (`1.2.3`, `1.0.0`) are **examples**: replace them with the exact versions your third-party review approved. Version ranges (`^1.2.3`, `~1.2.3`, `>=1.2.3`, `1.x`, `1.*`) are rejected.
- **Hosting:** serve the file over HTTPS with a certificate from a trusted CA (self-signed certificates are rejected). The URL may be private to the corporate network. Enter it in Kiro console > Settings > Shared settings > MCP Registry URL, with MCP turned on.
- **Behaviour:** Kiro fetches the registry at startup and every 24 hours. A locally installed server that is no longer listed is terminated; a server with a different version is relaunched at the registry version. Servers not in the registry are hidden, including entries in the user's own `mcp.json`. Users can only add environment variables, HTTP headers, a timeout, the server scope and tool trust on top of a registry entry.
- **Who it applies to:** IAM Identity Center and API-key users, in the IDE and CLI. It does not apply to Builder ID or social sign-in users, or to Kiro Web. If the client cannot reach the governance API, MCP **fails closed** (MCP disabled until it reconnects). Like the permission policy, it is client-enforced.
- **Runners:** clients need `npx` (npm), `uvx` (PyPI) or `docker` (OCI) pre-installed. If you mirror packages internally, set `registryBaseUrl` to the mirror and test how your Kiro version passes it to the runner.
- **Docs conflict:** the user-facing registry page refers to `~/.kiro/mcp.json` and `.kiro/mcp.json`, while the MCP configuration page documents `~/.kiro/settings/mcp.json` and `.kiro/settings/mcp.json`. This repository follows the configuration page. `C:\ProgramData\Kiro\mcp.json` is not a Kiro location.

See [`../kiro-docs/mcp-security.md`](../kiro-docs/mcp-security.md) and [`../kiro-docs/permissions-and-managed-settings.md`](../kiro-docs/permissions-and-managed-settings.md) for the reference snapshots.

## Official references (verified 2026-10-08)

- Permissions: https://kiro.dev/docs/permissions/
- Permission policies (managed-settings.json): https://kiro.dev/docs/enterprise/governance/permissions/
- Sign-in controls: https://kiro.dev/docs/enterprise/governance/sign-in/
- MCP governance and registry file format: https://kiro.dev/docs/enterprise/governance/mcp/
- MCP registry (user view): https://kiro.dev/docs/mcp/registry/
- MCP configuration: https://kiro.dev/docs/mcp/configuration/
- Enterprise governance overview: https://kiro.dev/docs/enterprise/governance/
- Managed updates: https://kiro.dev/docs/enterprise/managed-updates/
