# AWS integration test (isolated sandbox)

End-to-end validation of this repository in a **sandbox AWS account**. It runs what unit tests, `cdk synth` and dry runs cannot prove: a real CDK deployment, the root and admin MDM lockdowns, the full chaos harness, the `nat-dns-firewall` egress mode and the Kiro CLI on a hardened host.

> **Sandbox accounts only.** The CDK deploy creates account-level resources in the workload region: a CloudTrail trail, AWS Config rules, and optionally GuardDuty, Security Hub, an Access Analyzer and a Config recorder. The orchestrator detects existing account singletons and does not touch them.

## What it creates (all tagged `Project=kiro-fsi-test`, region `ap-southeast-1` by default)

| Resource | Security posture |
|---|---|
| `harness.yaml`: isolated VPC `10.250.0.0/24`, Linux (AL2023) and Windows Server 2022 runners, results bucket | **No inbound rules, no SSH keys.** Access only through AWS Systems Manager. IMDSv2 required, encrypted gp3, `InstanceInitiatedShutdownBehavior=terminate` plus an on-instance failsafe shutdown timer (8 h default). Bucket uses SSE-KMS, blocks public access, enforces TLS and expires objects after 7 days. |
| Runner IAM role | `AmazonSSMManagedInstanceCore`, plus read/write on the results bucket and `ssm:GetParameter` on `/kiro-fsi-test/*`. **No deploy permissions:** the CDK deploy runs from the operator's machine. |
| The repo's 5 CDK stacks (`env=dev`) | Synthesized offline with `cdk synth` (real AZs injected into the context for the run only, never committed), deployed with the AWS CLI through the CDK bootstrap bucket and CloudFormation execution role, verified, then deleted. RETAIN resources are cleaned up afterwards (KMS keys go to a 7-day pending deletion). |
| `probe.yaml`: egress probe in the CDK WorkSpaces subnet | Same posture as the runners; used to test the DNS Firewall allowlist and Kiro CLI sign-in paths. |

## Test matrix

| ID | Where | Checks |
|---|---|---|
| L1 | Linux runner | CI parity on GNU/Linux: `npm ci`, `npm audit`, tsc, lint, jest, `cdk synth` variants, hook tests, PII patterns, `validate-repo.sh`, `SHA256SUMS`, `bash -n`, MDM dry runs |
| L2 | Linux runner (root) | Root-mode MDM suite, plus a real `lockdown-linux.sh`. Checks immutability, that a non-root user cannot modify or delete the policy, hook hashes, drift detection (`--check` exit 3), restore, and that the audit log can be appended to but not truncated. |
| L3 | Linux runner (root) | Full chaos harness, rounds 1 and 2. Requires 0 BYPASSED and 0 sanity failures. |
| W1 | Windows runner (SYSTEM) | `test-lockdown-windows.ps1` in default and admin mode, under Windows PowerShell 5.1 and PowerShell 7. A real `lockdown-windows.ps1` must produce UTF-8 without a BOM, the Users DENY ACE, and correct drift and restore behaviour. |
| C1 | operator machine | Real deployment of the synthesized CDK app (all 5 stacks). Checks: KMS rotation, VPC endpoints, NACL association, WorkSpaces SG egress, flow logs with CMK, CloudTrail delivery to S3 and CloudWatch Logs, audit bucket Object Lock / versioning / public-access block / SSE-KMS / noncurrent expiration, **alarm actions delivered to the KMS-encrypted SNS topic** (each alarm is forced OK → ALARM, so an alarm that real activity already triggered is still tested), 19 Config rules evaluating without errors (a rule that has not started passes only if it is explicitly scoped and the account holds 0 resources of its scoped types), backup schedule |
| C2 | probe | `egress.mode = nat-dns-firewall`: allowlisted Kiro hosts resolve and answer over HTTPS; non-allowlisted hosts are blocked |
| K1 | probe | Kiro CLI installs through the allowlist; managed settings, hooks and the agent are deployed by MDM |
| K2 | probe | Only if a Kiro API key is stored at `/kiro-fsi-test/kiro-api-key` (SSM SecureString). `kiro-cli chat --no-interactive --trust-all-tools` must have a force-push blocked (remote ref unchanged), an NRIC write blocked, a benign command succeed, and hook audit records written. |

## Run

Prerequisites:
- AWS CLI v2 and credentials for the sandbox account;
- `jq`;
- Node.js 20+ with `cdk/node_modules` installed.

```bash
export IT_REGION=ap-southeast-1   # an inherited AWS_REGION is ignored
bash security-tests/aws-integration/run-integration.sh preflight up bundle
bash security-tests/aws-integration/run-integration.sh linux windows
bash security-tests/aws-integration/run-integration.sh deploy verify egress
# after fixing anything: bundle + re-run the failing stage
# re-verifying long-lived stacks: IT_VERIFY_WAIT=30 skips most of the 6-minute first-delivery wait
bash security-tests/aws-integration/run-integration.sh down leftovers
```

State and raw logs go to `$IT_WORKDIR` (default `$TMPDIR/kiro-fsi-it`) and are **never committed**. When summarising results, the orchestrator masks account IDs, instance and resource IDs, and IP addresses. Tear down with `down` even after a failed run; `leftovers` must report `LEFTOVERS total=0`, with KMS keys pending deletion listed as `EXPECTED`.

The test-only DNS Firewall additions (SSM, the results bucket and the AL2023 package mirrors, passed with `-c egressAllowedDomains=`) exist only to drive the probe. A production allowlist does not need them.

> **Why not `cdk deploy`?** In the test environment the CDK CLI's Node.js HTTP connections were repeatedly dropped (`aborted` / `Deserialization error`) by an intermediate egress proxy, while the Python AWS CLI was unaffected. The assembly contains no Lambda or Docker assets, so deploying the synthesized templates with CloudFormation is equivalent. `cdk deploy --all` remains the normal deployment path for users.

Results from the last run: [`kiro-docs/aws-integration-test-evidence.md`](../../kiro-docs/aws-integration-test-evidence.md).
