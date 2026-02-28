# Kiro Banking CDK Infrastructure

AWS CDK (TypeScript) modules for deploying MAS-compliant Kiro banking environments.

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
| **EncryptionStack** | 10 (Cryptography) | 3 KMS keys with rotation, strict policies |
| **NetworkStack** | 11.2 (Network Security) | VPC, 8 VPC endpoints, SGs, NACLs, flow logs |
| **MonitoringStack** | 15 (IT Audit) | CloudTrail, S3 log bucket, CloudWatch alarms, SNS |
| **ComplianceStack** | 9, 10, 11, 15 + PDPA | 18 AWS Config managed rules |

## Prerequisites

- Node.js 18+
- AWS CDK CLI: `npm install -g aws-cdk`
- AWS credentials configured
- CDK bootstrapped: `cdk bootstrap aws://ACCOUNT/ap-southeast-1`

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
```

## Configuration

Edit `config/environments.ts` to customize:

- VPC CIDR ranges
- Kiro service endpoints
- CloudTrail retention period
- Resource tags
- CDK Nag toggle

## CDK Nag

All stacks are validated with [cdk-nag](https://github.com/cdklabs/cdk-nag) AwsSolutions rule pack. Security suppressions include documented justifications.

## CloudWatch Alarms

| Alarm | MAS Section | Trigger |
|-------|-------------|---------|
| Unauthorized API calls | 9.1 | 5+ access denied in 5 min |
| Console sign-in without MFA | 9.1 | Any sign-in without MFA |
| IAM policy changes | 9.1 | Any policy create/delete/attach |
| Security group changes | 11.2 | Any SG rule modification |

## AWS Config Rules (18)

**MAS TRM 9 - Access Control:** Root key check, MFA console, root MFA, password policy, no user inline policies

**MAS TRM 10 - Cryptography:** KMS key rotation

**MAS TRM 11 - Data & Network:** S3 encryption, no public S3, SSL-only S3, VPC flow logs, no open SSH, default SG closed, EBS encryption

**MAS TRM 15 - Audit:** CloudTrail enabled, log validation, CloudTrail encrypted

**PDPA:** RDS encryption, RDS no public access
