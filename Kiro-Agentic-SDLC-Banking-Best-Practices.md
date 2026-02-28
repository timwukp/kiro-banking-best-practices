# AWS Kiro Agentic Code in SDLC Best Practices for Banking Developers
## Singapore MAS-Compliant Secure Development Framework

**Version:** 1.0  
**Date:** February 2026  
**Target Audience:** Banking Development Teams in Singapore  
**Compliance Framework:** Monetary Authority of Singapore (MAS) Technology Risk Management Guidelines

---

## Executive Summary

This document provides comprehensive best practices for Singapore banking developers using AWS Kiro in secure, MAS-compliant Software Development Life Cycle (SDLC) environments. It addresses end-to-end security from prototype to production, with emphasis on Enterprise Identity Provider (IdP) integration, VPC isolation, Virtual Desktop Infrastructure (VDI) controls, and Model Context Protocol (MCP) server governance.

**Key Security Principles:**
- **Zero Trust Architecture**: All access authenticated and authorized through Enterprise IdP
- **Network Isolation**: End-to-end VPC connectivity with AWS PrivateLink
- **Controlled Environment**: Amazon WorkSpaces VDI with DLP enforcement
- **MCP Governance**: Centrally managed whitelist with developer restrictions
- **MAS Compliance**: Alignment with Technology Risk Management Guidelines

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
│                    Enterprise IdP (SSO)                      │
│              (SAML 2.0 / SCIM Integration)                   │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              AWS IAM Identity Center (IDC)                   │
│         (Centralized Access Management)                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│                  Corporate VPC                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         Amazon WorkSpaces (VDI)                       │  │
│  │  ┌────────────────────────────────────────────────┐  │  │
│  │  │  Developer Desktop Environment                  │  │  │
│  │  │  - Kiro CLI/IDE Installed                      │  │  │
│  │  │  - DLP Agent Running                           │  │  │
│  │  │  - Centralized MCP Configuration               │  │  │
│  │  │  - No Local Admin Rights                       │  │  │
│  │  └────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────┘  │
│                     │                                        │
│                     │ (VPC Endpoint - AWS PrivateLink)       │
│                     ▼                                        │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         VPC Interface Endpoints                       │  │
│  │  - com.amazonaws.region.q                           │  │
│  │  - com.amazonaws.region.codewhisperer               │  │
│  │  - com.amazonaws.region.bedrock                     │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              AWS Kiro Service (Private)                      │
│         (No Internet Exposure Required)                      │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Security Layers

| Layer | Component | MAS Alignment |
|-------|-----------|---------------|
| **Identity** | Enterprise IdP + IAM IDC | Access Control (Section 9) |
| **Network** | VPC + PrivateLink | Network Security (Section 11.2) |
| **Compute** | Amazon WorkSpaces VDI | Data Centre Resilience (Section 8.5) |
| **Application** | Kiro with MCP Controls | Application Security (Annex A) |
| **Data** | Encryption at Rest/Transit | Data Security (Section 11.1) |
| **Monitoring** | CloudTrail + CloudWatch | Audit & Monitoring (Section 15) |

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
# Enable IAM Identity Center in your AWS Organization
aws sso-admin create-instance \
  --region us-east-1
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

**MAS Compliance Requirement:** Multi-factor authentication for privileged access

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

#### 2.2.1 Firewall Blocklist

**URLs to Block:**
```
https://view.awsapps.com/start
https://d-9067642ac7.awsapps.com/start
https://prod.us-east-1.auth.kiro.aws.dev
https://prod.us-east-1.auth.desktop.kiro.dev
https://kiro-prod-us-east1.auth.us-east-1.amazoncognito.com
```

#### 2.2.2 Network Policy Enforcement

**Corporate Firewall Rule:**
```
# Deny outbound to consumer auth endpoints
deny tcp any any eq 443 host view.awsapps.com
deny tcp any any eq 443 host prod.us-east-1.auth.kiro.aws.dev
deny tcp any any eq 443 host kiro-prod-us-east1.auth.us-east-1.amazoncognito.com
```

