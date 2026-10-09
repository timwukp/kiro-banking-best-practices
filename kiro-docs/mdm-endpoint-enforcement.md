# MDM Endpoint Enforcement

How to deploy Kiro's admin policy (`managed-settings.json`) and the optional guard hooks to every Kiro client (IDE and CLI) on Windows, macOS, Linux and WorkSpaces VDI with an MDM platform, and how to detect drift. This is the deployment side of layer 4a and 4e in [`agent-runtime-governance.md`](agent-runtime-governance.md).

> **Last verified:** 2026-10-08 against the official Kiro documentation (Permission policies: https://kiro.dev/docs/enterprise/governance/permissions/). Reference scripts: `mdm/lockdown-linux.sh`, `mdm/lockdown-macos.sh`, `mdm/lockdown-windows.ps1`.

## What MDM can and cannot guarantee

- **Resists a developer without administrator rights.** The policy file and the hook scripts are owned by root or Administrators, world-readable, and write-protected (Linux `chattr +i`, macOS `chflags schg`, Windows ACL with a deny for Users). A standard user cannot change or delete them.
- **Does not stop an administrator or root.** Kiro enforces the policy in the client, and the official page says it "can be circumvented by users, e.g., via administrative access to their local machine". An administrator can clear the flags or ACLs and edit or delete the file. Developers must therefore not be local administrators.
- **Detects drift instead of preventing it.** Re-run the MDM job on a schedule: it compares SHA-256 hashes with the source and restores anything changed or deleted. Use the `--check` / `-Check` mode as the MDM detection step (exit 3 on drift) and alert on it.
- **Gives no secrecy.** Kiro and its hooks run as the developer, so the developer can read the hook scripts and the policy. The controls are about integrity, not confidentiality.
- **Covers only managed devices running the Kiro client.** Devices without the file, older clients (for sign-in controls: before IDE 1.2 and CLI 2.25.0) and Kiro Web are not covered. Keep Cloud Sessions off in the Kiro console.

Earlier versions of this page called the controls "tamper-proof" and said they "cannot be removed". That wording was wrong and has been replaced by the statements above.

## What gets deployed

| Item | Linux | macOS | Windows | Owner / lock | Required |
|------|-------|-------|---------|--------------|----------|
| Admin policy `managed-settings.json` | `/etc/kiro/managed-settings.json` | `/Library/Application Support/Kiro/managed-settings.json` | `C:\ProgramData\Kiro\managed-settings.json` (UTF-8 without BOM) | root / Administrators, mode 0644 or Users Read; `chattr +i` / `chflags schg` / ACL deny | **Yes**: the primary control |
| Hook scripts (`--hooks`, `-DeployHooks`) | `/opt/kiro/hooks/` | `/Library/Application Support/Kiro/hooks/` | `C:\ProgramData\Kiro\hooks\` | root / Administrators, 0755; same lock; deployed only after `agent-hooks/SHA256SUMS` verifies | Optional (defense in depth) |
| v1 hook file `banking-guards.json` (`--install-user`) | `~USER/.kiro/hooks/` | `~USER/.kiro/hooks/` (paths rewritten to the macOS hook directory) | Not installed | **User-owned** | Optional |
| Agent `banking-secure.json` (`--install-user`) | `~USER/.kiro/agents/` | `~USER/.kiro/agents/` (paths rewritten) | Not installed | **User-owned** | Optional |
| Hook audit log (`--audit-user`) | `~USER/.kiro/audit/kiro-hooks.jsonl`, `chattr +a` | Same path, `chflags uappnd` (default) or `sappnd` (`--audit-sappnd`) | Not prepared | User-owned file, append-only flag set by root | Optional, supplementary |

Why the per-user files are user-owned: Kiro loads custom agents only from `~/.kiro/agents` and a trusted workspace's `.kiro/agents`, and global v1 hook files only from `~/.kiro/hooks`. An agent file under `/opt` or `/Library` is ignored. Kiro always asks before the **agent** writes to those directories, but the developer can edit or delete the files. The scripts reinstall them on each run and `--check` reports when they differ, but **the guarantee comes from `managed-settings.json`, not from these files**.

Not deployed by these scripts: steering files (guidance only), `mcp.json` (MCP is governed by the console MCP registry, not by locking files), and the user `permissions.yaml` template ([`../managed-settings/permissions.banking.yaml`](../managed-settings/permissions.banking.yaml); MDM may copy it to `~/.kiro/settings/permissions.yaml`, where it remains user-owned).

## Global, per-user and local

| Scope | What | Who can change it |
|-------|------|-------------------|
| Machine (MDM, admin-owned) | `managed-settings.json`; hook scripts | Administrators only; drift detected by MDM |
| Organization (Kiro console) | Model list, MCP governance and registry, web tools, API keys, Cloud Sessions, prompt logging | Kiro administrators |
| Per user (MDM-installed, user-owned) | v1 hook file, `banking-secure` agent, hook audit log, optional `permissions.yaml` | The developer (drift reported) |
| Workspace (repository) | Project code, specs, workspace steering, workspace agents and hooks | Repository contributors; workspace agents, steering, MCP configuration and skills load only after the user trusts the workspace |

`availableAgents` governs subagents only: it limits which agents a session may spawn as subagents (with `trustedAgents`, CLI 1.25.0). It does not stop a developer from creating or selecting a workspace or global agent. Agent choice is not an enforcement point; the admin policy applies to every agent.

## Running the scripts

Every script validates **everything first** (policy JSON, `SHA256SUMS`, user hook files, user accounts) and only then installs anything, so a refusal leaves the machine unchanged. All are idempotent, make no network calls, and support a dry run that needs no root.

```bash
# Linux / VDI image (root)
bash mdm/lockdown-linux.sh --dry-run                          # validate and print the plan (no root)
sudo bash mdm/lockdown-linux.sh                               # policy only (Option A file)
sudo bash mdm/lockdown-linux.sh --option-b                    # direct IdP federation policy
sudo bash mdm/lockdown-linux.sh --hooks --install-user alice  # + hooks, alice's v1 hook file, agent and audit log
sudo bash mdm/lockdown-linux.sh --check --hooks --install-user alice   # detection: exit 3 on drift

# macOS (Jamf Pro, Kandji, Intune; runs as root)
sudo bash mdm/lockdown-macos.sh --hooks --install-user alice
```

```powershell
# Windows (Intune remediation, SCCM or GPO startup script; SYSTEM or elevated Administrator)
powershell -ExecutionPolicy Bypass -File mdm\lockdown-windows.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File mdm\lockdown-windows.ps1
powershell -ExecutionPolicy Bypass -File mdm\lockdown-windows.ps1 -Check   # Intune detection: exit 3 on drift
```

Common options: `--settings FILE` / `-SettingsPath` for another policy file (or `KIRO_MANAGED_SETTINGS_SRC`), `--strict` / `-Strict` to treat warnings such as placeholder values as errors, `--manifest-sha256 HEX` / `-ManifestSha256` to pin the hash of `SHA256SUMS` itself (deliver the pin out of band, for example in the MDM policy). Exit codes: 0 success, 1 usage or environment error, 2 validation refused, 3 drift (check mode).

**Validation before deployment.** The scripts reject a UTF-8 BOM or UTF-16 encoding, malformed JSON, unknown top-level or rule fields, a missing `rules` array, any rule whose effect is not `deny` or `ask` (an `allow` rule would make Kiro reject the whole file and deny every tool call), sign-in rules with more than 16 entries and a non-https `signin_help_url`. Unknown capabilities and placeholder values produce warnings. Hook deployment aborts on any `SHA256SUMS` mismatch, a malformed or unsafe manifest line, a missing manifest, or a user hook file whose command points outside the hook directory or to a script that is not in the manifest.

### Platform notes

- **Linux.** `chattr +i` needs a filesystem that supports it (ext4, XFS); on tmpfs, overlay or NFS the script warns and relies on ownership and mode. The audit log gets `chattr +a`: the developer can append but cannot truncate, overwrite or delete it or clear the flag. The developer still owns `~/.kiro/audit` and can rename it, so the local log is supplementary evidence only.
- **macOS.** `schg` can be cleared by root only at `kern.securelevel` 0; at 1 or higher it needs Recovery or single-user mode, and so does every later MDM update of the file. Use `--no-system-immutable` where that is not acceptable; root ownership and mode 0644 already stop a standard user. The hook directory contains a space, so the rewritten hook commands quote the path; this assumes Kiro passes hook commands to a shell, so verify on a pilot machine or use `--hooks-dest /opt/kiro/hooks`. The default audit flag `uappnd` is a user flag: the owner can clear it with `chflags nouappnd`, so it guards against accidental truncation, not against the developer. `--audit-sappnd` uses the super-user flag instead (the owner cannot clear it; at securelevel 1 or higher neither can root without Recovery mode, which also blocks log rotation).
- **Windows.** The file is written with `[System.IO.File]::WriteAllText(path, text, (New-Object System.Text.UTF8Encoding $false))` and checked for a BOM afterwards. The ACL is rebuilt on every run: owner Administrators, inheritance removed, every other explicit ACE removed (a standard user can pre-create folders under `C:\ProgramData` and plant ACEs), SYSTEM and Administrators Full Control, Users Read (+Execute on the folder), and a deny for Users on Delete, Write, Append and attribute changes. The script refuses a junction or symbolic link at `C:\ProgramData\Kiro`. Administrators are members of Users, so the deny also blocks an administrator's direct edits until it is removed; the script removes it before each update. The hook scripts are bash: they need Git Bash or WSL plus `jq`, and the script does not wire them into Kiro. On Windows, `managed-settings.json` is the primary control.

## Drift detection

1. Schedule the deploy run (self-repair) at least daily and at login on VDI.
2. Run the check mode as the MDM detection step and report non-compliance on exit 3: Intune remediation detection script, Jamf extension attribute or Kandji audit script.
3. Compare the deployed hash with the expected value that `--dry-run` prints (`sha256=...`), for example `shasum -a 256 "/Library/Application Support/Kiro/managed-settings.json"`.
4. Optionally add file-integrity monitoring (auditd, osquery or EDR) on the policy path and alert in the SIEM.

## Protecting the repository and workspace

The workspace stays writable for the developer, so protection is layered: the admin policy denies catastrophic deletion and asks for other recursive deletion, `destructive-fs-guard.sh` blocks destructive commands issued by the agent, and backups (the CDK `BackupStack`, WorkSpaces snapshots, the Git server) make an accidental or malicious deletion recoverable.

## Threat model

| Stops (for a developer without administrator rights) | Does not stop |
|------------------------------------------------------|---------------|
| Changing, replacing or deleting the admin policy and the deployed hook scripts | A local administrator or root user (detected by drift checks, not prevented) |
| The agent changing its own permission or MCP files (Kiro hardcoded deny) | The developer editing the user-owned hook file or agent (reported by `--check`, restored on the next run) |
| Weakening the admin policy with user, workspace, agent or session rules, including `--trust-all-tools` | Commands that evade glob rules and hook patterns (quoting, encoding, scripts); covered by OS, IAM, egress and server-side controls |
| Deploying a policy with an `allow` rule or a tampered hook (refused by the scripts) | Reading the hook scripts and the policy (no secrecy) |
| Truncating the hook audit log (`chattr +a`; `sappnd` on macOS) | Renaming the user-owned audit directory, or redirecting the log with `KIRO_AUDIT_LOG`; Kiro prompt logging is the audit record |

## Testing

- **Dry-run tests (no root, no system changes, safe for CI):** `bash mdm/tests/test-lockdown.sh` and `bash mdm/tests/test-lockdown-macos.sh` validate the shipped policy JSON, `agent-hooks/SHA256SUMS`, the planned actions and the refusal of bad input (allow rules, malformed JSON, BOM, UTF-16, tampered hooks, wrong pins, hook commands outside the hook directory), and assert that nothing was written. `mdm/tests/test-lockdown-windows.ps1` does the same on Windows and also writes into a temporary folder to check the UTF-8-without-BOM output. Run locally; a CI job is added separately.
- **Root and administrator tests (opt-in, disposable hosts only):** `KIRO_MDM_ROOT_TESTS=1` (Linux, macOS) or `KIRO_MDM_ADMIN_TESTS=1` (Windows). They deploy into a temporary prefix, never the real system paths, use an existing unprivileged account, and never create or delete accounts.
- **Hook tests:** `bash agent-hooks/tests/run-tests.sh`. Run locally; a CI job is added separately.
- **Adversarial harness:** `security-tests/chaos/` (see [`chaos-pentest-evidence.md`](chaos-pentest-evidence.md)). `--hooks-only` is safe anywhere; the full run needs a throwaway Linux VM and `CHAOS_ALLOW_SYSTEM_CHANGES=1`.

Historical results: [`mdm-test-evidence.md`](mdm-test-evidence.md). They predate this version of the scripts; read the dated note at the top.

## MAS TRM mapping

| MAS TRM | Covered by |
|---------|------------|
| 9.1 / 9.2 Access control | Administrator-only policy file; developers without local admin rights; sign-in restriction |
| 11.1 Data security | Policy `fs_read` denies and PII hooks deployed to every client |
| 11.2 Network security | Policy network-tool denies; MCP registry in the console |
| 7.5 Change management | Policy changes only through the MDM job; validation before deployment; hash-pinned hooks |
| 12.2 Cyber event monitoring | Drift detection (`--check`, exit 3), file-integrity alerts, append-only hook log shipped to the SIEM |

## References

- [`agent-runtime-governance.md`](agent-runtime-governance.md): the layered model this deployment supports.
- [`../managed-settings/README.md`](../managed-settings/README.md): the policy, rule rationale and manual deployment commands.
- [`permissions-and-managed-settings.md`](permissions-and-managed-settings.md): reference snapshot of the official pages.
- Official: https://kiro.dev/docs/enterprise/governance/permissions/, https://kiro.dev/docs/enterprise/governance/sign-in/, https://kiro.dev/docs/permissions/, https://kiro.dev/docs/custom-agents/, https://kiro.dev/docs/hooks/
