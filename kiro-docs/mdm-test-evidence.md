# MDM Endpoint Enforcement — Test Evidence

> **Historical evidence. Dated note, 2026-10-08.**
>
> - **The results below predate the PR3 hardening and the Kiro 1.x permission system.** They were produced by earlier versions of `mdm/` and `agent-hooks/` that deployed hook scripts and an agent file to root-owned paths. Those versions did not deploy `managed-settings.json`, which is now the primary control, and the agent file locations they used (`/opt/kiro/agents/`, `/Library/Application Support/Kiro/agents/`, `C:\ProgramData\Kiro\agents\`) are not places Kiro loads agents from, so the locked agent file had no effect on Kiro. The current scripts and tests are described in [`mdm-endpoint-enforcement.md`](mdm-endpoint-enforcement.md); no results for them are recorded on this page yet.
> - **A later review found gaps in the hooks** tested here: force-push variants (for example a `+` refspec or options before `push`), quoting and wrapper variants, a PEM private-key detection bug (a pattern that starts with dashes was read by `grep` as an option, so it never matched), and fail-open behaviour on errors (missing `jq` or unparsable input let the call through). These are fixed in `agent-hooks/` with regression tests in `agent-hooks/tests/`. The hook PASS lines below were valid only for the inputs those tests used.
> - **The round-2 "closed" items in the chaos report were simulations**; see [`chaos-pentest-evidence.md`](chaos-pentest-evidence.md).
> - **Corrections to claims on this page:** the macOS run used the user flag `uchg`, which the file owner can clear, so it does **not** show protection against the owner (see the corrected note under Environments). The hooks were **not** fail-closed at the time. CI did **not** run these tests; the hook and MDM dry-run tests are run locally, and a CI job is added separately. Agent `toolsSettings` and `denyByDefault` are deprecated in Kiro 1.x and have no equivalent in the new permission model.

Reproducible results for the cross-platform lockdown (`mdm/`) and the agent
hooks (`agent-hooks/`) as they were at the time of testing. See `kiro-docs/mdm-endpoint-enforcement.md` for the current controls.

> **Sanitized:** environment identifiers (EC2 instance IDs, account IDs, IP addresses,
> internal hostnames, local user paths) have been redacted/generalized. Outputs below are
> the verbatim PASS/RESULT lines; test fixtures (sample PII/secrets) live only in the test
> scripts, never in the output.

## Environments

| Platform | Environment | Privilege | Mechanism |
|----------|-------------|-----------|-----------|
| Linux | Amazon Linux 2023 EC2 | root (via SSM) | `chattr +i` / `chattr +a` |
| Windows | Windows Server 2022 EC2 | SYSTEM (via SSM) | `icacls` deny Delete/Write |
| macOS | macOS (Darwin), local workstation | non-root | `chflags uchg` / `uappnd` |

> The macOS run used user-immutable (`uchg`) so it needs no root; the production setting is
> system-immutable (`schg`) applied by the MDM as root.
>
> **Correction (2026-10-08):** the original note said `schg` "differs only by being harder to
> remove". That understated the difference. A user flag (`uchg`, `uappnd`) can be cleared by the
> file's **owner** with `chflags nouchg`, so the macOS results below show only that the flag blocks
> writes while it is set, not that the owner is prevented from changing the file. `schg` can be
> set and cleared only by root (and only from Recovery or single-user mode at
> `kern.securelevel` 1 or higher). The current macOS test demonstrates the owner limitation
> explicitly.

## Linux — Amazon Linux 2023 (root via SSM)

```
== run-tests ==
== pii-guard ==        PASS x5
== git-guard ==        PASS x5
== destructive-fs-guard == PASS x5 (rm -rf /, rm -rf .git, find -delete blocked; ./build + single-file allowed)
== audit-logger ==     PASS x4
== agent config ==     PASS (valid JSON); SKIP kiro-cli (not installed)
RESULT: PASS=20 FAIL=0

== test-lockdown (root) ==
  PASS: lockdown-linux.sh ran
  PASS: lockdown deployed the hook
  PASS: immutable hook cannot be modified
  PASS: immutable hook cannot be deleted (even by root)
  PASS: audit log accepts append
  PASS: audit log cannot be truncated
  PASS: self-heal restored the deleted hook
  PASS: destructive-fs-guard blocks rm -rf / , rm -rf .git , find -delete ; allows ./build
RESULT: PASS=11 FAIL=0
```

## Windows — Windows Server 2022 (SYSTEM via SSM)

```
  PASS: lockdown deployed the hook
  PASS: deny ACE present for BUILTIN\Users
  PASS: Users denied Delete
  PASS: Users denied Write
  PASS: self-heal setup (deleted)
  PASS: self-heal restored the deleted hook
RESULT: PASS=6 FAIL=0
```

Applied ACL on a locked hook (icacls), confirming a normal user is blocked:

```
<redacted-temp-path>\hooks\destructive-fs-guard.sh
  BUILTIN\Users:(DENY)(D,WD,AD,DC,WA)        <- Delete + Write + Append denied to Users
  BUILTIN\Users:(RX)
  BUILTIN\Administrators:(F)
  NT AUTHORITY\SYSTEM:(F)
```

## macOS — Darwin, local (uchg, non-root)

```
run-tests.sh             RESULT: PASS=21 FAIL=0   (incl. kiro-cli agent validate)

test-lockdown-macos.sh:
  PASS: lockdown-macos.sh ran
  PASS: lockdown deployed the hook
  PASS: immutable hook cannot be modified
  PASS: immutable hook cannot be deleted
  PASS: audit log accepts append
  PASS: audit log cannot be truncated
  PASS: self-heal restored the deleted hook
RESULT: PASS=7 FAIL=0
```

## How to reproduce

The commands that produced the results above belong to the earlier scripts. The current
tests have a different structure: by default they run non-root dry-run checks only, and the
root/administrator checks are opt-in.

```bash
# hooks (any platform with bash)
bash agent-hooks/tests/run-tests.sh

# MDM scripts, default mode: non-root dry-run tests, no system changes
bash mdm/tests/test-lockdown.sh                 # lockdown-linux.sh (runs on Linux and macOS)
bash mdm/tests/test-lockdown-macos.sh           # lockdown-macos.sh (includes the uappnd/uchg owner check on macOS)
powershell -ExecutionPolicy Bypass -File mdm/tests/test-lockdown-windows.ps1

# Opt-in root / administrator tests, disposable hosts only (temporary prefix, never the real paths)
sudo KIRO_MDM_ROOT_TESTS=1 bash mdm/tests/test-lockdown.sh          # Linux
sudo KIRO_MDM_ROOT_TESTS=1 bash mdm/tests/test-lockdown-macos.sh    # macOS
# Windows: $env:KIRO_MDM_ADMIN_TESTS = '1' in an elevated PowerShell, then run the test script
```

> **Correction (2026-10-08):** the original note said that CI ran the pure-bash hook subset. The
> CI workflows at the time (`validate-docs`, `validate-cdk`, `validate-skills`) did not run the hook
> tests. Run the hook and MDM dry-run tests locally; a CI job is added separately.
