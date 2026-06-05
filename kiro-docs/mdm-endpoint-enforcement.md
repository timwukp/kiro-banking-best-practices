# MDM / Endpoint-Managed Enforcement

Extends the enforcement boundary in `kiro-docs/agent-runtime-governance.md` with a
**control plane** (an MDM platform) that pushes the **global** security controls to every
Kiro client (CLI + IDE) across Windows / macOS / Linux / VDI, and **re-applies them on a
schedule** so they are tamper-proof and self-healing.

## Why MDM (not just local file ACLs)

`agent-runtime-governance.md` makes the managed files root-owned and read-only on a single
host. MDM adds three things a single host cannot:

1. **Central control plane** — one canonical version of the hooks/steering/agent/settings.
2. **Cross-OS push** — the same policy lands on Windows, macOS, Linux, and WorkSpaces VDI.
3. **Self-healing** — a periodic re-apply restores anything a user deleted or edited
   (the same pattern as Kiro's 24-hour MCP registry sync, extended to all control files).

## Global (MDM-managed) vs local (developer-owned)

| Global — pushed, locked, self-healed | Local — developer-owned, NOT locked |
|--------------------------------------|--------------------------------------|
| Security guardrail **hooks**: PII, DLP, credential, `git-guard`, `destructive-fs-guard` (preToolUse) + `audit-logger` (postToolUse) | Project code, workspace `.kiro/specs`, prompts, sessions |
| Global **steering**: org security-policy, code-patterns, prohibited patterns | Project-level steering (additive — cannot override/disable global guardrails) |
| Locked **default agent** (`banking-secure.json`: deny rules + hook wiring + least-privilege) | Project-level agents (bounded by `availableAgents`) |
| Managed **settings**: MCP registry URL, web tools off, model governance, telemetry off | |
| **Launcher/wrapper** (rejects `--trust-all-tools`/`--trust-tools`) + **drift watcher** | |
| **Audit log** (append-only) | |

## Control plane → client

```
MDM platform (Intune / Jamf Pro / Workspace ONE / Kandji)
  canonical hooks + steering + agent + settings (versioned)
        │  push + periodic re-apply (self-heal)
        ▼
  device agent on each client  ──►  root/admin-owned, locked paths
  (Windows / macOS / Linux / VDI)
```

### Per-OS lockdown

| OS | Path | Lockdown |
|----|------|----------|
| Windows | `C:\ProgramData\Kiro\` (admin-owned) | Intune config profile + remediation script; `icacls` grant SYSTEM/Admins Full, Users Read+Execute, **deny DELETE/WRITE** |
| macOS | `/Library/Application Support/Kiro/` (root:wheel) | Jamf config profile; `chflags schg` (system immutable) / SIP-protected location |
| Linux / VDI | `/opt/kiro/` (root:root) | `chattr +i` (immutable) on hooks/agent; `chattr +a` (append-only) on audit; `systemd` drift watcher with `Restart=always` |

## Reference implementation (Linux)

- `mdm/lockdown-linux.sh` — idempotent: deploys the canonical hooks + locked
  agent to a root-owned path, sets `chattr +i` (immutable) on them and `chattr +a`
  (append-only) on the audit log. **Re-running it restores and re-locks** anything that was
  removed or edited — schedule it via the MDM agent / cron / a `systemd` timer for
  self-healing.
- `agent-hooks/destructive-fs-guard.sh` — `preToolUse` hook that blocks repo/workspace
  destruction (`rm -rf` of a root/home/workspace path, deleting `.git`, `find … -delete`,
  `mkfs`/`dd` to a device). Wired into `banking-secure.agent.json`.

The Windows (`icacls` + Intune) and macOS (`chflags schg` + Jamf) equivalents follow the
same deploy-then-immutabilize + self-heal pattern. Per-OS reference scripts:

- Linux/VDI: `mdm/lockdown-linux.sh` (`chattr +i` immutable, `chattr +a` append-only).
- macOS: `mdm/lockdown-macos.sh` (`chflags schg`/`sappnd` as root; `uchg`/`uappnd` otherwise).
- Windows: `mdm/lockdown-windows.ps1` (`icacls`: grant Users Read+Execute, **deny** Delete/Write).

**Windows hooks:** the bash guard hooks run on Linux/macOS; a Windows Kiro client uses
PowerShell hook equivalents — PowerShell ports of the guards are a documented follow-up.

## Protecting against repo/workspace deletion

Two layers, because the workspace must stay writable for the developer:

1. **Via the agent:** `destructive-fs-guard` blocks destructive commands before they run.
2. **Recovery:** rely on backups/snapshots (the repo's CDK `BackupStack` / WorkSpaces
   snapshots) so an accidental or malicious deletion is recoverable.

The **control files** themselves (hooks/agent/audit) are immutable + self-healing, so they
cannot be permanently removed even by a user with shell access.

## Threat model — what this stops, and the honest limit

**Stops:** a developer or compromised process (or the agent itself) **modifying, deleting,
or bypassing** the security hooks/agent/settings; **silently disabling** the audit trail;
and **permanently removing** the controls (self-heal restores them).

**Does NOT provide secrecy.** `kiro-cli` runs **as the developer**, so the same user can
**read** the hook scripts. MDM + immutability gives **anti-tamper / anti-delete /
anti-bypass + self-healing** — not confidentiality. "Executable only by the agent /
unreadable by humans" requires a separate service account or brokered execution, which Kiro
CLI does not natively provide. Document this so the controls are not mistaken for secrecy.

## Testing

OS-enforcement tests (not part of CI — they need root/admin + filesystem-attribute support):

- **Linux** — `mdm/tests/test-lockdown.sh` (`chattr`): immutability blocks
  modify+delete, append-only blocks truncation, self-heal restores, destructive-fs-guard
  blocks. Verified on **Amazon Linux 2023** (root via SSM).
- **macOS** — `mdm/tests/test-lockdown-macos.sh` (`chflags`): same checks; uses
  user-immutable `uchg` so it runs without root. Verified on **macOS (Darwin)**.
- **Windows** — `mdm/tests/test-lockdown-windows.ps1` (`icacls`): asserts the
  BUILTIN\Users **deny Delete/Write** ACE is applied and that self-heal restores. Verified
  on **Windows Server 2022** (SYSTEM via SSM).

`agent-hooks/tests/run-tests.sh` — pure-bash hook tests (incl. `destructive-fs-guard`),
green on macOS and Linux (CI runs the pure-bash subset).

Sanitized results for all three platforms: `kiro-docs/mdm-test-evidence.md`.

## Adversarial validation (chaos test)

A non-privileged red-team harness (`security-tests/chaos/run-chaos.sh`; 4 runs, no sudo)
confirmed the OS-layer controls **hold against a human in a plain shell, not just the Kiro
agent**: immutable hooks could not be modified or deleted, the immutable bit could not be
cleared, the append-only audit could not be truncated, the root-owned command guard could not
be replaced, `sudo` failed, and root-owned "production" could not be deleted — **0 unexpected
bypasses**. The expected limitation — invoking a binary by absolute path or shipping your own
bypasses a `PATH` command guard — requires **application allow-listing** to fully close. Full
report: `kiro-docs/chaos-pentest-evidence.md`. A follow-up hardened run closed **4 of the 6**
endpoint gaps locally (`noexec` application control, fixed/managed audit path, `denyByDefault`
allow-list, least-privilege data access); the two residuals — force-push via an approved
binary and obfuscated-content detection — are anchored **server-side** (branch protection) and
via **DLP/egress + least-privilege**, respectively.

## MAS TRM mapping

| MAS TRM | Covered by |
|---------|------------|
| 9 / 9.1 — Access control | locked agent, bypass rejection, immutable controls |
| 11.1 — Data security | PII/DLP/credential hooks, `write.deniedPaths` |
| 11.2 — Network security | MCP registry allow-list (managed setting) |
| 12 / 15 — Cyber-sec ops / IT audit | append-only audit, drift detection, self-heal |

## References

- `kiro-docs/agent-runtime-governance.md` — the runtime controls this layer hardens.
- `kiro-docs/security-governance-features.md` — enterprise/registry governance.
- Kiro CLI settings & hooks: https://kiro.dev/docs/cli/reference/settings/
