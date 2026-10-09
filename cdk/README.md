# Kiro Banking CDK Infrastructure

AWS CDK (TypeScript) modules for deploying MAS-aligned Kiro banking environments.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ EncryptionStack                                         │
│  KMS Keys: Audit | Data | WorkSpaces                    │
└──────────────────────┬──────────────────────────────────┘
                       │ AuditKey
                       ▼
┌──────────────┐ ┌────────────┐ ┌──────────────┐ ┌──────────────┐
│ NetworkStack │ │ Monitoring │ │ Compliance   │ │ BackupStack  │
│ VPC          │ │ CloudTrail │ │ AWS Config   │ │ AWS Backup   │
│ PrivateLink  │ │ S3 + Object│ │ 19 rules     │ │ vault (KMS)  │
│ SGs + NACL   │ │  Lock logs │ │ opt. recorder│ │ daily plan   │
│ Flow Logs    │ │ 7 alarms   │ │ Security Hub │ │              │
│ (KMS)        │ │ GuardDuty  │ │ Access Anal. │ │              │
└──────────────┘ └────────────┘ └──────────────┘ └──────────────┘
```

Only MonitoringStack depends on EncryptionStack (it uses the AuditKey); the other stacks are independent.

## Stacks

| Stack | MAS TRM Section | Resources |
|-------|-----------------|-----------|
| **EncryptionStack** | 10.2 (Cryptographic Key Management) | 3 KMS keys with rotation; every service-principal statement is limited to this account or the specific source resource |
| **NetworkStack** | 11.2 (Network Security) | VPC, 4 AWS interface endpoints + S3 gateway (Kiro endpoints only in the Kiro profile region), SGs without default allow-all egress, NACL on the Endpoints subnets, flow logs encrypted with a dedicated KMS key, optional NAT + DNS Firewall egress |
| **MonitoringStack** | 12.2 (Cyber Event Monitoring and Detection) | CloudTrail, S3 audit-log bucket with Object Lock, 7 CloudWatch alarms, encrypted SNS topic, GuardDuty (optional) |
| **ComplianceStack** | 9, 10, 11, 12.2 + PDPA | 19 AWS Config managed rules, optional configuration recorder, Security Hub and IAM Access Analyzer (optional) |
| **BackupStack** | 8.4 (System Backup and Recovery) | AWS Backup vault (KMS), daily plan for resources tagged `Backup=daily`, 35-day retention |

## Prerequisites

- Node.js 22 LTS (Node.js 20 or later is supported; `aws-cdk-lib` requires `>= 20`)
- AWS credentials configured
- CDK bootstrapped: `npx cdk bootstrap aws://ACCOUNT/ap-southeast-1` (and any region you pass with `-c region=`)
- An AWS Config configuration recorder in the account and region, or `createConfigRecorder: true` (see [AWS Config](#aws-config-rules-19))

The CDK CLI is a dev dependency, so `npx cdk` uses the pinned version; a global `npm install -g aws-cdk` is optional.

## Quick Start

```bash
cd cdk
npm install

# Synthesize (validates all stacks + CDK Nag)
npx cdk synth

# Deploy to dev
npx cdk deploy --all -c env=dev

# Deploy to prod
npx cdk deploy --all -c env=prod

# Preview changes
npx cdk diff

# Optional overrides (see "Network and Kiro connectivity" and "Account-level singletons")
npx cdk synth -c env=dev -c egress=nat-dns-firewall   # self-contained filtered egress
npx cdk synth -c env=dev -c region=us-east-1          # workload in the Kiro profile region
npx cdk synth -c env=dev -c createConfigRecorder=true # also create the AWS Config recorder
```

### Build

The app is compiled with the TypeScript compiler; `ts-node` is not used. `cdk.json` sets `"build": "npx tsc"`, which the CDK CLI runs before every synth, deploy or diff, and `"app": "node build/bin/kiro-banking.js"`. `tsc` writes JavaScript to `build/` (ignored by git and ESLint); `cdk.out/` only holds the synthesized cloud assembly. After `npm install`, synthesis needs no network access. `npm run build` compiles without synthesizing; `npm test` runs the Jest tests in `test/` directly from TypeScript.

## Configuration

Edit `config/environments.ts` to customize:

- VPC CIDR ranges
- Kiro profile region (`kiroProfileRegion`: `us-east-1` or `eu-central-1`)
- IAM Identity Center region, access portal host and external IdP host (used for the egress allowlist)
- Egress mode (`egress.mode`) and extra allowed domains (`egress.allowedDomains`)
- Optional subset of Kiro endpoints (`kiroEndpoints`, normally empty)
- Audit log retention and protection (see [Audit log retention](#audit-log-retention))
- Account-level singletons (see [Account-level singletons](#account-level-singletons))
- Backup schedule (see [Backup schedule](#backup-schedule))
- Resource tags
- CDK Nag toggle

| Option | dev | prod | Purpose |
|--------|-----|------|---------|
| `cloudTrailRetentionDays` | 90 | 2555 | Days to keep CloudTrail log files in S3 (also the AWS Config history bucket) |
| `auditLogObjectLockDays` | 30 | 365 | Default Object Lock retention (GOVERNANCE) for new audit-log objects; must not exceed `cloudTrailRetentionDays` |
| `accessLogRetentionDays` | 365 | 365 | Days to keep S3 server access logs of the audit-log bucket |
| `createConfigRecorder` | `false` | `false` | Create the AWS Config recorder and delivery channel in this stack |
| `configRecorderGlobalResources` | `true` | `true` | With the recorder: also record global IAM resource types (in one region only) |
| `enableGuardDuty` | `true` | `true` | Create the GuardDuty detector |
| `enableSecurityHub` | `true` | `true` | Enable Security Hub |
| `enableAccessAnalyzer` | `true` | `true` | Create an account-level IAM Access Analyzer |
| `backupScheduleCron` | `cron(0 18 * * ? *)` | `cron(0 18 * * ? *)` | AWS Backup schedule in UTC |

The boolean options can also be set for one run with `-c createConfigRecorder=true`, `-c enableGuardDuty=false`, `-c enableSecurityHub=false` or `-c enableAccessAnalyzer=false`.

Kiro regions, endpoint service names and the egress allowlist live in `config/kiro-endpoints.ts`.

### Account-level singletons

Some resources exist at most once per account and region: the AWS Config configuration recorder and delivery channel, the GuardDuty detector, the Security Hub hub and the account-level IAM Access Analyzer (one per analyzer type). If AWS Control Tower or a delegated administrator already manages them for the organization, creating them here fails the deployment. Set the matching option so this app does not create them: `createConfigRecorder` (default `false`), `enableGuardDuty`, `enableSecurityHub` and `enableAccessAnalyzer` (default `true`). GuardDuty findings are routed to the security topic either way.

### Backup schedule

AWS Backup evaluates cron expressions in UTC. The default `cron(0 18 * * ? *)` starts the daily backup at 18:00 UTC, which is 02:00 in Singapore (UTC+8, no daylight saving). Set `backupScheduleCron` to another six-field AWS cron expression to change it; the start window is 1 hour and the completion window 2 hours.

## Network and Kiro connectivity

Two regions are involved and they are usually different:

- **Workload region** (`region`, default `ap-southeast-1`): this app's VPC, WorkSpaces networking, CloudTrail, AWS Config and AWS Backup.
- **Kiro profile region** (`kiroProfileRegion`, `us-east-1` or `eu-central-1`): where Kiro stores prompts, code context and responses and runs inference. Inference scope is set per model (see the [Kiro models page](https://kiro.dev/docs/models/)): content sent to Geography-scope models, which include all Claude models, may be processed in other regions of the same geography, and Global-scope models (currently GPT-5.6 Sol, Terra and Luna) may be processed in AWS Regions worldwide. Kiro has no Asia Pacific profile region. IAM Identity Center can stay in `ap-southeast-1`.

### VPC endpoints

| Endpoint | Created when | Purpose |
|----------|--------------|---------|
| `com.amazonaws.<region>.logs`, `.kms`, `.sts` | Always | AWS APIs called from workloads in this VPC |
| `com.amazonaws.<region>.identitystore` | Always | Identity Store API for user/group administration. Not used for Kiro sign-in |
| S3 gateway | Always | Private S3 access from this VPC |
| `com.amazonaws.<region>.q` | Workload region = `kiroProfileRegion` (us-east-1 or eu-central-1) | Kiro API; private DNS serves `q.<region>.amazonaws.com` and `runtime\|management\|telemetry.<region>.kiro.dev` |
| `com.amazonaws.us-east-1.codewhisperer` | Workload region = `kiroProfileRegion` = us-east-1 | Kiro (us-east-1 only) |

`com.amazonaws.ap-southeast-1.q` and `.codewhisperer` do not exist, cross-Region PrivateLink does not support these services, and Kiro clients do not need an Amazon Bedrock endpoint. In `ap-southeast-1` the stack therefore creates no Kiro endpoints and reports this as an info message during synthesis. CloudTrail and VPC Flow Logs are delivered by the AWS services themselves and do not use these endpoints.

Sources (verified 2026-10-08): [Kiro VPC endpoints](https://kiro.dev/docs/privacy-and-security/vpc-endpoints/), [Kiro firewall allowlist](https://kiro.dev/docs/privacy-and-security/firewalls/), [AWS cross-Region PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/aws-services-cross-region-privatelink-support.html).

### Egress (`egress.mode`)

Kiro sign-in (`app.kiro.dev`, IAM Identity Center), downloads and auth hosts are public HTTPS endpoints in every region, and browser-based sign-in bypasses the IDE proxy settings. Kiro clients therefore always need allowlisted HTTPS egress. `kiroEgressDomains()` in `config/kiro-endpoints.ts` builds the allowlist from the official firewall page using exact hostnames only (no `*.amazonaws.com`, which would allow any S3 bucket). It includes the IAM Identity Center hosts for `identityCenterRegion`, plus `identityCenterPortalHost` and `externalIdpDomain` when set. Social sign-in (`cognito-identity.us-east-1.amazonaws.com`) and the optional extension hosts (Open VSX, GitHub) are excluded by default.

- **`none` (default):** no internet gateway, no NAT gateway, isolated subnets. Provide egress centrally (landing-zone egress/inspection VPC or explicit proxy) and enforce the Kiro allowlist there. This is the recommended option for production.
- **`nat-dns-firewall`:** self-contained option for experimentation or small estates. Adds a `Public` subnet group (`/28`, no public IP mapping), one NAT gateway, `PRIVATE_WITH_EGRESS` Workspaces subnets (the Endpoints subnets stay isolated), HTTPS (443) egress to any IPv4 address on the WorkSpaces security group, and a Route 53 Resolver DNS Firewall associated with the VPC: an ALLOW rule (priority 100) for the Kiro allowlist, this VPC's endpoint hostnames and `egress.allowedDomains`, then a BLOCK rule (priority 200, `NODATA`) for `*`.

Limitations of `nat-dns-firewall`:

- DNS Firewall filters DNS queries only. It does not stop connections made directly to IP addresses, including DNS over HTTPS to a public resolver IP on port 443. For stronger enforcement use AWS Network Firewall with TLS SNI inspection or an explicit proxy in a central inspection VPC.
- Every name that is not allowlisted gets `NODATA`, including OS patching, S3 bucket hostnames, Route 53 private hosted zones and `*.compute.internal`. Add what you need to `egress.allowedDomains`.
- The inline HTTPS rule replaces EC2's default allow-all egress rule on the WorkSpaces security group, so add rules for any other traffic WorkSpaces need (e.g. directory services).
- One NAT gateway keeps cost low but is a single-AZ dependency; use one NAT gateway per AZ for production resilience. NAT gateways and DNS Firewall queries are charged.
- Consider enabling Route 53 Resolver query logging to record blocked queries (MAS TRM 12.2).

### Private connectivity to the Kiro API from Singapore

A Singapore VPC cannot create Kiro interface endpoints directly. If you need PrivateLink for the Kiro API, either (a) build a "Kiro access VPC" in the profile region with the `.q` (and, in us-east-1, `.codewhisperer`) endpoints, private DNS disabled, and Route 53 private hosted zones for `q.<region>.amazonaws.com` and `runtime|management|telemetry.<region>.kiro.dev` that point to the endpoint and are associated with the Singapore VPC, connected through inter-Region VPC peering or Transit Gateway peering; or (b) run the WorkSpaces in the profile region (`-c region=us-east-1`). Either way, sign-in and download hosts stay public, so an egress path is still required.

### Security groups, NACL and flow logs

- **WorkSpaces security group:** egress is HTTPS (443) to the endpoint security group only (plus HTTPS to any IPv4 address in `nat-dns-firewall` mode). In `egress.mode = 'none'` the group also carries CDK's inline "match no traffic" rule so that EC2 removes its default allow-all egress rule; a separate security-group-to-security-group rule alone would leave that default in place.
- **Endpoint NACL:** associated with the Endpoints subnets. It is stateless and allows only HTTPS (443) and ephemeral return traffic (1024-65535) to and from the VPC CIDR. Clients outside the VPC CIDR (peered VPCs, Transit Gateway, on-premises) need additional entries before they can use these endpoints.
- **Flow logs:** delivered to a CloudWatch Logs group (two-year retention) encrypted with a dedicated customer-managed key (`alias/kiro-banking-flow-logs-<env>`, rotation enabled, retained on stack deletion). The key policy only lets CloudWatch Logs use the key for this log group (matched on its CloudFormation-generated name, which is kept so that the existing group is not replaced).

## CDK Nag

All stacks are validated with [cdk-nag](https://github.com/cdklabs/cdk-nag) AwsSolutions rule pack. Security suppressions include documented justifications.

## CloudWatch Alarms

All alarms evaluate CloudTrail events in 5-minute periods and notify the SNS topic `kiro-banking-security-alerts-<env>`. The topic is encrypted with the AuditKey, whose policy lets CloudWatch alarms (`cloudwatch.amazonaws.com`, this account) and EventBridge use it; the topic policy allows CloudWatch alarms of this account and region and EventBridge to publish. Subscribe your security team's endpoints to the topic.

| Alarm | MAS Section | CIS AWS Foundations | Trigger |
|-------|-------------|---------------------|---------|
| Unauthorized API calls | 12.2 / 9.1 | — | 5+ access denied in 5 min |
| Console sign-in without MFA | 12.2 / 9.1 | 4.2 | Successful IAM user console sign-in without MFA (federated sign-ins are excluded; their MFA is enforced by the identity provider) |
| Root account usage | 12.2 / 9.2 | 4.3 | Any root user activity that is not an AWS service event |
| IAM policy changes | 12.2 / 9.2 | 4.4 | Create/delete/put/attach/detach of role, user, group and managed policies, policy versions and default version changes |
| CloudTrail configuration changes | 12.2 | 4.5 | CreateTrail, UpdateTrail, DeleteTrail, StartLogging, StopLogging |
| KMS key disabled or scheduled for deletion | 12.2 / 10.2 | 4.7 | DisableKey, ScheduleKeyDeletion |
| Security group changes | 12.2 / 11.2 | 4.10 | Any SG rule modification |

GuardDuty findings are routed to the same topic by an EventBridge rule.

## Audit log retention

- **Audit-log bucket** (`kiro-banking-audit-logs-<env>-<account>`): KMS-encrypted (AuditKey), versioned, SSL-only, Object Lock with a default retention of `auditLogObjectLockDays` in GOVERNANCE mode. Principals with `s3:BypassGovernanceRetention` can still shorten or remove a GOVERNANCE lock; COMPLIANCE mode cannot be shortened or removed by anyone, including the root user, until each object's retention expires, so switch to it only after legal review. The lifecycle rule moves objects to Standard-IA after 30 days and Glacier after 90 days, but only for transitions that occur before the expiration (`cloudTrailRetentionDays`; in dev, 90 days, so only the Standard-IA transition applies). Noncurrent versions are removed 90 days after they become noncurrent, and never before their Object Lock retention ends.
- **Access-log bucket** (`kiro-banking-access-logs-<env>-<account>`): server access logs of the audit-log bucket, kept for `accessLogRetentionDays` (default 365, Glacier after 90 days). This is shorter than the prod audit-log retention by design; raise it to `cloudTrailRetentionDays` if your record-keeping policy requires access records for the same period.
- **CloudTrail log group** (`/kiro-banking/cloudtrail/<env>`): two-year retention, encrypted with the AuditKey; it feeds the alarms above.

## AWS Config Rules (19)

**MAS TRM 9 - Access Control:** Root key check, MFA console, root MFA, password policy, no user inline policies

**MAS TRM 10.2 - Cryptographic Key Management:** KMS key rotation

**MAS TRM 11 - Data & Network:** S3 encryption, no public S3, SSL-only S3, VPC flow logs, no open SSH, default SG closed, EBS encryption

**MAS TRM 12.2 - Cyber Event Monitoring and Detection (audit logging):** CloudTrail enabled, log validation, CloudTrail encrypted. These logs serve as evidence for the independent IT audit function (TRM 15.1). The rule names keep their original `mas-trm-15-` prefix.

**PDPA:** RDS encryption, RDS no public access

The `ComplianceRuleCount` stack output reports the number of rules (19).

**Prerequisite: a configuration recorder.** AWS Config rules only evaluate resources that a configuration recorder records, and creating a rule fails if the account and region have no recorder. Each account and region supports one recorder and one delivery channel, so:

- Keep `createConfigRecorder: false` (default) where AWS Control Tower, an organization-wide setup or another stack already runs a recorder. The rules use it.
- Set `createConfigRecorder: true` otherwise. ComplianceStack then creates a recorder for all supported resource types (including the global IAM types, unless `configRecorderGlobalResources: false`; record them in one region only), a delivery channel with daily snapshots, a dedicated bucket (`kiro-banking-config-<env>-<account>`: KMS-encrypted with its own rotating key, versioned, SSL-only, public access blocked, server access logs to `kiro-banking-config-access-logs-<env>-<account>`, no Object Lock because AWS Config cannot deliver to Object Lock buckets) and an IAM role that trusts AWS Config for this account only and uses the AWS managed `AWS_ConfigRole` policy. All rules depend on the recorder and the delivery channel.

