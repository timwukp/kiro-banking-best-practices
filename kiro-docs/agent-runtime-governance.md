# Agent Runtime Governance (Kiro CLI)

Layer 4 (Application) expansion of the Security Architecture in the root `README.md`.
This document adds runtime controls on the Kiro CLI agent itself — what it may read,
write, and execute during a session — to complement the environment controls (identity,
network, VDI, MCP allowlist, audit).

## Why this layer

The 5-layer model secures everything *around* Kiro. On its own it does not constrain what
the agent does *at runtime*: reading `.env`/credential files, running destructive shell
commands, pushing to protected branches, or emitting sensitive data into tool inputs.
This layer closes that gap with two native Kiro mechanisms:

1. **Agent configuration `toolsSettings`** — declarative allow/deny rules for paths and commands.
2. **The hook system** (`preToolUse` / `postToolUse`) — scripts that can **block** a tool call (exit code 2) or record it.

## Enforcement boundary — read this first

Kiro CLI has **no un-removable "managed settings" layer**. A workspace
`.kiro/agents/<name>.json` overrides a global agent of the same name, and there is no
agent inheritance or composition. Steering files are **guidance**, not an enforced
boundary.

Therefore, for regulated (MAS TRM) deployments, un-removable enforcement MUST be applied
at the **OS layer on the Amazon WorkSpaces VDI** — the same control this guide already
mandates for `mcp.json`:

- `~/.kiro/agents/`, `~/.kiro/steering/`, and `~/.kiro/settings/cli.json` are
  **root/Administrator-owned and read-only to the developer**.
- Hook scripts live in a root-owned path (e.g. `/opt/kiro/hooks/`, mode `0755`, owner
  `root`) so a developer cannot modify or remove them.
- A drift watcher alarms on any change to these files (see Deployment).

Without this OS-layer control, the runtime controls below are advisory only.

## Control mapping

| # | Control | Kiro mechanism | Stops | MAS TRM |
|---|---------|----------------|-------|---------|
| 1 | Command & path deny rules | `toolsSettings.shell.deniedCommands`, `write.deniedPaths`, `shell.denyByDefault` | `rm -rf`, `curl`/`wget` exfiltration, writes to `.env`/secrets | 9, 11.1 |
| 2 | Least-privilege tools | `tools` + `allowedTools` | Agent uses only explicitly granted tools | 9.1 |
| 3 | PII / secret pre-flight | `preToolUse` hook `pii-guard.sh` (exit 2 blocks) | PII/credentials in tool inputs | 11.1, PDPA |
| 4 | Git policy | `preToolUse` hook `git-guard.sh` (matcher `shell`) | Force-push, push to protected branch, `reset --hard`, `clean -f` | 6, 9 |
| 5 | Tamper-evident tool-use audit | `postToolUse` hook `audit-logger.sh` -> hash-chained JSONL -> CloudWatch agent | Audit gaps / silent tampering | 12, 15 |
| 6 | Bypass-flag rejection | OS wrapper on `kiro-cli` rejecting `--trust-all-tools` / `--trust-tools` in prod | Developers disabling approval prompts | 9 |
| 7 | Config drift detection | inotify/fswatch on agent/steering/settings + CloudWatch alarm | Tampering with managed config | 12, 15 |
| 8 | MCP server allowlist | `mcpServers` (explicit) + `disabledTools` | Unapproved MCP servers/tools (ties to existing MCP Governance) | 11.2 |

## Reference agent configuration

A locked-down agent is provided at `agent-hooks/banking-secure.agent.json`. Deploy it as
the global default so every session inherits it:

```bash
# On the VDI golden image (root-owned, developer-read-only):
install -m 0755 -o root agent-hooks/pii-guard.sh    /opt/kiro/hooks/pii-guard.sh
install -m 0755 -o root agent-hooks/git-guard.sh    /opt/kiro/hooks/git-guard.sh
install -m 0755 -o root agent-hooks/audit-logger.sh /opt/kiro/hooks/audit-logger.sh
install -m 0644 -o root agent-hooks/banking-secure.agent.json ~/.kiro/agents/banking-secure.json
kiro-cli agent set-default banking-secure
```

