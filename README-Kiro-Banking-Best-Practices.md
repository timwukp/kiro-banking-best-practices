# AWS Kiro Agentic Code in SDLC Best Practices for Banking Developers
## Singapore MAS-Compliant Implementation Guide

### Document Status
**Version:** 1.0 (Part 1 of 2 completed)  
**Created:** February 25, 2026  
**Compliance Framework:** MAS Technology Risk Management Guidelines

---

## Overview

This comprehensive guide provides Singapore banking developers with security-first best practices for implementing AWS Kiro in SDLC environments while maintaining full compliance with Monetary Authority of Singapore (MAS) regulations.

### Key Security Architecture Components

1. **Enterprise IdP Integration** - AWS IAM Identity Center with SAML 2.0
2. **Network Isolation** - End-to-end VPC with AWS PrivateLink
3. **Controlled Environment** - Amazon WorkSpaces VDI with DLP
4. **MCP Governance** - Centralized whitelist management
5. **Audit & Compliance** - CloudTrail logging and monitoring

---

## Document Structure

### ✅ **Completed Sections** (in Kiro-Agentic-SDLC-Banking-Best-Practices.md)

1. **Architecture Overview**
   - High-level security architecture diagram
   - Security layers mapped to MAS guidelines
   
2. **Authentication & Identity Management**
   - Enterprise IdP integration with AWS IAM IDC
   - SAML 2.0 and SCIM configuration
   - Session management and MFA enforcement
   - Blocking social logins and Builder IDs
   - CloudTrail audit logging

3. **Network Security Architecture**
   - VPC configuration for private connectivity
   - VPC Interface Endpoints (AWS PrivateLink) setup
   - Security groups and NACLs
   - DNS resolution and firewall rules

4. **Virtual Desktop Infrastructure (VDI)**
   - Amazon WorkSpaces configuration
   - Group Policy (GPO) hardening
   - DLP agent deployment and policies
   - Centralized MCP configuration management
   - Compliance monitoring and validation

### 📋 **Remaining Sections** (To be completed)

5. **MCP Server Security & Governance**
   - Whitelist management and approval workflow
   - Preventing unauthorized MCP server installation
   - Approved MCP servers for banking (AWS Docs, Git, etc.)
   - MCP configuration schema and validation
   - Monitoring MCP tool usage

6. **SDLC Security Controls**
   - Secure code development workflow
   - Code review and approval gates
   - Secrets management (AWS Secrets Manager)
   - Artifact security (S3, ECR)
   - CI/CD pipeline security

7. **Data Protection & Encryption**
   - Encryption at rest (KMS customer-managed keys)
   - Encryption in transit (TLS 1.2+, TLS 1.3 recommended)
   - Data residency and cross-region processing
   - PII handling and masking
   - Opt-out of service improvement data sharing

8. **Compliance & Audit**
   - MAS TRM Guidelines mapping
   - Audit trail requirements
   - Compliance validation procedures
   - Reporting and documentation

9. **Operational Best Practices**
   - Developer onboarding and training
   - Supervised vs Autopilot mode guidance
   - Trusted commands configuration
   - Prompt logging for audit
   - Performance optimization

10. **Incident Response**
    - Security incident procedures
    - MCP server compromise response
    - Data breach protocols
    - Escalation matrix

---

## Quick Start Guide

### Prerequisites
- AWS Organization with IAM Identity Center enabled
- Enterprise IdP (Azure AD, Okta, etc.) with SAML 2.0
- Corporate VPC with private subnets
- Amazon WorkSpaces directory configured

### Implementation Steps

#### Phase 1: Identity & Access (Week 1-2)
1. Configure Enterprise IdP integration with IAM IDC
2. Enable SCIM provisioning for user sync
3. Assign Kiro subscriptions to developer groups
4. Block social login URLs at firewall

#### Phase 2: Network Security (Week 2-3)
1. Create VPC Interface Endpoints for Kiro services
2. Configure security groups and NACLs
3. Enable Private DNS resolution
4. Test connectivity from WorkSpaces

#### Phase 3: VDI Deployment (Week 3-4)
1. Deploy Amazon WorkSpaces with encryption
2. Apply Group Policy hardening
3. Install and configure DLP agents
4. Deploy centralized MCP configuration

#### Phase 4: MCP Governance (Week 4-5)
1. Define approved MCP server whitelist
2. Create centralized mcp.json configuration
3. Implement file system permissions
4. Test developer access restrictions

#### Phase 5: Monitoring & Compliance (Week 5-6)
1. Enable CloudTrail logging for Kiro
2. Configure CloudWatch alarms
3. Implement compliance validation scripts
4. Conduct security audit

