# MDM Endpoint Enforcement — Test Evidence

Reproducible results for the cross-platform lockdown (`mdm/`) and the agent
hooks (`agent-hooks/`). See `kiro-docs/mdm-endpoint-enforcement.md` for the controls.

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
> system-immutable (`schg`) applied by the MDM as root. Both use the same `chflags`
> mechanism — `schg` differs only by being harder to remove (single-user mode).

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

```bash
# hooks (any platform with bash)
bash agent-hooks/tests/run-tests.sh

# OS lockdown (need root/admin + filesystem attribute support; not run in CI)
sudo bash mdm/tests/test-lockdown.sh            # Linux
bash mdm/tests/test-lockdown-macos.sh           # macOS (uchg, no root)
powershell -ExecutionPolicy Bypass -File mdm/tests/test-lockdown-windows.ps1   # Windows (admin)
```

> CI (`validate-docs`/`validate-cdk`/`validate-skills`) runs the pure-bash hook subset; the
> root/admin OS-lockdown tests are run out-of-band on managed hosts as shown above.
