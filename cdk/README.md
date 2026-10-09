# Kiro Banking CDK Infrastructure

AWS CDK (TypeScript) modules for deploying MAS-aligned Kiro banking environments.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ EncryptionStack                                         │
│  KMS Keys: Audit | Data | WorkSpaces                   │
└──────────────────────┬──────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
┌──────────────┐ ┌──────────┐ ┌──────────────┐
│ NetworkStack │ │Monitoring│ │ Compliance   │
│ VPC          │ │CloudTrail│ │ AWS Config   │
│ PrivateLink  │ │CloudWatch│ │ 18 rules     │
│ SGs + NACLs  │ │S3 Logs   │ │ MAS+PDPA     │
│ Flow Logs    │ │Alarms    │ │              │
└──────────────┘ └──────────┘ └──────────────┘
```

## Stacks

| Stack | MAS TRM Section | Resources |
|-------|-----------------|-----------|
| **EncryptionStack** | 10.2 (Cryptographic Key Management) | 3 KMS keys with rotation, strict policies |
| **NetworkStack** | 11.2 (Network Security) | VPC, 4 AWS interface endpoints + S3 gateway (Kiro endpoints only in the Kiro profile region), SGs, NACL, flow logs, optional NAT + DNS Firewall egress |
| **MonitoringStack** | 12.2 (Cyber Event Monitoring and Detection) | CloudTrail, S3 log bucket, CloudWatch alarms, SNS |
| **ComplianceStack** | 9, 10, 11, 12.2 + PDPA | 18 AWS Config managed rules |

## Prerequisites

- Node.js 18+
- AWS CDK CLI: `npm install -g aws-cdk`
- AWS credentials configured
- CDK bootstrapped: `cdk bootstrap aws://ACCOUNT/ap-southeast-1` (and any region you pass with `-c region=`)

## Quick Start

```bash
cd cdk
npm install

# Synthesize (validates all stacks + CDK Nag)
cdk synth

# Deploy to dev
cdk deploy --all -c env=dev

# Deploy to prod
cdk deploy --all -c env=prod

# Preview changes
cdk diff

# Optional overrides (see "Network and Kiro connectivity")
cdk synth -c env=dev -c egress=nat-dns-firewall   # self-contained filtered egress
cdk synth -c env=dev -c region=us-east-1          # workload in the Kiro profile region
```

## Configuration

Edit `config/environments.ts` to customize:

- VPC CIDR ranges
- Kiro profile region (`kiroProfileRegion`: `us-east-1` or `eu-central-1`)
- IAM Identity Center region, access portal host and external IdP host (used for the egress allowlist)
- Egress mode (`egress.mode`) and extra allowed domains (`egress.allowedDomains`)
- Optional subset of Kiro endpoints (`kiroEndpoints`, normally empty)
- CloudTrail retention period
- Resource tags
- CDK Nag toggle

Kiro regions, endpoint service names and the egress allowlist live in `config/kiro-endpoints.ts`.

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

### Known limitations

- The endpoint NACL is not associated with any subnet, so its entries do not filter traffic yet.
- In `egress.mode = 'none'` the WorkSpaces security group has only a security-group-to-security-group egress rule, so EC2's default allow-all egress rule remains on it (the isolated subnets still have no internet route).

## CDK Nag

All stacks are validated with [cdk-nag](https://github.com/cdklabs/cdk-nag) AwsSolutions rule pack. Security suppressions include documented justifications.

## CloudWatch Alarms

| Alarm | MAS Section | Trigger |
|-------|-------------|---------|
| Unauthorized API calls | 12.2 / 9.1 | 5+ access denied in 5 min |
| Console sign-in without MFA | 12.2 / 9.1 | Any sign-in without MFA |
| IAM policy changes | 12.2 / 9.2 | Any policy create/delete/attach |
| Security group changes | 12.2 / 11.2 | Any SG rule modification |

## AWS Config Rules (18)

**MAS TRM 9 - Access Control:** Root key check, MFA console, root MFA, password policy, no user inline policies

**MAS TRM 10.2 - Cryptographic Key Management:** KMS key rotation

**MAS TRM 11 - Data & Network:** S3 encryption, no public S3, SSL-only S3, VPC flow logs, no open SSH, default SG closed, EBS encryption

**MAS TRM 12.2 - Cyber Event Monitoring and Detection (audit logging):** CloudTrail enabled, log validation, CloudTrail encrypted. These logs serve as evidence for the independent IT audit function (TRM 15.1). The rule names keep their original `mas-trm-15-` prefix.

**PDPA:** RDS encryption, RDS no public access
