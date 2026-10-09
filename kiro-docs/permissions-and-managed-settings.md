# Kiro Permissions, Managed Settings, Hooks and Custom Agents (Reference Snapshot)

> **Source:** kiro.dev: [Permissions](https://kiro.dev/docs/permissions/) (updated 2026-10-01), [Permission policies](https://kiro.dev/docs/enterprise/governance/permissions/) (2026-09-12), [Sign-in controls](https://kiro.dev/docs/enterprise/governance/sign-in/) (2026-09-30), [Hooks](https://kiro.dev/docs/hooks/) and [Hook triggers](https://kiro.dev/docs/hooks/types/) (2026-09-30), [Hook actions](https://kiro.dev/docs/hooks/actions/) (2026-08-04), [Custom agents](https://kiro.dev/docs/custom-agents/) (2026-09-02) and the [configuration reference](https://kiro.dev/docs/custom-agents/configuration-reference/) (2026-10-02).
> **Last verified:** 2026-10-08.
>
> Condensed, banking-oriented snapshot for offline use. Where official pages conflict, the newer page is followed and the conflict is noted. Deployable files that implement this reference are in [`../managed-settings/`](../managed-settings/) and [`../agent-hooks/`](../agent-hooks/).

## 1. Applicability

| Feature | Kiro IDE | Kiro CLI |
|---------|----------|----------|
| Capability-based permissions (`permissions.yaml`) | 1.0+ (GA 2026-06-25) | V3 engine (`kiro-cli --v3`), shipped in CLI 2.x; there is no CLI 3.x binary |
| Admin permission policies (`managed-settings.json`) | Minimum version not stated; requires the 1.x permission system. Verify on your version | Same (V3 engine) |
| Sign-in controls (same file) | 1.2+ | 2.25.0+ |
| v1 hook files (`.kiro/hooks/*.json`) | 1.0+ | V3 engine |
| Kiro Web | Not applicable: Web runs in an isolated cloud sandbox; `permissions.yaml`, admin policies and sign-in controls do not apply | |

Latest versions on 2026-10-08: IDE 1.2.37 (2026-10-05), CLI 2.28.0 (2026-10-05).

## 2. Permissions (`permissions.yaml`)

The capability-based model replaces the IDE 0.x Trusted Commands and Command Denylist (IDE 1.0 breaking change: trusted command prefixes become `allow` rules and denylist entries become `deny` rules; `kiroAgent.trustedCommands` and `kiroAgent.commandDenylist` are no longer used).

**Rule keys:** `capability` (required), `match` (globs, optional = all resources), `exclude` (globs that must not match), `effect` (`deny` | `ask` | `allow`).

**Capabilities:** `fs_read`, `fs_write`, `shell`, `web_fetch`, `web_search`, `mcp`, `subagent`, `skill`, `power`, `context`, `diagnostics`, `sandbox_network`. Meta-capabilities: `all`, `builtin` (all built-in tools), `filesystem` (`fs_read` + `fs_write`). `sandbox_network` is not part of `all`.

**Scopes** (all evaluated together, deny-overrides: `deny > ask > allow`; no precedence between scopes, the most restrictive effect wins):

| Scope | Location | Effects allowed |
|-------|----------|-----------------|
| Kiro | Hardcoded invariants | deny, ask |
| Administration | `managed-settings.json` (section 3) | deny, ask |
| User | `~/.kiro/settings/permissions.yaml` | deny, ask, allow |
| Workspace | `~/.kiro/workspace-roots/<hash>/permissions.yaml` (per user, outside the repository; a cloned repo cannot inject rules) | deny, ask, allow |
| Agent | `permissions` field of an agent profile | deny, ask, allow |
| Session | In-memory consent decisions; policy presets requested by ACP clients | deny, ask, allow |

**Pattern syntax**

- `fs_read` / `fs_write`: `*` within one path component, `**` across separators, `{a,b}` and `[abc]` supported; a pattern without wildcards also matches children (`~/temp` matches `~/temp/child`).
- `shell`, `web_fetch`, `mcp`: `*` matches any sequence of characters; `**`, `?` and character classes are not supported. MCP patterns are `<server>/<tool>`.
- Globs only, no regular expressions.
- Shell commands are parsed first: compound commands (`;`, `&&`, `||`, `|`) are split and each sub-command is evaluated independently.

**Defaults without any file:** silent `fs_read` on `./**`, common read-only git commands (`git status`, `git log`, `git diff`, `git branch` …), system-info commands (`pwd`, `whoami`, `uname` …) and utility tools; everything else prompts. A `permissions.yaml` adds to these defaults.

**Kiro hardcoded invariants**

- Always denied: writes to `~/.kiro/settings/`, `.kiro/settings/`, `~/.kiro/workspace-roots/`, an installed Power's `~/.kiro/powers/installed/<name>/mcp.json`, and Kiro state stores (`~/.kiro/sandbox-state/`, `~/.kiro/web-session/`, `~/.kiro/cloud-cache/`, `~/.kiro/sandbox-curl/`).
- Always ask (trusted or not; no allow rule removes the prompt): writes to `.git/**`, `.vscode/**`, `**/*.code-workspace`, `.kiroignore`, and the agents, hooks, workflows and powers directories of the workspace `.kiro` and of `~/.kiro`.
- Ask while the workspace is untrusted: writes to `.kiro/steering`, `.kiro/skills`, `.kiro/extensions` and any undeclared `.kiro` directory.

**Headless:** with no interactive client, every `ask` is treated as `deny`.

**IDE autonomy:** `kiroAgent.agentAutonomy` = `Autopilot` (proceed with allowed operations) or `Supervised` (prompt before any action). The permission layer applies after the autonomy decision.

**Interactive approvals:** Allow / Always allow / Deny / Always deny. "Always allow" saves to all workspaces (user file), this workspace (workspace-roots file) or this session. Chained commands are approved sub-command by sub-command.

**CLI session overrides:** `--trust-all-tools` still works as a session-scope override, and V3 adds `/tools trust-all` (CLI 2.24.0) and `/tools untrust <tool>`. These are allow sources and cannot override an admin `deny` or `ask`.

**Official example:**

```yaml
rules:
  - capability: shell
    effect: allow
    match: ["npm *"]
    exclude: ["npm publish*"]
  - capability: fs_read
    effect: deny
    match: ["**/.env", "**/.env.*", "secrets/**", "**/*.pem"]
```

## 3. Admin policy (`managed-settings.json`)

| OS | Path |
|----|------|
| macOS | `/Library/Application Support/Kiro/managed-settings.json` |
| Windows | `C:\ProgramData\Kiro\managed-settings.json` (UTF-8 **without** BOM; Windows PowerShell `Out-File` writes UTF-16 by default, which Kiro rejects) |
| Linux | `/etc/kiro/managed-settings.json` |

- Paths require administrator/root to modify. Deploy with MDM (Jamf, Kandji, Intune), Group Policy or SCCM. Restart Kiro to apply.
- One file serves every Kiro surface on the machine (IDE and CLI). Administration scope is for enterprise plans.
- Schema: `{"rules": [ ... ], "settings": { ... }}`. Keep `"rules": []` even if only settings are used. Rule fields: `capability` (required), `match`, `exclude`, `effect` (required; `deny` or `ask` only).
- **Validation (permission rules fail closed):** malformed JSON → whole file rejected, all tool calls denied until fixed or removed; `"effect": "allow"` → whole file rejected (same result); unknown fields → whole file rejected; unknown capabilities → rule skipped with a warning (forward compatibility).
- A denial caused by the policy names the rule source "administration"; the user is told their own settings cannot override it.
- **Client-side enforcement:** "can be circumvented by users, e.g., via administrative access to their local machine."

Official examples:

```json
{ "rules": [ { "capability": "web_fetch", "effect": "deny" }, { "capability": "shell", "match": ["rm *", "sudo *"], "effect": "deny" } ] }
```

```json
{ "rules": [ { "capability": "web_fetch", "exclude": ["docs.aws.amazon.com", "*.amazonaws.com", "*.github.com"], "effect": "deny" } ] }
```

The second example denies every domain except the excluded ones; excluded domains fall through to the user's own rules.

## 4. Sign-in controls (same file)

- Rule: `{"capability": "signin_method", "match": ["*"], "exclude": ["<kept methods>"], "effect": "deny"}`. Effect must be exactly `deny`; anything else (including `allow`, `ask`, `Deny`) makes Kiro ignore the restriction with a warning. At most 16 entries across `match` and `exclude`. If several rules exist, a method denied by any of them is denied.
- Method names (case-sensitive): `idc`, `external_idp`, `builder_id`, `google`, `github`, `social` (Google and GitHub). Screen labels and internal identifiers (`awsidc`, `builderid`) are not valid.
- Settings keys (optional, strings ≤ 2,048 characters, URLs must be https): `idc_start_url`, `idc_region`, `external_idp_domain`, `external_idp_start_url`, `external_idp_region` (without it Kiro looks up the organization across Regions), `signin_help_url` (rendered by the client only, so an internal URL is fine).
- Read when a sign-in starts (next sign-in). The client re-checks the method when the browser returns and refuses a denied method before a token is issued.
- **Fail open:** an invalid/unreadable file, a BOM, non-UTF-8 encoding, rules that deny every method or none, unrecognized `exclude` names or more than 16 entries drop the restriction and offer every method. Because the same file carries permission policies, an invalid file also blocks the agent's tools. Unknown settings keys are ignored.
- Not applied in Kiro Web or on devices without the file; older clients ignore it. Controlling who can use Kiro remains the job of the IdP and Kiro subscriptions.

```json
{
  "rules": [
    { "capability": "signin_method", "match": ["*"], "exclude": ["idc"], "effect": "deny" }
  ],
  "settings": {
    "idc_start_url": "https://my-org.awsapps.com/start",
    "idc_region": "us-east-1",
    "signin_help_url": "https://it.example.com/kiro-help"
  }
}
```

## 5. Workspace trust

A workspace is untrusted until the user trusts it; the decision is stored outside the workspace, so a repository cannot change its own trust status. While untrusted, Kiro:

- does not load the workspace's custom agents, steering files, MCP server configuration, skills or workflow files;
- asks before every shell command (including background processes), even if a rule allows it; a deny still refuses;
- asks before every MCP tool call and every Power activation, content read or tool call, even if a saved rule or `autoApprove` allows it;
- asks before writes to `.kiro/steering`, `.kiro/skills`, `.kiro/extensions` and undeclared `.kiro` directories;
- refuses writes to `~/.kiro/memories/` and the session store (`~/.kiro/sessions/` by default) and does not let the agent change memories, knowledge bases or remote learnings.

User, administration, agent, session and workspace-roots rules still load. One exception: an `fs_write` allow in the user `permissions.yaml` with no `match` and no `exclude` lifts the untrusted-only `.kiro` write prompts (not the always-ask paths).

**Not documented:** the untrusted list does not mention workspace hook files (`.kiro/hooks/`). Verify on your Kiro version whether hooks from an untrusted repository run, and review `.kiro/hooks/` in third-party repositories before opening them.

## 6. Protected configuration (IDE 1.2)

Kiro asks before the agent changes agent, hook or Power files or `.kiro/workflows/` recipes, even when broader file permissions allow the write.

## 7. Hooks (v1 hook files)

- Locations: `.kiro/hooks/<id>.json` (workspace) and `~/.kiro/hooks/` (global). Any `.json` file name; several hooks per file; active at session start. Replaces the IDE 0.x `.kiro.hook` format and the CLI 2.x hooks embedded in agent config (`kiro-cli agent migrate` converts them).
- Schema: `{"version": "v1", "hooks": [{"name", "description", "trigger", "matcher", "action": {"type": "command" | "agent", "command" | "prompt"}, "timeout", "enabled", "confirm"}]}`. `matcher` is a regular expression on the tool name (tool events) or file path (file events); omitted = always. `timeout` in seconds for command actions (default 60; 0 disables).
- Triggers: `UserPromptSubmit`, `Stop`, `SessionStart`, `SessionEnd` (CLI V3, 2.25.0), `PreToolUse`, `PostToolUse`, `PostFileCreate`, `PostFileSave`, `PostFileDelete`, `PreTaskExec`, `PostTaskExec`, `Manual`, `AgentSpawn` (alias of `SessionStart`). Triggers that can block: `PreToolUse`, `UserPromptSubmit`, `PreTaskExec`.
- Matchers: IDE categories `read`, `write`, `shell`, `web`, `spec`, `*`, plus `@mcp`, `@powers`, `@builtin`; CLI canonical tool names (`fs_read`, `fs_write`, `execute_bash`, `use_aws`) and aliases (`read`, `write`, `shell`, `aws`); CLI 2.28.0 lets V3 hooks match by category. MCP tools appear as `@<server>/<tool>`.
- STDIN (command actions): `{"hook_event_name": "preToolUse", "cwd": "…", "session_id": "…", "tool_name": "…", "tool_input": {…}}`; `postToolUse` adds `tool_response`, `userPromptSubmit` has `prompt`, `stop` has `assistant_response`.

**Exit codes (Hook triggers page, 2026-09-30):**

| Exit code | PreToolUse / UserPromptSubmit / PreTaskExec | Other triggers |
|-----------|---------------------------------------------|----------------|
| 0 | Proceed; STDOUT added to the agent's context | Success; STDOUT added to context |
| 2 | **Block**; STDERR returned to the model | No block; STDERR shown as a warning |
| Any other non-zero | Error, **not** a block: execution proceeds and STDERR is shown as a warning | STDERR warning |

**Docs conflict:** the older Hook actions page (2026-08-04) still says any non-zero exit blocks a Pre Tool Use or Prompt Submit hook. Design guard hooks to exit 2 both on a policy block **and** on any internal failure (missing dependency, parse error, timeout handling) so that they block under either reading.

**CLI 2.x embedded hooks** (legacy agent `hooks` field): triggers `agentSpawn`, `userPromptSubmit`, `preToolUse`, `postToolUse`, `stop`; matchers use internal tool names (`fs_read`, `fs_write`, `execute_bash`, `use_aws`); timeout `timeout_ms` (default 30000). Whether the IDE honours the agent `hooks` field differs between pages and versions; use v1 hook files for the IDE.

## 8. Custom agents

- Locations: `.kiro/agents/<name>.json` or `.md` (workspace; loaded only if the workspace is trusted) and `~/.kiro/agents/<name>.json` or `.md` (global). Nested directories become names such as `team/planner`. If both locations define the same name, the workspace agent wins (with a warning). Agent files placed anywhere else (for example under `/opt` or `/Library`) are not loaded as agents.
- Fields: `name`, `description`, `prompt`, `mcpServers`, `tools`, `excludedTools`, `toolAliases`, `allowedTools`, `permissions` (`{"rules": [...]}`), `resources` (`file://`, `skill://`, knowledge bases), `includeMcpJson`, `includePowers`, `model`, `keyboardShortcut`, `welcomeMessage`, `hooks`.
- MCP precedence for the same server name: agent `mcpServers` > workspace `mcp.json` > user `mcp.json`.
- Kiro Web can invoke committed workspace agents as sub-agents but cannot select one as the primary agent.
- **Docs conflict (resources):** the steering and skills pages say custom agents do not load steering or skills automatically (add `skill://.kiro/skills/*/SKILL.md`), while the configuration reference says custom agents inherit default resources unless `chat.disableInheritingDefaultResources` is set. List the resources you need explicitly.

## 9. `toolsSettings` deprecation

- Configuration reference: `toolsSettings` is "deprecated in CLI 3.0 and IDE 1.0. Use the permissions field"; it is still used for MCP-tool-specific settings and subagent settings. The V3 agent-configuration page says `toolsSettings` is removed in V3.
- Migration (`kiro-cli agent migrate` or `/upgrade-agent`): allowed/denied commands and paths become `permissions.rules`. `autoAllowReadonly` and `denyByDefault` have **no** equivalent; express them as explicit rules.

## 10. Related controls (elsewhere in this folder)

- MCP configuration files, MCP governance and the MCP registry: [`mcp-configuration.md`](mcp-configuration.md), [`mcp-security.md`](mcp-security.md).
- Data location, network endpoints and firewall allowlist: [`privacy-and-security.md`](privacy-and-security.md).
- Changelog-derived feature inventory: [`security-governance-features.md`](security-governance-features.md).
