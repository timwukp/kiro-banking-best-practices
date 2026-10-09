# AWS Kiro Agentic Code in SDLC Best Practices for Banking Developers
## Singapore MAS-Aligned Secure Development Framework

> **Audience:** security architects, banking developers, cloud ops · **Purpose:** Sections 1–4 — authentication, network isolation, and VDI for a MAS-aligned Kiro deployment · **Prerequisites:** AWS Organization + enterprise IdP · ↩ [README](README.md)

**Version:** 1.0  
**Date:** February 2026  
**Target Audience:** Banking Development Teams in Singapore  
**Regulatory Frameworks:**
- Monetary Authority of Singapore (MAS) Technology Risk Management (TRM) Guidelines (18 January 2021), which apply to all MAS-regulated financial institutions
- MAS Notice [FSM-N05](https://www.mas.gov.sg/regulation/notices/notice-fsm-n05) (Technology Risk Management) and Notice [FSM-N06](https://www.mas.gov.sg/regulation/notices/notice-fsm-n06) (Cyber Hygiene), binding for banks from 10 May 2024; other sectors have equivalent notices (see [README – Applicability](README.md#applicability-across-mas-regulated-financial-institutions))
- MAS [Notice 658](https://www.mas.gov.sg/regulation/notices/notice-658) and [Guidelines on Outsourcing (Banks)](https://www.mas.gov.sg/regulation/guidelines/guidelines-on-outsourcing-banks) for banks, and [Guidelines on Outsourcing (Financial Institutions other than Banks)](https://www.mas.gov.sg/regulation/guidelines/guidelines-on-outsourcing-financial-institutions-other-than-banks) for other FIs, effective 11 December 2024 (the 2016/2018 Guidelines on Outsourcing are cancelled)
- MAS [Guidelines on Artificial Intelligence Risk Management](https://www.mas.gov.sg/regulation/guidelines/guidelines-on-artificial-intelligence-risk-management-for-financial-institutions), published 7 October 2026, effective 7 October 2027

---

## Executive Summary

This document provides comprehensive best practices for Singapore banking developers using AWS Kiro in secure, MAS-aligned Software Development Life Cycle (SDLC) environments. It addresses end-to-end security from prototype to production, with emphasis on Enterprise Identity Provider (IdP) integration, VPC isolation, Virtual Desktop Infrastructure (VDI) controls, and Model Context Protocol (MCP) server governance.

**Key Security Principles:**
- **Zero Trust Architecture**: All access authenticated and authorized through Enterprise IdP
- **Network Isolation**: Private subnets with in-region VPC endpoints for AWS services, and an allowlisted HTTPS egress path for Kiro (optionally AWS PrivateLink in the Kiro profile region)
- **Controlled Environment**: Amazon WorkSpaces VDI with DLP enforcement
- **MCP Governance**: Centrally managed whitelist with developer restrictions
- **MAS Alignment**: Designed to support alignment with the MAS Technology Risk Management Guidelines and applicable MAS Notices; each institution remains responsible for its own compliance assessment

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Authentication & Identity Management](#2-authentication--identity-management)
3. [Network Security Architecture](#3-network-security-architecture)
4. [Virtual Desktop Infrastructure (VDI)](#4-virtual-desktop-infrastructure-vdi)
5. [MCP Server Security & Governance](#5-mcp-server-security--governance)
6. [SDLC Security Controls](#6-sdlc-security-controls)
7. [Data Protection & Encryption](#7-data-protection--encryption)
8. [Compliance & Audit](#8-compliance--audit)
9. [Operational Best Practices](#9-operational-best-practices)
10. [Incident Response](#10-incident-response)

---

## 1. Architecture Overview

### 1.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Enterprise IdP (SSO)                     │
│                (SAML 2.0 / SCIM Integration)                │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                AWS IAM Identity Center (IDC)                │
│       Identity region, e.g. ap-southeast-1 (Singapore)      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│       Corporate VPC - workload region (ap-southeast-1)      │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                Amazon WorkSpaces (VDI)                │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │          Developer Desktop Environment          │  │  │
│  │  │  - Kiro CLI/IDE Installed                       │  │  │
│  │  │  - Sign-in limited to IdC (managed settings)    │  │  │
│  │  │  - DLP Agent Running                            │  │  │
│  │  │  - Centralized MCP Configuration                │  │  │
│  │  │  - No Local Admin Rights                        │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └─────────────┬───────────────────────────┬─────────────┘  │
│                │                           │                │
│                ▼                           ▼                │
│  ┌──────────────────────────┐ ┌──────────────────────────┐  │
│  │ AWS service endpoints    │ │ Allowlisted HTTPS egress │  │
│  │ (PrivateLink, in-region) │ │ (sign-in, downloads,     │  │
│  │ - logs, kms, sts         │ │  Kiro APIs; Section 3.3) │  │
│  │ - s3 (gateway)           │ │ via proxy, inspection    │  │
│  │ No Kiro endpoints exist  │ │ VPC or NAT + DNS         │  │
│  │ in ap-southeast-1        │ │ Firewall (Section 3.4)   │  │
│  └──────────────────────────┘ └────────────┬─────────────┘  │
└────────────────────────────────────────────┼────────────────┘
                                             │ HTTPS
                                             ▼
┌─────────────────────────────────────────────────────────────┐
│   Kiro service - profile region (us-east-1 / eu-central-1)  │
│  - Stores and processes prompts, code context, responses    │
│  - May process in other regions of the same geography       │
│    (Global-scope models such as GPT-5.6: worldwide)         │
│  - Kiro endpoints (PrivateLink, profile region only):       │
│      com.amazonaws.us-east-1.q                              │
│      com.amazonaws.us-east-1.codewhisperer                  │
│      com.amazonaws.eu-central-1.q                           │
│    (optional; reached via a Kiro access VPC, Section 3.4)   │
└─────────────────────────────────────────────────────────────┘
```

The diagram shows Option A (IAM Identity Center). In Option B the enterprise IdP federates directly with Kiro and there is no IAM Identity Center box; the network design is the same. Kiro PrivateLink endpoints exist only in the Kiro profile region, and sign-in, downloads and `app.kiro.dev` are public HTTPS endpoints, so every design needs an allowlisted egress path (Section 3).

> **Data location: two regions to keep apart.**
> - **Workload region (`ap-southeast-1`):** the institution's own infrastructure: VPC, WorkSpaces, CloudTrail, AWS Config and AWS Backup (the CDK stacks in this repo). With Option A, IAM Identity Center can also run in `ap-southeast-1`, so identities and subscriptions can stay in Singapore.
> - **Kiro profile region (`us-east-1` or `eu-central-1`; there is no Singapore profile region):** Kiro stores and processes prompts, code context and responses here. Requests may be processed in other regions of the same geography (US or Europe; there is no Asia Pacific geography). Inference scope is set per model ([Kiro models page](https://kiro.dev/docs/models/)): Geography-scope models, which include all Claude models, stay within that geography, while Global-scope models (currently GPT-5.6 Sol, Terra and Luna) may be processed in supported commercial AWS Regions worldwide and use the US endpoint even for `eu-central-1` profiles; experimental or preview status does not determine routing. The network path (egress or PrivateLink) does not change this.
>
> Treat Kiro use as a cross-border transfer: apply the PDPA Transfer Limitation Obligation (s26), assess Kiro under MAS TRM 3.4 and the MAS outsourcing guidelines, keep customer information out of prompts and code context (banks: FSM-N05 para 9 and banking secrecy), and use model governance to exclude Global-scope models (and review preview terms such as Claude Fable 5.1's 30-day retention). MAS TRM does not impose a data-localisation mandate. See [Part 2, Section 7.2](Kiro-Banking-Best-Practices-Part2.md#72-data-location--residency) and the Kiro docs on [supported regions](https://kiro.dev/docs/enterprise/supported-regions/) and [data protection](https://kiro.dev/docs/privacy-and-security/data-protection/) (verified 2026-10-08).

### 1.2 Security Layers

| Layer | Component | MAS Alignment |
|-------|-----------|---------------|
| **Identity** | Enterprise IdP + IAM IDC | User and Privileged Access Management (Sections 9.1, 9.2) |
| **Network** | Private VPC + VPC endpoints + allowlisted egress | Network Security (Section 11.2) |
| **Compute** | Amazon WorkSpaces VDI | Remote Access Management (Section 9.3); System and Virtualisation Security (Sections 11.3, 11.4) |
| **Application** | Kiro with MCP Controls | Management of Third Party Services (Section 3.4); review and testing of third-party code, incl. MCP servers (Section 6.1.3); Network Security (Section 11.2) |
| **Data** | Encryption at Rest/Transit | Data Security (Section 11.1); Cryptography (Sections 10.1, 10.2) |
| **Monitoring** | CloudTrail + CloudWatch | Cyber Event Monitoring and Detection (Section 12.2); evidence for IT Audit (Section 15) |

---

## 2. Authentication & Identity Management

### 2.1 Enterprise IdP Integration with AWS IAM Identity Center

**Requirement:** All Kiro access MUST be authenticated through Enterprise IdP integrated with AWS IAM Identity Center (IDC).

#### 2.1.1 IdP Configuration

**Supported Identity Providers:**
- Microsoft Azure Active Directory
- Okta
- Ping Identity
- Any SAML 2.0 compliant IdP

**Integration Steps:**

1. **Enable IAM Identity Center**
```bash
# Enable IAM Identity Center in your AWS Organization.
# ap-southeast-1 keeps identities and subscriptions in Singapore; the Kiro profile
# region (us-east-1 or eu-central-1) can be a different region.
aws sso-admin create-instance \
  --region ap-southeast-1
```

2. **Configure SAML Integration**
- IdP Entity ID: `https://<idc-directory-id>.awsapps.com/start`
- ACS URL: `https://<idc-directory-id>.awsapps.com/sso/saml`
- SAML Attributes Required:
  - `email` (required)
  - `firstName` (required)
  - `lastName` (required)
  - `groups` (recommended for role mapping)

3. **Enable SCIM Provisioning**
```
SCIM Endpoint: https://scim.<region>.amazonaws.com/<directory-id>/scim/v2/
```

#### 2.1.2 Kiro Subscription Assignment

**Centralized User Management:**

```bash
# Assign Kiro subscription to users/groups via IAM IDC
aws sso-admin create-account-assignment \
  --instance-arn arn:aws:sso:::instance/<instance-id> \
  --target-id <aws-account-id> \
  --target-type AWS_ACCOUNT \
  --permission-set-arn arn:aws:sso:::permissionSet/<permission-set-id> \
  --principal-type GROUP \
  --principal-id <group-id>
```

**Access Control Matrix:**

| Role | Kiro Access | MCP Permissions | Admin Console |
|------|-------------|-----------------|---------------|
| **Developer** | Full | Whitelist Only | No |
| **Lead Developer** | Full | Whitelist + Request | No |
| **Security Admin** | Read-Only | Full Control | Yes |
| **Compliance Officer** | Audit Only | Read-Only | Yes |

#### 2.1.3 Session Management

**MAS alignment:** Multi-factor authentication for privileged access (TRM 9.2; for banks, Notice FSM-N06 para 4.6 requires MFA for all administrative accounts on critical systems)

**Configuration:**
- **Session Duration:** 90 days maximum (with hourly refresh)
- **MFA Enforcement:** Required for all users
- **Session Timeout:** 2 hours maximum (configurable via IdP)
- **Concurrent Sessions:** Limited to 3 per user

**IdP Session Policy Example (Azure AD):**
```json
{
  "sessionControls": {
    "applicationEnforcedRestrictions": null,
    "cloudAppSecurity": null,
    "persistentBrowser": {
      "mode": "never",
      "isEnabled": true
    },
    "signInFrequency": {
      "value": 2,
      "type": "hours",
      "isEnabled": true
    }
  }
}
```

### 2.2 Blocking Social Logins & Builder IDs

**Critical Security Control:** Prevent unauthorized access via consumer authentication methods.

> **Do not block `prod.us-east-1.auth.desktop.kiro.dev` or `app.kiro.dev`.** Kiro uses them for the sign-in portal and for token exchange, refresh and logout with every sign-in method, including IAM Identity Center. Blocking them breaks sign-in for all users. If you deployed the block list from an earlier version of this guide, remove those entries.

**Where the controls sit:**

| Layer | Control | Nature |
|-------|---------|--------|
| **Identity (authoritative)** | Only users in your IdP / IAM Identity Center who hold a Kiro subscription can use the organization's Kiro profile (Section 2.1.2) | Server-side access control |
| **Client** | `managed-settings.json` sign-in controls limit the methods Kiro offers (Section 2.2.1) | Client-enforced guardrail |
| **Network** | Default-deny egress allowlist (Section 3.3); optional explicit deny of the social sign-in host (Section 2.2.2) | Network guardrail |

The client and network controls reduce the chance that a personal account (AWS Builder ID, Google, GitHub) is used on a managed device. They do not replace identity and subscription management, which is the real access control.

#### 2.2.1 Restrict Sign-in Methods with Managed Settings

Kiro reads sign-in controls from a `managed-settings.json` file at an OS-protected path; changing the file requires administrator or root access. Deploy it with MDM, GPO or the WorkSpaces image build, and give standard users read-only access to the file and its folder.

| OS | Path |
|----|------|
| macOS | `/Library/Application Support/Kiro/managed-settings.json` |
| Windows | `C:\ProgramData\Kiro\managed-settings.json` (UTF-8 without BOM) |
| Linux | `/etc/kiro/managed-settings.json` |

**Option A (IAM Identity Center only):**
```json
{
  "rules": [
    {
      "capability": "signin_method",
      "match": ["*"],
      "exclude": ["idc"],
      "effect": "deny"
    }
  ],
  "settings": {
    "idc_start_url": "https://d-xxxxxxxxxx.awsapps.com/start",
    "idc_region": "ap-southeast-1",
    "signin_help_url": "https://it.example.com/kiro-help"
  }
}
```

Replace `d-xxxxxxxxxx` with your IAM Identity Center directory ID or alias. `idc_region` is the IAM Identity Center region, not the Kiro profile region.

**Option B (direct IdP federation):** use `"exclude": ["external_idp"]`, and in `settings` set `external_idp_domain` (the domain that identifies your organization) and, optionally, `external_idp_region` (the region where the external IdP connection is configured).

**Caveats:**
- **Version:** applies to Kiro IDE 1.2 and later and Kiro CLI 2.25.0 and later. Older clients ignore the rule, so enforce a minimum client version.
- **Client-enforced:** the rule does not apply to Kiro Web or to devices without the file, and a user with local administrator rights can remove it (Section 4.1.2 removes local admin rights).
- **Fails open:** if the rules deny every method, or the file cannot be read or is invalid (not valid JSON, not UTF-8, or starts with a byte order mark), Kiro drops the restriction and offers every method. On Windows, Windows PowerShell 5.1 `Out-File -Encoding UTF8` writes a BOM; write the file with `[System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding $false))` instead.
- **Shared file:** the same file holds Kiro permission policies, and an invalid file also blocks the agent's tools until it is fixed. Keep a `rules` array in the file even when it only carries `settings`, and validate the file before rollout.
- **Verify** on a test WorkSpace: sign out, sign in again, and confirm that only "Your organization" is offered with the start URL and region prefilled, and that no managed-settings warning appears.

Source: [Kiro Docs: Sign-in controls](https://kiro.dev/docs/enterprise/governance/sign-in/) (verified 2026-10-08).

#### 2.2.2 Network-Layer Guardrails

Network rules are a secondary control:
- Apply the default-deny allowlist in Section 3.3. Allow only your own IAM Identity Center portal host (`<idc-directory-id-or-alias>.awsapps.com`, for example `d-xxxxxxxxxx.awsapps.com`), not `*.awsapps.com`, and do not use the broad `*.amazonaws.com` wildcard. Hosts that are not on the allowlist, such as the shared AWS Builder ID portal (`view.awsapps.com`), are then blocked by the default deny.
- Optionally deny the social sign-in host `cognito-identity.us-east-1.amazonaws.com` (Google and GitHub sign-in) with an explicit rule ahead of any allow rule, so that a later wildcard cannot re-open it. The rule template in Section 3.3 includes this deny.
- Leave `billing.stripe.com` and `checkout.stripe.com` off the allowlist. Kiro uses them only for personal plans (Google, GitHub or AWS Builder ID sign-in); organizations that use IAM Identity Center do not need them.

#### 2.2.3 WorkSpaces Security Group

Security groups match IP addresses, CIDR ranges, prefix lists and other security groups, not domain names, so a rule cannot express "HTTPS except blocked domains". Allow outbound HTTPS only towards the egress path, and do the domain filtering there with a proxy, AWS Network Firewall or Route 53 Resolver DNS Firewall (Section 3.4):

- **Explicit proxy** (for example in a central egress VPC): allow TCP only to the proxy address on its listener port. Kiro honours `HTTPS_PROXY`, `HTTP_PROXY` and `NO_PROXY` and its own Settings > Proxy, but browser-based sign-in uses the operating system's network stack and bypasses Kiro's proxy settings, so also set the system or browser proxy (for example by GPO or a PAC file).

```json
{
  "IpPermissions": [],
  "IpPermissionsEgress": [
    {
      "IpProtocol": "tcp",
      "FromPort": 8080,
      "ToPort": 8080,
      "IpRanges": [
        {
          "CidrIp": "10.100.0.0/24",
          "Description": "Central egress proxy (domain allowlist enforced by the proxy)"
        }
      ]
    }
  ]
}
```

- **Transparent path** (NAT gateway with DNS Firewall, or a Transit Gateway route to an inspection VPC with AWS Network Firewall): the security group sees the final public destination address, not the NAT gateway or firewall, so the rule must be TCP 443 to `0.0.0.0/0`. The route table is what forces the traffic through the inspection path (the only default route points to the NAT gateway or Transit Gateway), and DNS Firewall or Network Firewall does the domain filtering. The CDK `nat-dns-firewall` mode uses this pattern.

```json
{
  "IpPermissions": [],
  "IpPermissionsEgress": [
    {
      "IpProtocol": "tcp",
      "FromPort": 443,
      "ToPort": 443,
      "IpRanges": [
        {
          "CidrIp": "0.0.0.0/0",
          "Description": "HTTPS via the inspection path only (route table); domains filtered by DNS Firewall or Network Firewall"
        }
      ]
    }
  ]
}
```

Section 3.2.1 shows the complete WorkSpaces security group, including the VPC endpoint rules.

### 2.3 CloudTrail Logging for Audit

**MAS alignment:** Comprehensive audit trail for all access and actions (TRM 12.2 Cyber Event Monitoring and Detection)

**Enable CloudTrail for Kiro:**
```bash
aws cloudtrail create-trail \
  --name kiro-audit-trail \
  --s3-bucket-name kiro-audit-logs-<account-id> \
  --include-global-service-events \
  --is-multi-region-trail \
  --enable-log-file-validation

# Enable data events for Kiro
aws cloudtrail put-event-selectors \
  --trail-name kiro-audit-trail \
  --event-selectors '[{
    "ReadWriteType": "All",
    "IncludeManagementEvents": true,
    "DataResources": [{
      "Type": "AWS::Q::*",
      "Values": ["arn:aws:q:*:*:*"]
    }]
  }]'
```

**Key Events to Monitor:**
- User authentication (success/failure)
- Kiro API calls (chat, code generation, MCP tool usage)
- MCP server configuration changes
- Administrative actions
- Data access patterns

---

## 3. Network Security Architecture

### 3.1 VPC Configuration for Kiro Access

**Objective:** Keep developer desktops off the open internet. WorkSpaces run in private subnets with no direct internet route, AWS services are reached through VPC endpoints in the workload region (`ap-southeast-1`), and Kiro is reached only through a controlled, allowlisted HTTPS egress path, optionally with AWS PrivateLink in the Kiro profile region for the Kiro APIs.

> **What PrivateLink can and cannot do for Kiro.** Kiro interface endpoints exist only in the Kiro profile regions: `us-east-1` and `eu-central-1` (and AWS GovCloud (US), which is not relevant here). There is no Kiro endpoint in `ap-southeast-1`, and AWS cross-Region PrivateLink does not support Kiro services. Where an endpoint is used, it carries only the Kiro service APIs (`q`, `runtime`, `management`, `telemetry`). Sign-in (`app.kiro.dev`, `prod.us-east-1.auth.desktop.kiro.dev`, the IAM Identity Center portal and OIDC endpoints), auto-updates and downloads, and IDE telemetry use public HTTPS endpoints that must be allowlisted (Section 3.3). Every design therefore needs an egress path (Section 3.4).

#### 3.1.1 VPC Design

**Network Architecture (workload region `ap-southeast-1`):**
```
Corporate VPC (10.0.0.0/16)
├── Private Subnet A (10.0.1.0/24) - WorkSpaces
├── Private Subnet B (10.0.2.0/24) - WorkSpaces
├── Private Subnet C (10.0.3.0/24) - VPC Endpoints
└── Private Subnet D (10.0.4.0/24) - VPC Endpoints
```

**No public subnets and no internet gateway in this VPC (default design).** AWS service traffic (CloudWatch Logs, KMS, STS, S3) stays on VPC endpoints in `ap-southeast-1`. Kiro traffic is not fully private: it leaves through the egress path in Section 3.4, for example a Transit Gateway route to a central inspection VPC or an explicit proxy. The CDK `egress.mode = 'nat-dns-firewall'` option is the exception; it adds a public subnet group with a NAT gateway to this VPC.

WorkSpaces is available only in some Availability Zones of each region, so place the WorkSpaces subnets in supported zones (see [Configure a VPC for WorkSpaces Personal](https://docs.aws.amazon.com/workspaces/latest/adminguide/amazon-workspaces-vpc.html)).

#### 3.1.2 VPC Interface Endpoints (AWS PrivateLink)

**AWS service endpoints in the workload region (`ap-southeast-1`):**

```bash
# Interface endpoints for AWS services used by the workload (CloudWatch Logs, KMS, STS)
for svc in logs kms sts; do
  aws ec2 create-vpc-endpoint \
    --region ap-southeast-1 \
    --vpc-id vpc-xxxxx \
    --vpc-endpoint-type Interface \
    --service-name "com.amazonaws.ap-southeast-1.${svc}" \
    --subnet-ids subnet-xxxxx subnet-yyyyy \
    --security-group-ids sg-xxxxx \
    --private-dns-enabled
done

# S3 gateway endpoint (CloudTrail log delivery, artifacts)
aws ec2 create-vpc-endpoint \
  --region ap-southeast-1 \
  --vpc-id vpc-xxxxx \
  --vpc-endpoint-type Gateway \
  --service-name com.amazonaws.ap-southeast-1.s3 \
  --route-table-ids rtb-xxxxx
```

The CDK network stack also creates an Identity Store (`identitystore`) endpoint for administrative automation. Kiro sign-in does not use it; sign-in uses the public IAM Identity Center portal and OIDC endpoints listed in Section 3.3.

**Kiro interface endpoints (Kiro profile region only):**

| Kiro profile region | Endpoint service names | Private DNS names served |
|---------------------|------------------------|--------------------------|
| US East (N. Virginia), `us-east-1` | `com.amazonaws.us-east-1.q`; `com.amazonaws.us-east-1.codewhisperer` (legacy, `us-east-1` only) | `q.us-east-1.amazonaws.com`, `runtime.us-east-1.kiro.dev`, `management.us-east-1.kiro.dev`, `telemetry.us-east-1.kiro.dev` |
| Europe (Frankfurt), `eu-central-1` | `com.amazonaws.eu-central-1.q` | `q.eu-central-1.amazonaws.com`, `runtime.eu-central-1.kiro.dev`, `management.eu-central-1.kiro.dev`, `telemetry.eu-central-1.kiro.dev` |

- `com.amazonaws.ap-southeast-1.q` and `com.amazonaws.ap-southeast-1.codewhisperer` do not exist. You can create Kiro endpoints only in a VPC in the profile region: a "Kiro access VPC" (Section 3.4, option 3) or a VDI VPC placed in the profile region.
- Kiro clients do not need an Amazon Bedrock endpoint. Earlier versions of this guide listed a `bedrock-runtime` endpoint; it is not used by Kiro clients and can be removed.

```bash
# Run against a VPC in the Kiro profile region (here us-east-1), not the Singapore VPC.
# Private DNS on an endpoint serves only the endpoint's own VPC. If clients in another
# VPC (for example the Singapore VPC) use the endpoint, disable private DNS and create
# the private hosted zones described in Section 3.4.
aws ec2 create-vpc-endpoint \
  --region us-east-1 \
  --vpc-id vpc-kiro-access \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.us-east-1.q \
  --subnet-ids subnet-aaaaa subnet-bbbbb \
  --security-group-ids sg-kiro-access-endpoints \
  --no-private-dns-enabled

# Legacy CodeWhisperer endpoint (us-east-1 only)
aws ec2 create-vpc-endpoint \
  --region us-east-1 \
  --vpc-id vpc-kiro-access \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.us-east-1.codewhisperer \
  --subnet-ids subnet-aaaaa subnet-bbbbb \
  --security-group-ids sg-kiro-access-endpoints \
  --no-private-dns-enabled

# Europe (Frankfurt) profile: create only com.amazonaws.eu-central-1.q, with --region eu-central-1
```

Source: [Kiro Docs: VPC endpoints (AWS PrivateLink)](https://kiro.dev/docs/privacy-and-security/vpc-endpoints/) and [AWS services that support cross-Region PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/aws-services-cross-region-privatelink-support.html) (verified 2026-10-08).

**Endpoint Security Group (workload-region endpoints):**
```json
{
  "GroupName": "kiro-vpc-endpoint-sg",
  "Description": "Security group for VPC interface endpoints",
  "VpcId": "vpc-xxxxx",
  "IpPermissions": [
    {
      "IpProtocol": "tcp",
      "FromPort": 443,
      "ToPort": 443,
      "UserIdGroupPairs": [
        {
          "GroupId": "sg-workspaces",
          "Description": "Allow HTTPS from WorkSpaces"
        }
      ]
    }
  ]
}
```

In a Kiro access VPC, the endpoint security group must allow TCP 443 from the Singapore VPC CIDR (for example `10.0.0.0/16`) instead, because security group references do not work across inter-Region peering.

#### 3.1.3 DNS Resolution

- **AWS service endpoints:** private DNS makes `logs.ap-southeast-1.amazonaws.com`, `kms.ap-southeast-1.amazonaws.com` and `sts.ap-southeast-1.amazonaws.com` resolve to private IP addresses in the endpoint subnets.
- **Kiro API names:** nothing in `ap-southeast-1` serves them. Unless you use option 3 in Section 3.4, they resolve to public IP addresses and the traffic must go through the allowlisted egress path. The queries are answered by the VPC resolver (Route 53 Resolver) or your directory's DNS servers; with DNS Firewall, queries for names outside the allowlist are blocked.
- **Option 3 (Kiro access VPC):** private hosted zones associated with the Singapore VPC resolve `q.<region>.amazonaws.com` and `runtime|management|telemetry.<region>.kiro.dev` to the private IP addresses of the endpoint in the profile region.
- **Sign-in hosts** (`app.kiro.dev`, `prod.us-east-1.auth.desktop.kiro.dev`, IAM Identity Center hosts) always resolve to public addresses.

**Verification:**
```bash
# From a WorkSpace in ap-southeast-1
nslookup logs.ap-southeast-1.amazonaws.com
# Expected: private IP in the endpoint subnets (10.0.3.x or 10.0.4.x)

nslookup runtime.us-east-1.kiro.dev
# Egress-only design: public IP (must be allowed by the egress allowlist)
# Kiro access VPC (Section 3.4, option 3): private IP of the endpoint in that VPC

nslookup prod.us-east-1.auth.desktop.kiro.dev
# Always public: used for sign-in, must be allowlisted
```

### 3.2 Network Access Control

#### 3.2.1 Security Group Rules

**WorkSpaces Security Group (Outbound), explicit proxy variant:**
```json
{
  "IpPermissionsEgress": [
    {
      "IpProtocol": "tcp",
      "FromPort": 443,
      "ToPort": 443,
      "UserIdGroupPairs": [
        {
          "GroupId": "sg-kiro-endpoints",
          "Description": "AWS service VPC endpoints (logs, kms, sts)"
        }
      ]
    },
    {
      "IpProtocol": "tcp",
      "FromPort": 443,
      "ToPort": 443,
      "PrefixListIds": [
        {
          "PrefixListId": "pl-xxxxx",
          "Description": "S3 Gateway Endpoint"
        }
      ]
    },
    {
      "IpProtocol": "tcp",
      "FromPort": 8080,
      "ToPort": 8080,
      "IpRanges": [
        {
          "CidrIp": "10.100.0.0/24",
          "Description": "Central egress proxy (Kiro allowlist, Section 3.3)"
        }
      ]
    }
  ]
}
```

For a transparent egress path, replace the proxy rule with TCP 443 to `0.0.0.0/0` and rely on the route table and DNS Firewall or Network Firewall for filtering (Section 2.2.3). Add the directory and DNS rules from Section 3.2.3.

#### 3.2.2 Network ACLs

**Endpoint subnet NACL (defense in depth; matches the CDK network stack):**
```
Inbound Rules:
- Rule 100: Allow TCP 443 from 10.0.0.0/16 (VPC CIDR)
- Rule 110: Allow TCP 1024-65535 from 10.0.0.0/16 (return traffic)
- Rule *: Deny all

Outbound Rules:
- Rule 100: Allow TCP 443 to 10.0.0.0/16
- Rule 110: Allow TCP 1024-65535 to 10.0.0.0/16 (return traffic)
- Rule *: Deny all
```

NACLs are stateless, so return traffic needs ephemeral-port rules in both directions. The WorkSpaces subnets need their own NACL: outbound to the egress path (for a transparent path, TCP 443 to `0.0.0.0/0` with inbound TCP 1024-65535 from `0.0.0.0/0` for the replies), plus the directory and DNS ports in Section 3.2.3. Test NACL changes on a non-production WorkSpace first.

#### 3.2.3 WorkSpaces and Directory Connectivity

Amazon WorkSpaces has its own documented network requirements, separate from Kiro:
- The WorkSpaces subnets must reach the directory (AWS Managed Microsoft AD, or AD Connector to your domain controllers) on the Active Directory ports (DNS, Kerberos, LDAP, SMB and related ports). WorkSpaces use the directory's DNS servers.
- Streaming between users' WorkSpaces clients and their WorkSpaces (HTTPS 443, plus PCoIP 4172 or WSP 4195) goes through the WorkSpaces gateways, not through the Kiro egress path in your VPC.

See [IP address and port requirements for WorkSpaces Personal](https://docs.aws.amazon.com/workspaces/latest/adminguide/workspaces-port-requirements.html), [Configure a VPC for WorkSpaces Personal](https://docs.aws.amazon.com/workspaces/latest/adminguide/amazon-workspaces-vpc.html) and [AD Connector prerequisites](https://docs.aws.amazon.com/directoryservice/latest/admin-guide/prereq_connector.html).

### 3.3 Firewall Configuration

Kiro makes two kinds of outbound connection, and the proxy or firewall must allow both:
- **Application traffic** from the Kiro process (chat, completions, telemetry, updates). It honours `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY` and Kiro's Settings > Proxy.
- **Browser traffic** for sign-in. It uses the operating system's network stack and bypasses Kiro's proxy settings.

**Allowlist (HTTPS, TCP 443; specific hostnames):**
```
# Core (all Kiro products)
app.kiro.dev                                  # sign-in portal
assets.app.kiro.dev                           # application assets

# Kiro IDE
prod.us-east-1.auth.desktop.kiro.dev          # token exchange, refresh, logout (every sign-in method)
prod.us-east-1.telemetry.desktop.kiro.dev     # telemetry
prod.download.desktop.kiro.dev                # auto-updates, Powers registry, icons
q.us-east-1.amazonaws.com                     # Kiro service, US East (legacy name, still required)
q.eu-central-1.amazonaws.com                  # Kiro service, Europe (legacy name, still required)
runtime.us-east-1.kiro.dev                    # Kiro service, US East
runtime.eu-central-1.kiro.dev                 # Kiro service, Europe
management.us-east-1.kiro.dev                 # configuration, access management, US East
management.eu-central-1.kiro.dev              # configuration, access management, Europe
telemetry.us-east-1.kiro.dev                  # telemetry, US East
telemetry.eu-central-1.kiro.dev               # telemetry, Europe

# Kiro CLI (in addition to the IDE list)
cli.kiro.dev
prod.download.cli.kiro.dev
desktop-release.q.us-east-1.amazonaws.com

# IAM Identity Center (Option A); <region> and <sso-region> are the Identity Center region, e.g. ap-southeast-1
<region>.signin.aws                           # AWS sign-in
<sso-region>.signin.aws.amazon.com            # AWS sign-in (alternate)
<idc-directory-id-or-alias>.awsapps.com       # your portal only, e.g. d-xxxxxxxxxx.awsapps.com
portal.sso.<sso-region>.amazonaws.com         # SSO portal
assets.sso-portal.<sso-region>.amazonaws.com  # SSO portal assets
oidc.<sso-region>.amazonaws.com               # OIDC token exchange

# External IdP (Option B, or an external IdP behind IAM Identity Center)
login.microsoftonline.com                     # Microsoft Entra ID
<your-org>.okta.com                           # Okta

# Optional: only if the feature is approved
open-vsx.org                                  # extensions: search and metadata
openvsx.eclipsecontent.org                    # extensions: icons and VSIX downloads
github.com                                    # Powers / MCP: repository cloning
raw.githubusercontent.com                     # Powers / MCP: config files and readme images

# Do not allow (enterprise)
cognito-identity.us-east-1.amazonaws.com      # Google / GitHub social sign-in
billing.stripe.com                            # personal-plan billing
checkout.stripe.com                           # personal-plan checkout
```

**Notes:**
- The Kiro docs list both profile regions (`us-east-1` and `eu-central-1`). Allow both unless you have tested sign-in and profile selection with your profile region only.
- The `q.<region>.amazonaws.com` names are legacy and will be deprecated, but they are still required.
- **Wildcards:** the Kiro docs also offer `*.kiro.dev`, `*.app.kiro.dev`, `*.kiro.aws.dev`, `*.amazonaws.com`, `*.shortbread.aws.dev` and `*.signin.aws`. Prefer the specific names above. `*.amazonaws.com` is too broad for a bank: it allows every AWS service endpoint, including any S3 bucket (a data exfiltration path) and the social sign-in host. Some firewalls match only one subdomain level; on those, `*.kiro.dev` does not cover `assets.app.kiro.dev`.
- The CDK `nat-dns-firewall` mode builds its DNS Firewall domain list from these hostnames (see [cdk/README.md](cdk/README.md)).

**Firewall Rule Template:**
```
# Pseudo-syntax for a proxy or firewall that matches FQDN or TLS SNI.
# Rules are evaluated top-down; the first match wins.
deny  tcp any any eq 443 host cognito-identity.us-east-1.amazonaws.com
allow tcp any any eq 443 host app.kiro.dev
allow tcp any any eq 443 host assets.app.kiro.dev
allow tcp any any eq 443 host prod.us-east-1.auth.desktop.kiro.dev
allow tcp any any eq 443 host <idc-directory-id-or-alias>.awsapps.com
# ... one allow rule for each remaining hostname in the allowlist above

# Deny all other HTTPS traffic
deny tcp any any eq 443
```

Source: [Kiro Docs: Firewalls, proxies, and data perimeters](https://kiro.dev/docs/privacy-and-security/firewalls/) (verified 2026-10-08).

### 3.4 Connectivity Options for Singapore Institutions

All three options keep the VPC and WorkSpaces in `ap-southeast-1`, and all of them need the Section 3.3 allowlist for sign-in and downloads. They differ in how the Kiro API traffic travels and in cost and complexity. None of them changes where Kiro stores or processes data (Section 1.1).

| Option | Kiro API traffic | Best for | Main trade-off |
|--------|------------------|----------|----------------|
| **1. Central egress** (recommended) | HTTPS through the landing-zone inspection VPC or an explicit proxy | Production, institutions with an existing landing zone | Depends on the central egress platform |
| **2. CDK `nat-dns-firewall`** | HTTPS through a NAT gateway in this VPC, filtered by DNS Firewall | PoC, development, accounts without central egress | DNS-based filtering only |
| **3. Kiro access VPC** (optional) | AWS PrivateLink in the profile region, over inter-Region peering or Transit Gateway | Keeping the Kiro APIs on the AWS network | Cost and complexity; egress still needed for sign-in |

#### Option 1: Central Egress through the Landing Zone (Recommended)

- Attach the WorkSpaces VPC to a Transit Gateway. Either route `0.0.0.0/0` to a central inspection VPC with AWS Network Firewall (domain list or TLS SNI rules), or route to an explicit proxy fleet in the central egress VPC. Apply the Section 3.3 allowlist there.
- This reuses the institution's existing internet egress controls, logging and change process, keeps one allowlist for all VPCs, and works with either profile region.
- With an explicit proxy, the WorkSpaces security group allows only the proxy (Section 2.2.3), and both the OS and Kiro are configured to use it. With a transparent Network Firewall, the security group allows TCP 443 to `0.0.0.0/0` and the route table sends it to the Transit Gateway.
- Log allowed and denied domains and feed them into security monitoring (Section 2.3).

#### Option 2: This Repo's CDK `nat-dns-firewall` Mode

- Set `egress: { mode: 'nat-dns-firewall', allowedDomains: [] }` in `cdk/config/environments.ts`, or pass `-c egress=nat-dns-firewall` to try it. The default, `mode: 'none'`, keeps the VPC without a NAT gateway or internet gateway; use it with option 1.
- The mode adds a public subnet group with one NAT gateway, makes the WorkSpaces subnets private with egress, and associates a Route 53 Resolver DNS Firewall rule group with the VPC: ALLOW the Kiro and IAM Identity Center domain list (priority 100), then BLOCK `*` with a NODATA response (priority 200). The WorkSpaces security group allows TCP 443 to `0.0.0.0/0`; DNS Firewall does the domain filtering.
- **Limits:**
  - DNS Firewall filters name resolution only. It does not stop a connection to a hard-coded IP address.
  - It sees only queries that reach the Route 53 Resolver of an associated VPC. WorkSpaces use the directory's DNS servers: AWS Managed Microsoft AD forwards other queries to the VPC resolver, so associate the rule group with the VPC where the domain controllers run. With AD Connector, WorkSpaces use your own DNS servers, which DNS Firewall does not see, so apply the allowlist there as well.
  - The BLOCK `*` rule applies to every query from the VPC. Add other domains the WorkSpaces need (for example OS updates or certificate revocation endpoints) to `allowedDomains`.
  - One NAT gateway keeps cost down but is a single-AZ dependency; use one NAT gateway per AZ for production.
  - For stronger enforcement, use AWS Network Firewall with TLS SNI inspection or an explicit proxy in a central inspection VPC (option 1).

#### Option 3: Kiro PrivateLink through a Kiro Access VPC (Optional)

Cross-Region PrivateLink does not support Kiro services, so this is the only way to use the Kiro endpoints from a Singapore VPC:
1. Create a small "Kiro access VPC" in the Kiro profile region (`us-east-1` or `eu-central-1`) with a CIDR that does not overlap the Singapore VPC.
2. Create the Kiro interface endpoints there with private DNS disabled (Section 3.1.2). The endpoint security group allows TCP 443 from the Singapore VPC CIDR.
3. Connect the two VPCs with inter-Region VPC peering or Transit Gateway inter-Region peering, and add routes in both directions.
4. Create Route 53 private hosted zones for `q.<region>.amazonaws.com`, `runtime.<region>.kiro.dev`, `management.<region>.kiro.dev` and `telemetry.<region>.kiro.dev`. In each zone, add an alias A record at the zone apex that points to the endpoint's regional DNS name, and associate the zone with the Singapore VPC.
5. Keep an egress path (option 1 or 2) for sign-in, downloads, `app.kiro.dev` and the IAM Identity Center and IdP hosts.

```bash
# Example for one name (repeat for q.us-east-1.amazonaws.com,
# management.us-east-1.kiro.dev and telemetry.us-east-1.kiro.dev)
aws route53 create-hosted-zone \
  --name runtime.us-east-1.kiro.dev \
  --vpc VPCRegion=ap-southeast-1,VPCId=vpc-xxxxx \
  --hosted-zone-config PrivateZone=true \
  --caller-reference "kiro-runtime-$(date +%s)"

aws route53 change-resource-record-sets \
  --hosted-zone-id <private-hosted-zone-id> \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "runtime.us-east-1.kiro.dev",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "<endpoint-dns-hosted-zone-id>",
          "DNSName": "<vpce-regional-dns-name>",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'
# <endpoint-dns-hosted-zone-id> and <vpce-regional-dns-name> come from:
# aws ec2 describe-vpc-endpoints --region us-east-1 --vpc-endpoint-ids vpce-xxxxx --query 'VpcEndpoints[0].DnsEntries[0]'
```

**Trade-offs:** the Kiro API traffic stays on the AWS network, but you pay for interface endpoint hours and data processing, inter-Region data transfer and any Transit Gateway attachments, and you operate extra routing and DNS. It does not remove the need for internet egress, and it does not change where Kiro stores or processes data. An alternative is to run the WorkSpaces in the profile region next to the endpoints, which moves the VDI out of Singapore and still needs egress for sign-in.

**References (verified 2026-10-08):**
- [Kiro Docs: VPC endpoints (AWS PrivateLink)](https://kiro.dev/docs/privacy-and-security/vpc-endpoints/)
- [Kiro Docs: Firewalls, proxies, and data perimeters](https://kiro.dev/docs/privacy-and-security/firewalls/)
- [AWS services that support cross-Region PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/aws-services-cross-region-privatelink-support.html)
- [Route 53 Resolver DNS Firewall](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/resolver-dns-firewall.html)
- [AWS Network Firewall: stateful domain list rule groups](https://docs.aws.amazon.com/network-firewall/latest/developerguide/stateful-rule-groups-domain-names.html)

---

## 4. Virtual Desktop Infrastructure (VDI)

### 4.1 Amazon WorkSpaces Configuration

**Rationale:** Centralized control over developer environments prevents unauthorized MCP server installation and ensures DLP enforcement.

#### 4.1.1 WorkSpaces Bundle Selection

**Recommended Configuration:**

| Component | Specification | Justification |
|-----------|---------------|---------------|
| **Bundle Type** | PowerPro or GraphicsPro | High-performance for development workloads |
| **vCPU** | 8+ cores | Kiro AI processing + IDE + build tools |
| **Memory** | 32 GB+ | Large codebases + AI context windows |
| **Storage** | 175 GB SSD | Root volume + user volume separation |
| **GPU** | Optional (Graphics.g4dn) | For ML model testing |

**Deployment Command:**
```bash
aws workspaces create-workspaces \
  --workspaces \
    DirectoryId=d-xxxxx,\
    UserName=[developer-username],\
    BundleId=wsb-xxxxx,\
    VolumeEncryptionKey=arn:aws:kms:region:account:key/xxxxx,\
    UserVolumeEncryptionEnabled=true,\
    RootVolumeEncryptionEnabled=true,\
    WorkspaceProperties={RunningMode=AUTO_STOP,RunningModeAutoStopTimeoutInMinutes=60},\
    Tags=[{Key=Environment,Value=Production},{Key=Compliance,Value=MAS}]
```

#### 4.1.2 Group Policy Configuration

**Windows Group Policy (GPO) Settings:**

**1. Disable Local Administrator Rights**
```
Computer Configuration > Windows Settings > Security Settings > Restricted Groups
- Administrators: <Empty> (remove all local admins)
```

**2. Application Whitelisting**
```
Computer Configuration > Windows Settings > Security Settings > Application Control Policies
- Allow: Kiro CLI, Kiro IDE, approved development tools
- Deny: All other executables
```

**3. USB/External Device Control**
```
Computer Configuration > Administrative Templates > System > Removable Storage Access
- All Removable Storage classes: Deny All Access
```

**4. Software Installation Restrictions**
```
Computer Configuration > Administrative Templates > Windows Components > Windows Installer
- Prohibit User Installs: Enabled
- Always install with elevated privileges: Disabled
```

#### 4.1.3 DLP Agent Deployment

**Data Loss Prevention Requirements:**

**Endpoint DLP Solution (Examples):**
- Symantec DLP
- McAfee Total Protection for DLP
- Microsoft Purview (formerly AIP)
- Forcepoint DLP

**DLP Policy Configuration:**

```json
{
  "dlp_policies": [
    {
      "name": "Prevent Code Exfiltration",
      "rules": [
        {
          "condition": "file_extension",
          "values": [".py", ".js", ".java", ".tf", ".yaml"],
          "action": "block",
          "channels": ["email", "usb", "cloud_upload", "clipboard"]
        }
      ]
    },
    {
      "name": "Protect Credentials",
      "rules": [
        {
          "condition": "content_pattern",
          "patterns": ["AWS_ACCESS_KEY", "AWS_SECRET", "password=", "api_key="],
          "action": "block_and_alert",
          "channels": ["all"]
        }
      ]
    },
    {
      "name": "Monitor Kiro Outputs",
      "rules": [
        {
          "condition": "application",
          "values": ["kiro.exe", "kiro-cli.exe"],
          "action": "log_and_monitor",
          "channels": ["clipboard", "file_save"]
        }
      ]
    }
  ]
}
```

**DLP Agent Installation (via GPO):**
```powershell
# Deploy DLP agent via startup script
$dlpInstaller = "\\fileserver\software\dlp-agent-installer.msi"
Start-Process msiexec.exe -ArgumentList "/i $dlpInstaller /quiet /norestart" -Wait
```

### 4.2 Centralized Configuration Management

#### 4.2.1 MCP Configuration Deployment

**Objective:** Prevent developers from installing unauthorized MCP servers.

**Centralized Configuration Location:**
```
\\fileserver\kiro-config\mcp.json (Read-Only for users)
```

**Deployment via GPO:**
```powershell
# Group Policy Startup Script
$source = "\\fileserver\kiro-config\mcp.json"
$destination = "C:\ProgramData\Kiro\mcp.json"

# Copy centralized config
Copy-Item -Path $source -Destination $destination -Force

# Set read-only permissions
$acl = Get-Acl $destination
$acl.SetAccessRuleProtection($true, $false)
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Users", "Read", "Allow")
$acl.AddAccessRule($rule)
Set-Acl $destination $acl

# Create symbolic link for user-level config (override)
$userConfig = "$env:USERPROFILE\.kiro\settings\mcp.json"
New-Item -ItemType SymbolicLink -Path $userConfig -Target $destination -Force
```

**File System Permissions:**
```
C:\ProgramData\Kiro\mcp.json
- SYSTEM: Full Control
- Administrators: Full Control
- Users: Read Only
```

#### 4.2.2 Workspace-Level Config Prevention

**Block Local MCP Configuration:**
```powershell
# GPO: Deny write access to workspace config locations
$workspaceConfigPaths = @(
    "$env:USERPROFILE\.kiro\settings",
    "$env:APPDATA\Kiro\settings"
)

foreach ($path in $workspaceConfigPaths) {
    if (Test-Path $path) {
        $acl = Get-Acl $path
        $denyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Users", "Write,CreateFiles,AppendData", "Deny"
        )
        $acl.AddAccessRule($denyRule)
        Set-Acl $path $acl
    }
}
```

### 4.3 Monitoring & Compliance

#### 4.3.1 WorkSpaces Monitoring

**CloudWatch Metrics:**
```bash
# Enable detailed monitoring
aws workspaces modify-workspace-properties \
  --workspace-id ws-xxxxx \
  --workspace-properties ComputeTypeName=PERFORMANCE,\
    RunningMode=AUTO_STOP,\
    RunningModeAutoStopTimeoutInMinutes=60,\
    UserVolumeSizeGib=100,\
    RootVolumeSizeGib=80
```

**Key Metrics to Monitor:**
- User connection duration
- Data transfer volumes
- Application usage patterns
- Failed authentication attempts
- DLP policy violations

#### 4.3.2 Compliance Validation

**Automated Compliance Checks:**
```powershell
# Daily compliance validation script
function Test-KiroCompliance {
    $results = @()
    
    # Check 1: MCP config is centralized
    $mcpConfig = "C:\ProgramData\Kiro\mcp.json"
    $results += @{
        Check = "Centralized MCP Config"
        Status = (Test-Path $mcpConfig) -and ((Get-Acl $mcpConfig).Access | Where-Object {$_.IdentityReference -eq "BUILTIN\Users" -and $_.FileSystemRights -eq "Read"})
    }
    
    # Check 2: DLP agent is running
    $results += @{
        Check = "DLP Agent Running"
        Status = (Get-Service -Name "DLPAgent" -ErrorAction SilentlyContinue).Status -eq "Running"
    }
    
    # Check 3: No local admin rights
    $results += @{
        Check = "No Local Admin"
        Status = -not (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
    }
    
    return $results
}

# Run and report
$complianceResults = Test-KiroCompliance
$complianceResults | Export-Csv -Path "\\fileserver\compliance\kiro-compliance-$(Get-Date -Format 'yyyyMMdd').csv" -Append
```

---

*[Document continues in next section...]*


---

## License & Disclaimer

This documentation is licensed under the [MIT License](LICENSE).

> **Disclaimer:** This documentation is provided for informational and educational purposes only. It does not constitute legal advice, regulatory guidance, or professional security consulting. Organizations must conduct independent security assessments, consult qualified professionals, and validate all implementations against their specific regulatory requirements. See [README.md](README.md#disclaimer) for full disclaimer.
