# AWS Integration Test — Evidence (2026-10-10)

Results of the isolated integration test in [`security-tests/aws-integration/`](../security-tests/aws-integration/README.md): disposable EC2 runners and a real deployment of the CDK app in a **sandbox AWS account** (`ap-southeast-1`), followed by a full teardown. This page records what was run, what failed first, what was fixed, and the final results.

> **Sanitized.** Account IDs, ARNs, instance, VPC, subnet and key IDs, IP addresses, bucket names and SSM command IDs are removed. The CHECK/PHASE lines below are verbatim apart from that. Raw logs stayed in the test's results bucket (7-day expiry, deleted at teardown) and are not committed. No Kiro API key or other secret was used in, or written to, any log.

## Result

All required checks pass on the final code of this change (base `main` at 3c181c8 plus the fixes listed below). Every suite was re-run on the final bundle after the last fix.

| ID | Suite | Where | Result |
|----|-------|-------|--------|
| L1 | CI parity on GNU/Linux | Linux runner | **17/17 PASS**: Jest 91/91, hooks 98/98, PII patterns 346/346, 4 synth variants, `npm audit --audit-level=high` |
| L2 | Root MDM: real `lockdown-linux.sh` | Linux runner (root) | **16/16 PASS** |
| L3 | Full chaos harness, rounds 1 and 2 | Linux runner (root) | **2/2 PASS**: 0 BYPASSED, 0 sanity failures |
| W1 | Windows MDM: real `lockdown-windows.ps1` | Windows runner (SYSTEM) | **14/14 PASS**: suite 24/24 (default) and 36/36 (admin) under Windows PowerShell 5.1 and PowerShell 7 |
| C1 | Real deployment of all 5 CDK stacks (`env=dev`) | sandbox account | **36/36 PASS** |
| C2 | `egress.mode = nat-dns-firewall`: DNS Firewall allowlist | egress probe | **13/13 PASS** |
| K1 | Kiro CLI on a hardened host behind the allowlist | egress probe | **3/3 PASS** (Kiro CLI 2.29.0) |
| K2 | Kiro end-to-end prompts | egress probe | **SKIP**: no Kiro API key was provided (see [Not covered](#not-covered)) |
| T1 | Teardown and leftover scan | sandbox account | **PASS**: `LEFTOVERS total=0`; 5 KMS keys pending deletion (expected) |

## Environment

| Item | Value |
|------|-------|
| Account | Sandbox account, `ap-southeast-1`. GuardDuty, Security Hub, an AWS Config recorder and the CDK bootstrap already existed, so the deployment used `-c enableGuardDuty=false -c enableSecurityHub=false` and the existing recorder. None of the existing account resources were modified. |
| Harness | [`harness.yaml`](../security-tests/aws-integration/harness.yaml): dedicated VPC `10.250.0.0/24`, security group with **no inbound rules**, access through AWS Systems Manager only (no SSH keys), IMDSv2 required, encrypted gp3, terminate-on-shutdown plus an 8-hour on-instance failsafe. The runner role has `AmazonSSMManagedInstanceCore` and access to the results bucket only, with no deploy permissions. |
| Linux runner | Amazon Linux 2023 x86_64, t3.medium, Node.js v22.23.3 (verified against `SHASUMS256.txt`) |
| Windows runner | Windows Server 2022, t3.medium, Windows PowerShell 5.1 and PowerShell 7.6.6 |
| Egress probe | Amazon Linux 2023, t3.small, in the CDK NetworkStack's WorkSpaces subnet (`nat-dns-firewall`), no public IP |
| CDK toolchain | aws-cdk-lib 2.273.0, CDK CLI 2.1145.0, cdk-nag 2.38.2, TypeScript 5.9.3, Jest 30.5.2, ESLint 9.39.5, lockfile generated with npm 10 |
| Kiro | Kiro CLI 2.29.0, installed with `curl -fsSL https://cli.kiro.dev/install \| bash` through the DNS Firewall |

The CDK app was synthesized with `cdk synth`, with the real Availability Zones injected into the context for the run only (never committed). The synthesized templates were then deployed with the AWS CLI through the CDK bootstrap bucket and CloudFormation execution role. The assembly has no Lambda or Docker assets, so this is equivalent to `cdk deploy`. The CDK CLI was not used for the deploy because its connections were dropped by the operator's egress proxy (see the harness README).

## Findings and fixes

The first runs failed in several places. Each failure was traced to its root cause and fixed, and the suite was re-run until it passed.

| # | Finding | Fix (in this change) |
|---|---------|----------------------|
| 1 | `npm audit --audit-level=high` on the lockfile at 3c181c8: **1 critical and 36 high** advisories. CI did not catch them, because the audit step had `continue-on-error: true`. | Upgraded to aws-cdk-lib 2.273, cdk-nag 2.38, CDK CLI 2.1145, Jest 30, TypeScript 5.9 and ESLint 9 (flat config `eslint.config.mjs` replaces `.eslintrc.json`), then ran `npm audit fix`. Result: 0 critical and 0 high (20 moderate, reviewed). The CI audit step is now a **blocking** gate. |
| 2 | A lockfile written by npm 11 failed `npm ci` under npm 10, the version bundled with Node.js 22 that CI uses: "Missing: @emnapi/core from lock file". | Lockfile regenerated with npm 10; works with `npm ci` under npm 10.9 and 11.6. Rule added to `AGENTS.md`. |
| 3 | Synth printed CDK deprecation warnings: `Stack.addDependency`, `CfnResource.addDependency`, and the planned change of the default cross-stack reference strength. | `addStackDependency` / `addResourceDependency`. `cdk.json` pins `@aws-cdk/core:defaultCrossStackReferences` to `strong`, which keeps today's CloudFormation exports, so deployed stacks and export names are unchanged. |
| 4 | Testing `nat-dns-firewall` needs extra DNS Firewall entries for the probe itself (SSM, S3, OS package mirrors), and there was no way to add them for one run. | New `-c egressAllowedDomains=a,b` context option. It is validated (exact hostnames or `*.`-wildcards; a bare `*` is rejected), merged into `egress.allowedDomains`, and covered by 4 unit tests. |
| 5 | The PDPA RDS Config rules never started evaluating in an account without RDS, so they were indistinguishable from a broken rule. | Both rules are now explicitly scoped to `AWS::RDS::DBInstance` (unit test added). The verifier accepts a rule that hasn't started only if it reports no error and the account holds 0 resources of the scoped types. |
| 6 | The chaos harness's hash-chained evidence records showed the **previous step's command** for steps run through `$(dev …)`. The command substitution ran `dev()` in a subshell, so its `LAST_CMD` was lost. The verdicts were unaffected (they use the captured output). | New `devo()` helper captures the output in the current shell. The 6 call sites in `run-chaos.sh` and `run-chaos-hardened.sh` use it, and the records now show the command that actually ran. |
| 7 | Two alarms (`unauthorized-api`, `iam-policy-change`) were **already in ALARM** from real activity when the delivery check started, so `set-alarm-state ALARM` caused no transition and no action. | The verifier now forces each alarm OK → ALARM before checking. |

Test-tooling fixes (no effect on the product):
- macOS `tar` added AppleDouble `._*` entries, which the hook-manifest and Windows checks correctly rejected as unsafe file names. Fixed with `COPYFILE_DISABLE=1` plus a guard.
- Credentials and IMDS are hidden during the L1 synth for CI parity; otherwise the CDK CLI replaces the dummy account with the instance role's account.
- Re-runs of an SSM label no longer mix earlier outputs into the summary log.
- Teardown: retained-bucket cleanup and the leftover scan (see [Teardown](#teardown)).

**Detective controls fired on real activity.** During the test, the *unauthorized API calls* alarm (16 access-denied events in 5 minutes) and the *IAM policy changes* alarm went to ALARM on genuine events. The access-denied events came from workloads that already existed in the sandbox account. The policy change was the deployment itself: the CloudFormation execution role attached a managed policy to a role created by the stacks. In both cases the KMS-encrypted SNS topic received the notifications ("Successfully executed action"). None of the access-denied events came from the deployed stacks.

## L1 — CI parity on GNU/Linux (Linux runner)

```
CHECK L1.npm-ci PASS
CHECK L1.npm-audit PASS
CHECK L1.tsc PASS
CHECK L1.lint PASS
CHECK L1.jest PASS
CHECK L1.synth[env=dev] PASS
CHECK L1.synth[env=prod] PASS
CHECK L1.synth[env=dev egress=nat-dns-firewall] PASS
CHECK L1.synth[env=dev createConfigRecorder=true] PASS
CHECK L1.hooks PASS
CHECK L1.pii-patterns PASS
CHECK L1.validate-repo PASS
CHECK L1.sha256sums PASS
CHECK L1.mdm-dry-run PASS
CHECK L1.mdm-macos-dry-run PASS
CHECK L1.bash-n PASS
CHECK L1.json PASS
PHASE L1 RESULT pass=17 fail=0 skip=0
```

Details from the same run: `Tests: 91 passed, 91 total`; hooks `PASS=98 FAIL=0 KNOWN_GAP=0`; PII patterns `PASS=346 FAIL=0 SKIP=0`; `validate-repo.sh` `RESULT: PASSED`; MDM dry runs `PASS=45 FAIL=0` (Linux) and `PASS=28 FAIL=0 SKIP=1` (macOS script on Linux); `npm audit`: 20 moderate, 0 high, 0 critical.

## L2 — root MDM lockdown (Linux runner, root)

A real `mdm/lockdown-linux.sh --hooks` for a test user that the suite created (the final run reused it):

```
CHECK L2.root-suite PASS
CHECK L2.user PASS
CHECK L2.lockdown PASS
CHECK L2.policy-present PASS
CHECK L2.policy-owner-mode PASS root:644
CHECK L2.policy-immutable PASS
CHECK L2.policy-content PASS
CHECK L2.user-cannot-modify PASS
CHECK L2.user-cannot-delete PASS
CHECK L2.hooks-verified PASS
CHECK L2.check-clean PASS rc=0
CHECK L2.check-detects-drift PASS rc=3
CHECK L2.reapply PASS
CHECK L2.check-after-restore PASS rc=0
CHECK L2.audit-append PASS
CHECK L2.audit-no-truncate PASS
PHASE L2 RESULT pass=16 fail=0 skip=0
```

`/etc/kiro/managed-settings.json` is identical to `managed-settings/managed-settings.banking.json`, owned by root, mode 644, and immutable (`chattr +i`). The non-root user can neither modify nor delete it. The deployed hooks match `agent-hooks/SHA256SUMS`. `--check` exits 0 on a clean host and 3 after a one-byte change, and a re-run restores the file. The user can append to the hook audit log but cannot truncate it (`chattr +a`).

## L3 — chaos harness (Linux runner, root, `CHAOS_ALLOW_SYSTEM_CHANGES=1`)

```
CHECK L3.run-chaos.sh PASS total=37 BLOCKED=28 DETECTED=1 GAP=8 BYPASSED=0 sanity-failures=0
CHECK L3.run-chaos-hardened.sh PASS total=32 BLOCKED=27 DETECTED=1 GAP=4 BYPASSED=0 sanity-failures=0
PHASE L3 RESULT pass=2 fail=0 skip=0
```

Every GAP is a documented endpoint limitation, and its `expected` value in the harness is `GAP`. Each is covered by another tier (server-side branch protection, egress control, IAM), as described in [`chaos-pentest-evidence.md`](chaos-pentest-evidence.md):
- **Round 1:** deleting or renaming user-owned files (A8, A9); git by absolute path or a private copy of git bypassing a PATH guard (C1, C2); redirecting the audit log through an environment variable (C3); base64-encoded commands and PII (D4, D6); copying readable data to a local sink (E3).
- **Round 2:** the remaining four, D4, D6, C3 and C1. An approved system binary still runs, so force-push must be stopped server-side.

The harness created its own test account, refused to reuse an existing one, and deleted only the account it created.

## W1 — Windows MDM (Windows runner, SYSTEM)

```
CHECK W1.ps51-default PASS RESULT: PASS=24 FAIL=0 SKIP=0
CHECK W1.ps51-admin PASS RESULT: PASS=36 FAIL=0 SKIP=0
CHECK W1.pwsh7-installed PASS 7.6.6
CHECK W1.pwsh7-default PASS RESULT: PASS=24 FAIL=0 SKIP=0
CHECK W1.pwsh7-admin PASS RESULT: PASS=36 FAIL=0 SKIP=0
CHECK W1.lockdown PASS
CHECK W1.policy-present PASS
CHECK W1.no-bom PASS
CHECK W1.json PASS
CHECK W1.content PASS
CHECK W1.users-deny-ace PASS
CHECK W1.check-clean PASS
CHECK W1.check-detects-drift PASS rc=3
CHECK W1.check-after-restore PASS
PHASE W1 RESULT pass=14 fail=0 skip=0
```

`C:\ProgramData\Kiro\managed-settings.json` is written as UTF-8 without a BOM, is valid JSON, matches the source policy, and carries a DENY ACE for `BUILTIN\Users`. `-Check` detects drift (exit 3), and a re-run restores the file.

## C1 — real deployment (`env=dev`, default egress `none`)

```
CHECK C1.stack[KiroBanking-Encryption-dev] PASS CREATE_COMPLETE
CHECK C1.stack[KiroBanking-Network-dev] PASS CREATE_COMPLETE
CHECK C1.stack[KiroBanking-Monitoring-dev] PASS CREATE_COMPLETE
CHECK C1.stack[KiroBanking-Compliance-dev] PASS UPDATE_COMPLETE
CHECK C1.stack[KiroBanking-Backup-dev] PASS CREATE_COMPLETE
CHECK C1.kms-rotation[KiroBanking-Encryption-dev] PASS        (x3)
CHECK C1.kms-rotation[KiroBanking-Network-dev] PASS
CHECK C1.kms-rotation[KiroBanking-Backup-dev] PASS
CHECK C1.vpc-endpoints-available PASS 5 available
CHECK C1.nacl-associated PASS Endpoints subnets
CHECK C1.workspaces-sg-no-allow-all-egress PASS nat-gateways=0
CHECK C1.flow-log-active PASS ACTIVE/SUCCESS
CHECK C1.flow-log-cmk PASS
CHECK C1.cloudtrail-logging PASS
CHECK C1.cloudtrail-no-LatestDeliveryError PASS
CHECK C1.cloudtrail-no-LatestCloudWatchLogsDeliveryError PASS
CHECK C1.cloudtrail-no-LatestDigestDeliveryError PASS
CHECK C1.cloudtrail-delivered-s3 PASS
CHECK C1.cloudtrail-delivered-cwl PASS
CHECK C1.audit-object-lock PASS GOVERNANCE 30
CHECK C1.audit-versioning PASS
CHECK C1.audit-public-access-block PASS
CHECK C1.audit-sse-kms PASS
CHECK C1.audit-noncurrent-expiration PASS
CHECK C1.alarm-action-delivered[kiro-banking-cloudtrail-change-dev] PASS prior-state=OK
CHECK C1.alarm-action-delivered[kiro-banking-iam-policy-change-dev] PASS prior-state=OK
CHECK C1.alarm-action-delivered[kiro-banking-kms-key-disable-or-deletion-dev] PASS prior-state=OK
CHECK C1.alarm-action-delivered[kiro-banking-no-mfa-signin-dev] PASS prior-state=OK
CHECK C1.alarm-action-delivered[kiro-banking-root-account-usage-dev] PASS prior-state=OK
CHECK C1.alarm-action-delivered[kiro-banking-sg-change-dev] PASS prior-state=OK
CHECK C1.alarm-action-delivered[kiro-banking-unauthorized-api-dev] PASS prior-state=ALARM
CHECK C1.config-rules-19 PASS
CHECK C1.config-rules-evaluate PASS not-applicable(0 in-scope resources): pdpa-rds-encryption-dev pdpa-rds-no-public-dev
CHECK C1.backup-schedule PASS cron(0 18 * * ? *)
PHASE C1 RESULT pass=36 fail=0 skip=0
```

This proves:
- **Alarm delivery:** all 7 alarms deliver to the SNS topic encrypted with the AuditKey, so the key policy and topic policy allow CloudWatch alarms to publish.
- **CloudTrail:** delivers to the Object Lock audit bucket and to CloudWatch Logs without errors.
- **Flow logs:** active and encrypted with their dedicated CMK.
- **Network:** the endpoint NACL is attached to the Endpoints subnets, and the WorkSpaces security group has no allow-all egress rule.
- **Config:** 17 of the 19 Config rules evaluate without errors. The 2 RDS rules have nothing in scope.

`KiroBanking-Compliance-dev` shows `UPDATE_COMPLETE` because the RDS rule scopes (finding 5) were deployed as an in-place update. The stack was not re-created.

## C2 — `nat-dns-firewall` egress (probe in the WorkSpaces subnet)

The deployed Network stack was updated in place to `-c egress=nat-dns-firewall`. CloudFormation added the `Public` subnets, the NAT gateway, the DNS Firewall rule group and association, and the WorkSpaces default routes; it replaced no existing subnet or endpoint. The test-only allowlist additions (`-c egressAllowedDomains=`) were the regional SSM hosts, the regional S3 host and the results bucket, and the AL2023 package mirrors. A production allowlist does not need them.

```
CHECK C2.resolves[app.kiro.dev] PASS
CHECK C2.resolves[prod.us-east-1.auth.desktop.kiro.dev] PASS
CHECK C2.resolves[runtime.us-east-1.kiro.dev] PASS
CHECK C2.resolves[cli.kiro.dev] PASS
CHECK C2.resolves[q.us-east-1.amazonaws.com] PASS
CHECK C2.resolves[oidc.ap-southeast-1.amazonaws.com] PASS
CHECK C2.blocked[example.com] PASS
CHECK C2.blocked[www.google.com] PASS
CHECK C2.blocked[github.com] PASS
CHECK C2.blocked[pastebin.com] PASS
CHECK C2.https[https://app.kiro.dev] PASS http=200
CHECK C2.https[https://prod.us-east-1.auth.desktop.kiro.dev] PASS http=404
CHECK C2.https-blocked PASS
PHASE probe RESULT pass=13 fail=0 skip=0
```

`github.com` is blocked because the optional extension and Powers/MCP hosts are excluded by default (`KIRO_OPTIONAL_HOSTS`). An HTTP 404 from the auth host still proves the TLS connection succeeded.

## K1 — Kiro CLI behind the allowlist (probe)

```
CHECK K1.install PASS kiro-cli 2.29.0
CHECK K1.lockdown PASS
CHECK K1.agent-installed PASS valid JSON, identical to agent-hooks/banking-secure.agent.json
CHECK K2.e2e SKIP no /kiro-fsi-test/kiro-api-key parameter (end-to-end prompts need a Kiro API key)
PHASE kiro RESULT pass=3 fail=0 skip=1
```

The official installer and its download host (`prod.download.cli.kiro.dev`) worked using only the hosts that `kiroEgressDomains()` allowlists. This confirms that the CLI host list in `cdk/config/kiro-endpoints.ts` is sufficient for installation.

## Not covered

- **K2 (Kiro end-to-end) was skipped.** It needs a Kiro API key (Pro tiers; headless mode uses `KIRO_API_KEY`) stored as the SSM SecureString `/kiro-fsi-test/kiro-api-key`. Without it, the following were not exercised: admin deny rules overriding `--trust-all-tools`, the pii-guard hook blocking an agent-driven write of an NRIC, and hook audit records written by a live session. The hooks themselves are covered by L1 (98 tests), L3 and K1. To run K2, store the key and re-run the `egress` stage.
- **macOS** was not tested (out of scope for this run; EC2 Mac has a 24-hour minimum allocation).
- **Account singletons:** GuardDuty, Security Hub and the Config recorder already existed, so the stacks' creation paths for them (`enableGuardDuty`, `enableSecurityHub`, `createConfigRecorder=true`) were synthesized and checked by cdk-nag (L1) but not deployed.
- **DNS Firewall scope:** it filters DNS only. A connection made directly to an IP address is not blocked (documented in `cdk/README.md`).
- The test asserts that the Config rules **evaluate**. It does not assert their compliance results, which reflect account-level settings of the sandbox account.

## Teardown

`run-integration.sh down leftovers`, run after this change's PR was opened (2026-10-10):

```
probe deleted
retained resources recorded: 10
deleted KiroBanking-Backup-dev
deleted KiroBanking-Compliance-dev
deleted KiroBanking-Monitoring-dev
deleted KiroBanking-Network-dev
deleted KiroBanking-Encryption-dev
KMS key scheduled for deletion (7 days)                      (x5)
deleted log group (retained)                                 (x2)
deleted bucket (retained)                                    (audit-log bucket, Object Lock GOVERNANCE)
deleted backup vault (retained)
harness deleted (instances terminated)
```

The first pass left one retained bucket behind. The cleanup passed `--bypass-governance-retention` to every bucket, and S3 rejects that flag on a bucket without Object Lock (the access-log bucket). `empty_bucket` now passes the flag only when Object Lock is enabled, and fails on per-object errors instead of looping. The bucket was then deleted with the fixed code.

Final leftover scan:

```
STALE ec2:instance (deleted; tagging API not yet updated)        (x3)
STALE ec2:natgateway (deleted; tagging API not yet updated)
STALE ec2:vpc-endpoint (deleted; tagging API not yet updated)    (x5)
STALE ec2:vpc-flow-log (deleted; tagging API not yet updated)
EXPECTED kms:key PendingDeletion                                 (x5)
LEFTOVERS total=0
```

- The Resource Groups Tagging API keeps listing deleted resources for a while. `leftovers` now checks every tagged ARN against its own service and reports it as `STALE` only when that service says it is gone (terminated, deleted or not found).
- A name-prefix scan (`kiro-banking`, `KiroBanking`, `kiro-fsi-test`) found nothing. It covers S3 buckets, log groups, KMS aliases, backup vaults and plans, SNS topics, alarms, Config rules, trails, Access Analyzer, EventBridge rules, DNS Firewall rule groups and domain lists, IAM roles and SSM parameters.
- No test instances are pending, running, stopping or stopped.
- The 5 customer-managed KMS keys are in `PendingDeletion` (7-day window, ending 2026-10-17). AWS deletes them automatically.
- The account resources that existed before the test are unchanged: the GuardDuty detector, Security Hub, the Config recorder (still recording), the CDK bootstrap stack, and the account's multi-region CloudTrail trail (still logging). The CDK bootstrap was not created by the test, so it was not removed.

## Reproduce

```bash
export IT_REGION=ap-southeast-1
bash security-tests/aws-integration/run-integration.sh preflight up bundle
bash security-tests/aws-integration/run-integration.sh linux windows
bash security-tests/aws-integration/run-integration.sh deploy verify egress
bash security-tests/aws-integration/run-integration.sh down leftovers
```

See [`security-tests/aws-integration/README.md`](../security-tests/aws-integration/README.md) for prerequisites, the safety controls and the test matrix.