**VPC Security Group (WorkSpaces):**
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
          "Description": "HTTPS - Except blocked domains"
        }
      ]
    }
  ]
}
```

### 2.3 CloudTrail Logging for Audit

**MAS Requirement:** Comprehensive audit trail for all access and actions

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

**Objective:** Eliminate internet exposure by routing all Kiro traffic through private VPC endpoints.

#### 3.1.1 VPC Design

**Network Architecture:**
```
Corporate VPC (10.0.0.0/16)
├── Private Subnet A (10.0.1.0/24) - WorkSpaces
├── Private Subnet B (10.0.2.0/24) - WorkSpaces
├── Private Subnet C (10.0.3.0/24) - VPC Endpoints
└── Private Subnet D (10.0.4.0/24) - VPC Endpoints
```

**No Public Subnets Required** - All traffic remains private.

#### 3.1.2 VPC Interface Endpoints (AWS PrivateLink)

**Required Endpoints for Kiro:**

```bash
# Create VPC endpoint for Kiro service
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxx \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.us-east-1.q \
  --subnet-ids subnet-xxxxx subnet-yyyyy \
  --security-group-ids sg-xxxxx \
  --private-dns-enabled

# Create VPC endpoint for CodeWhisperer (legacy support)
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxx \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.us-east-1.codewhisperer \
  --subnet-ids subnet-xxxxx subnet-yyyyy \
  --security-group-ids sg-xxxxx \
  --private-dns-enabled

# Create VPC endpoint for Bedrock (foundation models)
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxx \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.us-east-1.bedrock-runtime \
  --subnet-ids subnet-xxxxx subnet-yyyyy \
  --security-group-ids sg-xxxxx \
  --private-dns-enabled
```

**Endpoint Security Group:**
```json
{
  "GroupName": "kiro-vpc-endpoint-sg",
  "Description": "Security group for Kiro VPC endpoints",
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

#### 3.1.3 DNS Resolution

**Private DNS Configuration:**
- Enable Private DNS for VPC endpoints
- Kiro clients automatically resolve to private IPs
- No DNS queries leave the VPC

**Verification:**
```bash
# From WorkSpaces instance
nslookup q.us-east-1.amazonaws.com
# Should return private IP (10.0.x.x)
```

### 3.2 Network Access Control

#### 3.2.1 Security Group Rules

**WorkSpaces Security Group (Outbound):**
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
          "Description": "Kiro VPC Endpoints"
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
    }
  ]
}
```

#### 3.2.2 Network ACLs

**Subnet NACL (Defense in Depth):**
```
Inbound Rules:
- Rule 100: Allow TCP 443 from 10.0.0.0/16
- Rule *: Deny all

Outbound Rules:
- Rule 100: Allow TCP 443 to 10.0.0.0/16
- Rule 110: Allow TCP 1024-65535 (ephemeral ports)
- Rule *: Deny all
```

### 3.3 Firewall Configuration

**Required URLs for Allowlist:**

**Authentication (via VPC Endpoint):**
```
*.kiro.dev
<idc-directory-id>.awsapps.com
oidc.<sso-region>.amazonaws.com
*.sso.<sso-region>.amazonaws.com
*.sso-portal.<sso-region>.amazonaws.com
```

**Kiro Service (via VPC Endpoint):**
```
https://aws-toolkit-language-servers.amazonaws.com/
https://aws-language-servers.us-east-1.amazonaws.com/
```

**Telemetry (Optional - can be disabled):**
```
https://client-telemetry.us-east-1.amazonaws.com
https://prod.us-east-1.telemetry.desktop.kiro.dev
```

**Firewall Rule Template:**
```
# Allow only required Kiro endpoints
allow tcp any any eq 443 host *.kiro.dev
allow tcp any any eq 443 host <idc-directory-id>.awsapps.com
allow tcp any any eq 443 host aws-toolkit-language-servers.amazonaws.com

# Deny all other HTTPS traffic
deny tcp any any eq 443
```

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
