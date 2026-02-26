# AWS Kiro Banking Best Practices
## MAS-Compliant Implementation Guide for Singapore Financial Institutions

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![MAS Compliant](https://img.shields.io/badge/MAS-TRM%20Guidelines-blue.svg)](https://www.mas.gov.sg/regulation/guidelines/technology-risk-management-guidelines)
[![AWS](https://img.shields.io/badge/AWS-Kiro-orange.svg)](https://kiro.dev)

> Security-first guidance for implementing AWS Kiro in banking SDLC environments while maintaining full compliance with Monetary Authority of Singapore (MAS) Technology Risk Management Guidelines.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Documentation Structure](#documentation-structure)
- [Quick Start](#quick-start)
- [Security Architecture](#security-architecture)
- [Compliance Framework](#compliance-framework)
- [Target Audience](#target-audience)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

This repository provides comprehensive best practices for banking development teams implementing AWS Kiro (AI-powered development assistant) in Software Development Life Cycle (SDLC) environments. All guidance is designed to meet MAS regulatory requirements for financial institutions operating in Singapore.

### What is AWS Kiro?

AWS Kiro is an AI-powered IDE and development assistant that helps developers write, debug, and optimize code. For banking environments, special security controls are required to ensure compliance with financial services regulations.

### Why This Guide?

Financial institutions face unique challenges when adopting AI development tools:
- **Regulatory Compliance** - Must meet MAS Technology Risk Management Guidelines
- **Data Protection** - Sensitive code and data must remain within controlled environments
- **Access Control** - Enterprise identity management and MFA requirements
- **Audit Requirements** - Complete audit trails for all AI-assisted development activities
- **Network Security** - Private connectivity without internet exposure

This guide addresses all these challenges with practical, tested implementations.

---

## Key Features

### 🔐 Enterprise Security Controls
- AWS IAM Identity Center integration with Enterprise IdP (Azure AD, Okta, Ping Identity)
- SAML 2.0 authentication with MFA enforcement
- Blocking of social logins and AWS Builder IDs
- Session management and timeout policies

### 🌐 Network Isolation
- End-to-end VPC architecture with no internet-facing endpoints
- AWS PrivateLink for private connectivity to Kiro services
- Security groups and Network ACLs for defense-in-depth
- DNS resolution within private network

### 🖥️ Secure Development Environment
- Amazon WorkSpaces VDI with encryption at rest and in transit
- Group Policy (GPO) hardening for Windows environments
- Data Loss Prevention (DLP) agent deployment
- Centralized MCP configuration management

### 🛡️ MCP Server Governance
- Whitelist-based MCP server approval process
- Centrally managed configuration preventing developer modifications
- Approved MCP servers for banking use cases
- Audit logging of all MCP tool usage

### 📊 Compliance & Audit
- CloudTrail logging for all Kiro activities
- CloudWatch monitoring and alerting
- Automated compliance validation scripts
- MAS TRM Guidelines mapping

---

## Documentation Structure

### Primary Documentation

| Document | Description | Status |
|----------|-------------|--------|
| **[README-Kiro-Banking-Best-Practices.md](README-Kiro-Banking-Best-Practices.md)** | Detailed overview and quick start guide | ✅ Complete |
| **[Kiro-Agentic-SDLC-Banking-Best-Practices.md](Kiro-Agentic-SDLC-Banking-Best-Practices.md)** | Comprehensive implementation guide (Sections 1-4) | ✅ Complete |
| **[Kiro-Banking-Best-Practices-Part2.md](Kiro-Banking-Best-Practices-Part2.md)** | Extended guidance (Sections 5-10) | 🚧 In Progress |

### Technical Reference

| Document | Description |
|----------|-------------|
| **[kiro-docs/mcp-configuration.md](kiro-docs/mcp-configuration.md)** | MCP server configuration guide |
| **[kiro-docs/mcp-security.md](kiro-docs/mcp-security.md)** | MCP security best practices |
| **[kiro-docs/mcp-servers.md](kiro-docs/mcp-servers.md)** | Available MCP servers reference |
| **[kiro-docs/mcp-usage.md](kiro-docs/mcp-usage.md)** | MCP usage patterns and examples |
| **[kiro-docs/privacy-and-security.md](kiro-docs/privacy-and-security.md)** | Privacy and security guidelines |

### Regulatory Frameworks

- **MAS Framework for Impact and Risk Assessment of Financial Institutions.pdf**
- **TRM Guidelines 18 January 2021.pdf**
- **Risk Management Guidelines_Insurance Core Activities.pdf**
- **Monograph - A guide for senior executives - Final revised in April 2013.pdf**

---

## Quick Start

### Prerequisites

Before implementing Kiro in your banking environment, ensure you have:

- ✅ AWS Organization with IAM Identity Center enabled
- ✅ Enterprise IdP (Azure AD, Okta, Ping Identity) with SAML 2.0 support
- ✅ Corporate VPC with private subnets configured
- ✅ Amazon WorkSpaces directory set up
- ✅ DLP solution deployed (Symantec, McAfee, Microsoft Purview, or Forcepoint)
- ✅ CloudTrail enabled for audit logging

### Implementation Timeline

```
Week 1-2: Identity & Access Management
  └─ Configure Enterprise IdP integration with IAM Identity Center
  └─ Enable SCIM provisioning for user synchronization
  └─ Assign Kiro subscriptions to developer groups
  └─ Block social login URLs at firewall level

Week 2-3: Network Security Architecture
  └─ Create VPC Interface Endpoints for Kiro services
  └─ Configure security groups and Network ACLs
  └─ Enable Private DNS resolution
  └─ Test connectivity from WorkSpaces

Week 3-4: VDI Deployment
  └─ Deploy Amazon WorkSpaces with encryption
  └─ Apply Group Policy hardening
  └─ Install and configure DLP agents
  └─ Deploy centralized MCP configuration

Week 4-5: MCP Governance
  └─ Define approved MCP server whitelist
  └─ Create centralized mcp.json configuration
  └─ Implement file system permissions
  └─ Test developer access restrictions

Week 5-6: Monitoring & Compliance
  └─ Enable CloudTrail logging for Kiro activities
  └─ Configure CloudWatch alarms
  └─ Implement compliance validation scripts
  └─ Conduct security audit and documentation review
```

### Getting Started

1. **Read the Overview**
   ```bash
   # Start with the comprehensive overview
   open README-Kiro-Banking-Best-Practices.md
   ```

2. **Review Architecture**
   ```bash
   # Understand the security architecture
   open Kiro-Agentic-SDLC-Banking-Best-Practices.md
   ```

3. **Configure Your Environment**
   ```bash
   # Follow the step-by-step implementation guide
   # Begin with Section 2: Authentication & Identity Management
   ```

4. **Validate Compliance**
   ```bash
   # Use the provided validation scripts
   ./validate-repo.sh
   ```

---

## Security Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Enterprise IdP (Azure AD/Okta)              │
│                     SAML 2.0 + SCIM Provisioning                │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                  AWS IAM Identity Center                        │
│              MFA Enforcement + Session Management               │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Amazon WorkSpaces (VDI)                      │
│         DLP Agents + GPO Hardening + Centralized MCP            │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                  VPC with Private Subnets                       │
│         Security Groups + NACLs + VPC Endpoints                 │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              AWS PrivateLink (VPC Interface Endpoints)          │
│                   Private Connectivity to Kiro                  │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                        AWS Kiro Service                         │
│              CloudTrail Logging + CloudWatch Monitoring         │
└─────────────────────────────────────────────────────────────────┘
```

### Security Layers

1. **Identity Layer** - Enterprise IdP + IAM Identity Center + MFA
2. **Network Layer** - VPC + PrivateLink + Security Groups
3. **Endpoint Layer** - WorkSpaces VDI + DLP + GPO
4. **Application Layer** - MCP Governance + Centralized Configuration
5. **Audit Layer** - CloudTrail + CloudWatch + Compliance Validation

---

## Compliance Framework

### MAS TRM Guidelines Mapping

| MAS Section | Control Area | Implementation | Document Reference |
|-------------|--------------|----------------|-------------------|
| **3.1** | Governance & Oversight | IAM IDC + Enterprise IdP | Section 2 |
| **9.1** | Access Control | MFA + Session Management | Section 2.1.3 |
| **9.3** | Remote Access Security | VPC + PrivateLink | Section 3 |
| **10** | Cryptography | TLS 1.2+ + KMS | Section 7 |
| **11.1** | Data Security | DLP + Encryption at Rest | Section 4.1.3 |
| **11.2** | Network Security | VPC Endpoints + Security Groups | Section 3.2 |
| **15** | IT Audit | CloudTrail + Monitoring | Section 8 |

### Key Compliance Controls

✅ **Zero Trust Architecture** - No internet-facing endpoints, all traffic through VPC PrivateLink  
✅ **MFA Enforcement** - Required for all user access via Enterprise IdP  
✅ **Least Privilege** - IAM policies grant minimum required permissions  
✅ **Encryption** - Data encrypted at rest (KMS) and in transit (TLS 1.2+)  
✅ **Audit Trails** - CloudTrail logging with 90-day minimum retention  
✅ **Data Residency** - All data processing within Singapore region  
✅ **DLP Controls** - Prevent code exfiltration and credential exposure  
✅ **MCP Governance** - Centrally managed whitelist, no developer modifications  

---

## Target Audience

This documentation is designed for:

- **Banking Developers** - Implementing Kiro in daily SDLC workflows
- **Security Architects** - Designing secure AI development environments
- **Compliance Officers** - Validating MAS regulatory compliance
- **Cloud Operations Teams** - Deploying and managing Kiro infrastructure
- **Development Team Leads** - Establishing secure development practices
- **IT Auditors** - Reviewing security controls and audit trails

---

## Contributing

We welcome contributions from the banking and financial services community. Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:

- Submitting security enhancements
- Reporting compliance gaps
- Sharing implementation experiences
- Proposing new MCP server approvals
- Improving documentation

---

## License

This documentation is licensed under the MIT License. See [LICENSE](LICENSE) for full details.

### Disclaimer

This documentation is provided for informational and educational purposes only. It does not constitute legal advice, regulatory guidance, or professional security consulting services. Organizations must:

- Conduct independent security assessments and risk analysis
- Consult with qualified legal, compliance, and security professionals
- Validate implementations against specific regulatory requirements
- Maintain full responsibility for security posture and compliance status

---

## Additional Resources

### AWS Documentation
- [Kiro Privacy and Security](https://kiro.dev/docs/privacy-and-security/)
- [Kiro MCP Security](https://kiro.dev/docs/mcp/security/)
- [AWS IAM Identity Center](https://docs.aws.amazon.com/singlesignon/)
- [AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [Amazon WorkSpaces](https://docs.aws.amazon.com/workspaces/)

### MAS Guidelines
- [Technology Risk Management Guidelines](https://www.mas.gov.sg/regulation/guidelines/technology-risk-management-guidelines)
- [MAS Framework for Impact and Risk Assessment](https://www.mas.gov.sg/)

### AWS Compliance
- [AWS Financial Services Security](https://aws.amazon.com/financial-services/security-compliance/)
- [AWS Compliance Programs](https://aws.amazon.com/compliance/)

---

## Support

For questions, issues, or feedback:

- **Documentation Issues**: Open an issue in this repository
- **Security Concerns**: Follow responsible disclosure practices
- **Implementation Support**: Consult with AWS Professional Services or AWS Partners

---

**Version:** 1.0  
**Last Updated:** February 26, 2026  
**Maintained By:** Security Architecture Team