---

## MAS Compliance Mapping

| MAS TRM Section | Kiro Control | Implementation |
|-----------------|--------------|----------------|
| **3.1 Governance** | IAM IDC + Enterprise IdP | Section 2 |
| **9.1 Access Control** | MFA + Session Management | Section 2.1.3 |
| **9.3 Remote Access** | VPC + PrivateLink | Section 3 |
| **10 Cryptography** | TLS 1.2+ + KMS | Section 7 |
| **11.1 Data Security** | DLP + Encryption | Section 4.1.3 |
| **11.2 Network Security** | VPC Endpoints + SG | Section 3.2 |
| **15 IT Audit** | CloudTrail + Monitoring | Section 8 |

---

## Key Security Controls

### 1. Zero Trust Architecture
- ✅ No internet-facing endpoints
- ✅ All traffic through VPC PrivateLink
- ✅ MFA required for all access
- ✅ Least privilege IAM policies

### 2. MCP Server Governance
- ✅ Centrally managed whitelist
- ✅ Developers cannot install MCP servers
- ✅ Read-only configuration files
- ✅ Audit logging of MCP tool usage

### 3. Data Loss Prevention
- ✅ DLP agents on all WorkSpaces
- ✅ Block code exfiltration channels
- ✅ Monitor clipboard and file operations
- ✅ Alert on credential exposure

### 4. Audit & Compliance
- ✅ CloudTrail data events enabled
- ✅ 90-day log retention minimum
- ✅ Automated compliance validation
- ✅ Monthly security reports

---

## Approved MCP Servers for Banking

### Tier 1: Pre-Approved (No Additional Review)
- **AWS Documentation** - Official AWS docs access
- **Git** - Repository operations (read-only recommended)
- **Filesystem** - Controlled directory access

### Tier 2: Conditional Approval (Security Review Required)
- **GitHub** - With token scope restrictions
- **Docker** - For containerized builds
- **Kubernetes** - For deployment automation

### Tier 3: Prohibited
- **Web Search** - External data leakage risk
- **Browser** - Uncontrolled web access
- **Custom/Unverified** - Unknown security posture

---

## References

### AWS Documentation
- [Kiro Privacy and Security](https://kiro.dev/docs/privacy-and-security/)
- [Kiro MCP Security](https://kiro.dev/docs/mcp/security/)
- [Kiro MCP Configuration](https://kiro.dev/docs/mcp/configuration/)
- [AWS IAM Identity Center](https://docs.aws.amazon.com/singlesignon/)
- [AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [Amazon WorkSpaces](https://docs.aws.amazon.com/workspaces/)

### MAS Guidelines
- [Technology Risk Management Guidelines](https://www.mas.gov.sg/regulation/guidelines/technology-risk-management-guidelines)
- [MAS Framework for Impact and Risk Assessment](https://www.mas.gov.sg/)

### AWS Compliance
- [AWS Financial Services Security](https://aws.amazon.com/financial-services/security-compliance/)
- [AWS Compliance Programs](https://aws.amazon.com/compliance/)
- [AWS Trust Center](https://aws.amazon.com/trust-center/)



---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-25 | Initial release (Sections 1-4) | Security Architecture Team |
| 1.1 | TBD | Complete sections 5-10 | Pending |

---

## License

This documentation is licensed under the MIT License.

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy of this documentation and associated files (the "Documentation"), to deal in the Documentation without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Documentation, and to permit persons to whom the Documentation is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Documentation.

THE DOCUMENTATION IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE DOCUMENTATION OR THE USE OR OTHER DEALINGS IN THE DOCUMENTATION.

## Disclaimer

This documentation is provided for informational and educational purposes only. It does not constitute:
- Legal advice or regulatory guidance
- Professional security consulting services
- Compliance certification or validation
- Endorsement of any specific implementation approach

**No Liability:** The authors and contributors accept no responsibility or liability for:
- Any security breaches, data losses, or compliance violations
- Implementation decisions made based on this documentation
- Accuracy, completeness, or suitability of the information provided
- Any damages or losses arising from the use of this documentation

**User Responsibility:** Organizations using this documentation must:
- Conduct their own independent security assessments and risk analysis
- Consult with qualified legal, compliance, and security professionals
- Validate all implementations against their specific regulatory requirements
- Maintain full responsibility for their security posture and compliance status
- Adapt all guidance to their specific organizational context and risk profile

**Regulatory Compliance:** This documentation references MAS guidelines but does not guarantee compliance. Organizations are solely responsible for ensuring their implementations meet all applicable regulatory requirements.