Key fields (see the file for the full config):

- `tools` grants the working set; `allowedTools` auto-approves only read-only tools, so
  every `write`/`shell` call is gated.
- `toolsSettings.write.deniedPaths` blocks `.env`, `secrets/`, `~/.aws`, `~/.ssh`.
- `toolsSettings.shell.deniedCommands` blocks `rm -rf`, `sudo`, `curl`/`wget`, force-push,
  `reset --hard`, and `aws iam`/`sts`/`secretsmanager`.
- `hooks` wire the three guards below.

## Hooks

All three follow the Kiro hook contract: the JSON event arrives on **STDIN**; a
`preToolUse` hook returns **exit 2 to block** the call (its STDERR is shown to the model),
exit 0 to allow.

- `agent-hooks/pii-guard.sh` — `preToolUse`, matcher `*`. Scans the whole tool input for
  credit-card numbers, AWS access keys, PEM private keys, Singapore NRIC/FIN, and
  `password`/`secret`/`api_key` assignments. Blocks on match. Patterns are deliberately
  broad (fail-safe) and tunable per institution.
- `agent-hooks/git-guard.sh` — `preToolUse`, matcher `shell`. Blocks force-push, push to
  `main`/`master`, `git reset --hard`, and `git clean -f`. Normal commits and
  feature-branch pushes pass through.
- `agent-hooks/audit-logger.sh` — `postToolUse`. Appends a SHA-256 hash-chained JSONL
  record (timestamp, `KIRO_SESSION_ID`, tool name, previous hash) so the audit trail is
  tamper-evident. The CloudWatch agent on the VDI tails the file to ship records to
  CloudWatch Logs (Layer 5).

### Relationship to the `pii-detection` skill

This repo already ships a `pii-detection` skill (`.kiro/skills/pii-detection/`). A skill
*advises* the model; it cannot stop a tool call. `pii-guard.sh` is the **enforcement**
counterpart. Use both: the skill for developer guidance, the hook for a hard gate.

## Deployment on the WorkSpaces VDI

1. Bake hooks + agent config into the golden image at root-owned paths (see above).
2. Make `~/.kiro/agents`, `~/.kiro/steering`, and `~/.kiro/settings/cli.json` read-only to
   the developer (file ACL / GPO). This is the un-removable enforcement boundary.
3. Wrap `kiro-cli` so `--trust-all-tools` / `--trust-tools` are rejected in production.
4. Run a drift watcher (inotify on Linux / fswatch on macOS) over the managed paths and
   alarm to CloudWatch on change.
5. Point the CloudWatch agent at the audit log (`$KIRO_AUDIT_LOG`, default
   `~/.kiro/audit/tool-use.jsonl`).

## Testing

A pure-bash harness validates the hooks with no kiro-cli dependency:

```bash
bash agent-hooks/tests/run-tests.sh
# RESULT: PASS=... FAIL=0
```

It asserts: pii-guard blocks card/AWS-key/PEM-key/NRIC/secret and allows clean code;
git-guard blocks force-push + protected-branch push + `reset --hard` and allows
`git status` / feature pushes; audit-logger writes an appended, hash-chained record; and
`banking-secure.agent.json` is valid (plus `kiro-cli agent validate` when the binary is
present). Verified on macOS (dev) and Amazon Linux (EC2).

## MAS TRM mapping

| MAS TRM | Covered by |
|---------|------------|
| 6 — Security-by-design / SDLC | git-guard (branch protection) |
| 9 / 9.1 — Access control | least-privilege `tools`/`allowedTools`, command deny rules, bypass rejection |
| 11.1 — Data security | pii-guard, `write.deniedPaths` |
| 11.2 — Network security | MCP allowlist (`mcpServers`) |
| 12 / 15 — Cyber-sec ops / IT audit | audit-logger (hash-chained) + CloudWatch + drift detection |

## References

- Security Architecture: see the root `README.md` (Security Architecture section).
- Kiro CLI settings & hooks: https://kiro.dev/docs/cli/reference/settings/
- Companion enterprise kit (concepts adapted here): https://github.com/timwukp/claude-code-on-aws-bedrock-best-practices
