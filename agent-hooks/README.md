# agent-hooks — Kiro hook scripts (defense in depth)

These hooks are a **secondary** runtime control. The primary controls are:

1. **Admin policy** — [`managed-settings/`](../managed-settings/README.md) deployed by MDM to the official
   `managed-settings.json` path (deny/ask rules evaluated by the Kiro client; compound shell commands are
   split and each part is checked).
2. **Server-side branch protection / rulesets** on your Git host (the only control that cannot be bypassed
   from a developer workstation).

The hooks add content inspection that permission globs cannot do (secrets and personal data in tool input),
a second check for history-destroying git operations, and a supplementary local audit trail.

| File | Trigger / matcher | Purpose | MAS TRM |
|---|---|---|---|
| `pii-guard.sh` | PreToolUse, `*` | Block tool input containing private keys, AWS/GitHub/Anthropic credentials, password assignments, Singapore NRIC/FIN (S/T/F/G/M) or card numbers | 11.1 |
| `git-guard.sh` | PreToolUse, shell (`execute_bash`) | Block force-push, `+`/`:` refspecs, pushes to `main`/`master`, `reset --hard`, `clean -f`, `branch -D`, history rewrites | 6.3, 7.5 |
| `destructive-fs-guard.sh` | PreToolUse, shell (`execute_bash`) | Block recursive deletion of `/`, `~`, `$HOME`, `.`, `..`, system directories or `.git`; moving `.git`; `find -delete` / `-exec rm`; `mkfs`; `dd` to a device | 11.3 |
| `audit-logger.sh` | PostToolUse, `*` | Append a hash-chained JSONL record (SHA-256 of the input, never the raw input) | 12.2 |
| `banking-secure.agent.json` | — | Kiro CLI custom agent: `permissions.rules` + embedded hooks + resources (AGENTS.md, steering, skills) | — |
| `hooks/banking-guards.json` | — | The same hooks in the v1 hook-file format (IDE 1.0+ and CLI V3) | — |
| `SHA256SUMS` | — | Pinned hashes of the four scripts; `mdm/` verifies them before deploying | — |

## Two configuration formats

- **v1 hook files** (`hooks/banking-guards.json`) — Kiro IDE 1.0+ and the CLI V3 engine load hook files from
  `~/.kiro/hooks/` (global) and `.kiro/hooks/` (workspace). Matchers use categories (`shell`, `write`, `*`);
  `timeout` is in seconds.
- **CLI custom agent** (`banking-secure.agent.json`) — hooks embedded in the agent (`preToolUse` /
  `postToolUse`, matchers use tool names such as `execute_bash`, `timeout_ms`). Kiro loads agents only from
  `~/.kiro/agents/` and the workspace `.kiro/agents/` (workspace wins on a name clash). The deprecated
  `toolsSettings` block was replaced by `permissions.rules`.

## Deployment

The scripts are referenced by absolute path:

| OS | Script directory | Deployed by |
|---|---|---|
| Linux | `/opt/kiro/hooks/` | `mdm/lockdown-linux.sh` (root-owned, 0755, after `SHA256SUMS` verification) |
| macOS | `/Library/Application Support/Kiro/hooks/` | `mdm/lockdown-macos.sh` (rewrites `/opt/kiro/hooks` in the deployed copies) |
| Windows | `C:\ProgramData\Kiro\hooks\` | Requires Git Bash or WSL; on Windows rely on `managed-settings.json` |

Requirements: `bash`, `jq`, `awk`, `sed`, `grep`, and `shasum` or `sha256sum`.

## Exit-code contract

- stdin is the hook event JSON: `{"hook_event_name","cwd","session_id","tool_name","tool_input":{...}}`
  (`postToolUse` adds `tool_response`).
- `exit 0` allows; `exit 2` blocks and returns stderr to the model.
- **Docs conflict:** newer Kiro pages say only exit 2 blocks and any other non-zero code is treated as an
  error (the call proceeds); an older IDE page says any non-zero code blocks. The guards therefore map every
  failure — empty or invalid input, missing `jq`, an internal error — to **exit 2** (fail closed).
- `audit-logger.sh` never blocks (always exit 0).

## Limitations (read before relying on the hooks)

- Pattern-based. Commands are normalized (shell `-c` wrappers, quotes, compound commands, `git -C/-c`
  options) but deliberate obfuscation — variables, aliases, scripts written to disk and then run, other
  interpreters — can evade them. That is why the admin policy and server-side branch protection are primary.
- `pii-guard.sh` is broad by design; expect occasional false positives (for example, 16-digit IDs).
- A developer with local administrator rights can remove hooks and policy files. MDM detects drift by
  re-running and comparing hashes; it cannot prevent an administrator from changing the machine.
- The audit chain is tamper-evident only against casual edits (no secret key). The authoritative audit trail
  is Kiro prompt logging and user activity reports (S3, profile region) plus CloudTrail.

## Tests

```bash
bash agent-hooks/tests/run-tests.sh          # exact exit codes for every fixture, fail-closed and audit checks
(cd agent-hooks && shasum -a 256 -c SHA256SUMS)
```

Fixtures live in `tests/fixtures/` (`git-fs-cases.tsv`, `pii-cases.tsv`). Add a row for every new bypass you
find; rows marked `known_gap` in the fourth column are skipped and counted.

After changing a script, regenerate the hashes:

```bash
cd agent-hooks && shasum -a 256 audit-logger.sh destructive-fs-guard.sh git-guard.sh pii-guard.sh > SHA256SUMS
```
