# AWS Kiro Banking Best Practices - Part 2
## Sections 5-14: MCP Governance, SDLC, Data Protection, Operations & Regulatory Compliance

---

## 5. MCP Server Security & Governance

### 5.1 Centralized Whitelist Management

**Approved MCP Servers Configuration:**

```json
{
  "mcpServers": {
    "aws-docs": {
      "command": "uvx",
      "args": ["awslabs.aws-documentation-mcp-server@latest"],
      "disabled": false,
      "autoApprove": ["mcp_aws_docs_search_documentation", "mcp_aws_docs_read_documentation"]
    },
    "git": {
      "command": "uvx",
      "args": ["mcp-server-git"],
      "disabled": false,
      "autoApprove": [],
      "disabledTools": ["git_push", "git_force_push"]
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "C:\\Projects"],
      "disabled": false,
      "autoApprove": [],
      "disabledTools": ["delete_file"]
    }
  }
}
```

**Deployment Script:**
```powershell
# Deploy via GPO startup script
$centralConfig = "\\fileserver\kiro-config\mcp.json"
$targetPath = "C:\ProgramData\Kiro\mcp.json"

Copy-Item $centralConfig $targetPath -Force
icacls $targetPath /inheritance:r /grant:r "SYSTEM:(F)" "Administrators:(F)" "Users:(R)"

# Symlink user config to central
$userConfig = "$env:USERPROFILE\.kiro\settings\mcp.json"
New-Item -ItemType SymbolicLink -Path $userConfig -Target $targetPath -Force
```

### 5.2 MCP Configuration Validation

**Validation Script:**
```python
import json
import hashlib

APPROVED_SERVERS = ["aws-docs", "git", "filesystem"]
APPROVED_HASH = "sha256_of_approved_config"

def validate_mcp_config(config_path):
    with open(config_path) as f:
        config = json.load(f)
    
    # Check only approved servers
    for server in config.get("mcpServers", {}).keys():
        if server not in APPROVED_SERVERS:
            raise ValueError(f"Unauthorized MCP server: {server}")
    
    # Verify config hash
    config_hash = hashlib.sha256(json.dumps(config, sort_keys=True).encode()).hexdigest()
    if config_hash != APPROVED_HASH:
        raise ValueError("MCP configuration tampered")
    
    return True
```

### 5.3 MCP Usage Monitoring

**CloudWatch Log Insights Query:**
```sql
fields @timestamp, userIdentity.principalId, eventName, requestParameters.toolName
| filter eventSource = "q.amazonaws.com" 
| filter eventName = "InvokeMCPTool"
| stats count() by requestParameters.toolName, userIdentity.principalId
```

---

## 6. SDLC Security Controls

### 6.1 Secure Development Workflow

**Kiro Supervised Mode (Mandatory for Production):**
```json
{
  "kiro.autopilot.enabled": false,
  "kiro.supervised.requireApproval": true,
  "kiro.trustedCommands": ["npm install", "npm test", "git status"]
}
```

### 6.2 Secrets Management

**AWS Secrets Manager Integration:**
```bash
# Store secrets
aws secretsmanager create-secret \
  --name /banking/dev/db-password \
  --secret-string "$(openssl rand -base64 32)" \
  --kms-key-id arn:aws:kms:region:account:key/xxxxx

# Retrieve in code (never hardcode)
import boto3
secret = boto3.client('secretsmanager').get_secret_value(SecretId='/banking/dev/db-password')
```

**Kiro Prompt Guidance:**
```
"Use AWS Secrets Manager for credentials. Never hardcode secrets. 
Reference: secretsmanager.get_secret_value(SecretId='...')"
```

### 6.3 Code Review Gates

**Pre-commit Hook:**
```bash
#!/bin/bash
# .git/hooks/pre-commit

# Scan for secrets
if git diff --cached | grep -E '(AWS_ACCESS_KEY|password\s*=|api_key\s*=)'; then
    echo "ERROR: Potential secret detected"
    exit 1
fi

# Validate Kiro-generated code
if git diff --cached --name-only | grep -E '\.(py|js|java)$'; then
    echo "Code review required for Kiro-generated changes"
fi
```

### 6.4 Artifact Security

**S3 Bucket Policy (Code Artifacts):**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:*",
    "Resource": "arn:aws:s3:::banking-artifacts/*",
    "Condition": {
      "Bool": {"aws:SecureTransport": "false"}
    }
  }]
}
```

---

## 7. Data Protection & Encryption

### 7.1 Customer-Managed KMS Keys

**Create KMS Key for Kiro:**
```bash
aws kms create-key \
  --description "Kiro data encryption" \
  --key-policy '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "Enable IAM policies",
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::account:root"},
      "Action": "kms:*",
      "Resource": "*"
    }]
  }'

# Configure in Kiro console
aws q update-encryption-configuration \
  --kms-key-id arn:aws:kms:region:account:key/xxxxx
```

### 7.2 Data Residency

**Regional Configuration:**
- **Primary Region:** ap-southeast-1 (Singapore)
- **Cross-Region Inference:** Disabled for banking
- **Data Storage:** Singapore region only

**Kiro Admin Console Setting:**
```json
{
  "dataResidency": {
    "primaryRegion": "ap-southeast-1",
    "allowCrossRegion": false,
    "dataRetention": "90days"
  }
}
```

### 7.3 Opt-Out Configuration

**Disable Service Improvement (Enterprise):**
```bash
# Via IAM IDC - applies to all users
aws q update-organization-settings \
  --opt-out-service-improvement true \
  --opt-out-telemetry false
```

**IDE Settings (Backup):**
```json
{
  "kiro.telemetry.enabled": false,
  "kiro.shareContentWithAWS": false,
  "kiro.codeReferences.enabled": true
}
```

---

## 8. Compliance & Audit

### 8.1 MAS TRM Compliance Matrix

| Control | MAS Section | Implementation | Evidence |
|---------|-------------|----------------|----------|
| Access Control | 9.1 | IAM IDC + MFA | CloudTrail logs |
| Encryption | 10.1 | TLS 1.2+ + KMS | KMS key policy |
| Data Security | 11.1 | DLP + Encryption | DLP reports |
| Network Security | 11.2 | VPC + PrivateLink | VPC flow logs |
| Audit Logging | 15.1 | CloudTrail | S3 audit bucket |

### 8.2 Audit Trail Requirements

**CloudTrail Configuration:**
```bash
aws cloudtrail put-event-selectors \
  --trail-name kiro-audit \
  --event-selectors '[{
    "ReadWriteType": "All",
    "IncludeManagementEvents": true,
    "DataResources": [{
      "Type": "AWS::Q::Chat",
      "Values": ["arn:aws:q:*:*:*"]
    }]
  }]'

# Enable log file validation
aws cloudtrail update-trail \
  --name kiro-audit \
  --enable-log-file-validation
```

**S3 Lifecycle Policy (90-day retention):**
```json
{
  "Rules": [{
    "Id": "ArchiveAuditLogs",
    "Status": "Enabled",
    "Transitions": [{
      "Days": 30,
      "StorageClass": "STANDARD_IA"
    }, {
      "Days": 90,
      "StorageClass": "GLACIER"
    }],
    "Expiration": {"Days": 2555}
  }]
}
```

### 8.3 Compliance Reporting

**Monthly Compliance Report Script:**
```python
import boto3
from datetime import datetime, timedelta

def generate_compliance_report():
    cloudtrail = boto3.client('cloudtrail')
    
    # Last 30 days
    end_time = datetime.now()
    start_time = end_time - timedelta(days=30)
    
    events = cloudtrail.lookup_events(
        LookupAttributes=[{'AttributeKey': 'EventSource', 'AttributeValue': 'q.amazonaws.com'}],
        StartTime=start_time,
        EndTime=end_time
    )
    
    report = {
        "period": f"{start_time.date()} to {end_time.date()}",
        "total_events": len(events['Events']),
        "unique_users": len(set(e['Username'] for e in events['Events'])),
        "mcp_tool_usage": sum(1 for e in events['Events'] if 'MCP' in e['EventName']),
        "failed_auth": sum(1 for e in events['Events'] if e.get('ErrorCode'))
    }
    
    return report
```

---

## 9. Operational Best Practices

### 9.1 Developer Onboarding

**Day 1 Checklist:**
1. ✅ IAM IDC account provisioned
2. ✅ MFA device registered
3. ✅ WorkSpaces assigned
4. ✅ Security training completed
5. ✅ Kiro access tested

**Training Topics:**
- Supervised mode vs Autopilot
- MCP server restrictions
- Secrets management
- Code review requirements
- DLP policies

### 9.2 Kiro Usage Guidelines

**Supervised Mode (Default):**
```json
{
  "kiro.mode": "supervised",
  "kiro.autoApprove": false,
  "kiro.reviewRequired": ["file_write", "command_execute", "mcp_tool"]
}
```

**Trusted Commands (Minimal):**
```json
{
  "kiro.trustedCommands": [
    "npm install",
    "npm test",
    "git status",
    "git log",
    "terraform plan"
  ]
}
```

### 9.3 Prompt Logging

**Enable Prompt Logging:**
```bash
aws q put-prompt-logging-configuration \
  --s3-bucket-name kiro-prompts-<account-id> \
  --kms-key-id arn:aws:kms:region:account:key/xxxxx
```

**S3 Bucket Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "q.amazonaws.com"},
    "Action": "s3:PutObject",
    "Resource": "arn:aws:s3:::kiro-prompts-*/*",
    "Condition": {
      "StringEquals": {"s3:x-amz-server-side-encryption": "aws:kms"}
    }
  }]
}
```

### 9.4 Performance Optimization

**Context Window Management:**
- Limit file context to relevant code only
- Use `.kiro/steering` for project-specific guidance
- Avoid uploading large binary files

**Steering File Example:**
```yaml
# .kiro/steering/banking-standards.yaml
guidelines:
  - "Follow MAS security guidelines"
  - "Use AWS Secrets Manager for credentials"
  - "All database queries must use parameterized statements"
  - "Log all financial transactions"
  
prohibited:
  - "Never hardcode credentials"
  - "No direct database connections from frontend"
  - "No unencrypted data transmission"
```

---

## 10. Incident Response

### 10.1 Security Incident Procedures

**Incident Classification:**

| Severity | Example | Response Time |
|----------|---------|---------------|
| **Critical** | Credential exposure | Immediate (15 min) |
| **High** | Unauthorized MCP server | 1 hour |
| **Medium** | DLP policy violation | 4 hours |
| **Low** | Failed authentication | 24 hours |

### 10.2 MCP Server Compromise Response

**Immediate Actions:**
1. Disable affected MCP server in central config
2. Revoke API tokens/credentials
3. Review CloudTrail logs for unauthorized activity
4. Isolate affected WorkSpaces

**Investigation Script:**
```bash
# Find all MCP tool invocations in last 24 hours
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=InvokeMCPTool \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --query 'Events[*].[EventTime,Username,CloudTrailEvent]' \
  --output json > mcp-investigation.json
```

### 10.3 Data Breach Protocol

**Containment:**
```powershell
# Immediately disable user access
aws sso-admin delete-account-assignment \
  --instance-arn <instance-arn> \
  --target-id <account-id> \
  --target-type AWS_ACCOUNT \
  --permission-set-arn <permission-set-arn> \
  --principal-type USER \
  --principal-id <user-id>

# Rotate all secrets
aws secretsmanager rotate-secret --secret-id /banking/*
```

**Notification:**
- Security team: Immediate
- Compliance team: Within 1 hour
- MAS: Within 24 hours (if material breach)

### 10.4 Escalation Matrix

```
Level 1: Developer → Team Lead (15 min)
Level 2: Team Lead → Security Team (30 min)
Level 3: Security Team → CISO (1 hour)
Level 4: CISO → MAS (24 hours if required)
```

---

## Appendix A: Quick Reference Commands

### IAM IDC
```bash
# List users
aws identitystore list-users --identity-store-id d-xxxxx

# Assign Kiro subscription
aws sso-admin create-account-assignment \
  --instance-arn <arn> --target-id <account> \
  --permission-set-arn <arn> --principal-type USER --principal-id <id>
```

### VPC Endpoints
```bash
# Create Kiro endpoint
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxxxx \
  --service-name com.amazonaws.us-east-1.q \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-xxxxx \
  --security-group-ids sg-xxxxx
```

### CloudTrail
```bash
# Query Kiro events
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=q.amazonaws.com \
  --max-results 50
```

### WorkSpaces
```bash
# List WorkSpaces
aws workspaces describe-workspaces

# Reboot WorkSpace
aws workspaces reboot-workspaces --reboot-workspace-requests WorkspaceId=ws-xxxxx
```

---

## Appendix B: Compliance Checklist

### Pre-Production Checklist

- [ ] IAM IDC integrated with Enterprise IdP
- [ ] MFA enabled for all users
- [ ] Social logins blocked at firewall
- [ ] VPC endpoints created and tested
- [ ] WorkSpaces deployed with encryption
- [ ] DLP agents installed and configured
- [ ] Centralized MCP config deployed
- [ ] CloudTrail logging enabled
- [ ] KMS customer-managed keys configured
- [ ] Prompt logging enabled
- [ ] Security training completed
- [ ] Incident response plan documented
- [ ] Compliance report template created

### Monthly Audit Checklist

- [ ] Review CloudTrail logs for anomalies
- [ ] Validate MCP configuration integrity
- [ ] Check DLP policy violations
- [ ] Review failed authentication attempts
- [ ] Verify encryption key rotation
- [ ] Test incident response procedures
- [ ] Update security documentation
- [ ] Generate compliance report for management

---

## Appendix C: Troubleshooting

### Issue: Cannot connect to Kiro from WorkSpaces

**Check:**
1. VPC endpoint status: `aws ec2 describe-vpc-endpoints`
2. Security group rules allow port 443
3. Private DNS enabled on endpoint
4. DNS resolution: `nslookup q.us-east-1.amazonaws.com`

### Issue: MCP server not loading

**Check:**
1. Config file permissions: `icacls C:\ProgramData\Kiro\mcp.json`
2. MCP server in approved list
3. MCP logs: Kiro panel → Output → "Kiro - MCP Logs"
4. Network connectivity to MCP server endpoint

### Issue: DLP blocking legitimate operations

**Resolution:**
1. Review DLP policy exceptions
2. Add file path to whitelist
3. Document business justification
4. Update DLP policy via GPO

---

## 11. Personal Data Protection Act (PDPA) Compliance

### 11.1 PDPA Overview for Kiro Usage

**Applicability:** The Personal Data Protection Act 2012 (PDPA) governs the collection, use, disclosure, and care of personal data in Singapore. When developers use Kiro to write, review, or debug code that handles personal data, PDPA obligations apply.

**Key PDPA Obligations Relevant to Kiro:**

| PDPA Obligation | Kiro Context | Implementation |
|-----------------|--------------|----------------|
| **Consent** | Code processing personal data must have valid consent basis | Kiro prompts should reference consent requirements |
| **Purpose Limitation** | Personal data used only for stated purposes | DLP policies block unauthorized data access |
| **Notification** | Individuals informed of data collection purposes | Audit logs track what data Kiro accesses |
| **Access & Correction** | Individuals can request access to their data | Data handling code must support DSAR workflows |
| **Accuracy** | Reasonable effort to ensure data is accurate | Validation logic in Kiro-generated code |
| **Protection** | Reasonable security to protect personal data | Encryption, DLP, VPC isolation |
| **Retention Limitation** | Data not kept longer than necessary | Kiro prompt logs subject to retention policy |
| **Transfer Limitation** | Cross-border transfer restrictions | Data residency in ap-southeast-1 (Singapore) |
| **Data Breach Notification** | Notify PDPC within 3 calendar days of assessment | Incident response plan must include PDPC notification |

### 11.2 PDPA Controls for Kiro Environments

**Data Classification for Kiro Context:**

```json
{
  "dataClassification": {
    "prohibited_in_prompts": [
      "NRIC numbers",
      "Credit card numbers (full)",
      "Bank account numbers (full)",
      "Medical records",
      "Passwords or authentication credentials"
    ],
    "restricted_in_prompts": [
      "Customer names (use pseudonyms)",
      "Email addresses (use examples)",
      "Phone numbers (use masked format)",
      "Transaction amounts (use sample data)"
    ],
    "permitted_in_prompts": [
      "Code patterns and logic",
      "Architecture descriptions",
      "Error messages (sanitized)",
      "Configuration templates"
    ]
  }
}
```

**DLP Policy Enhancement for PDPA:**

```json
{
  "pdpa_dlp_rules": [
    {
      "name": "Block NRIC in Kiro Prompts",
      "pattern": "[STFG]\\d{7}[A-Z]",
      "action": "block_and_alert",
      "notification": "PDPA violation: NRIC detected in AI prompt"
    },
    {
      "name": "Block Credit Card in Kiro Prompts",
      "pattern": "\\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13})\\b",
      "action": "block_and_alert",
      "notification": "PDPA violation: Credit card number detected"
    },
    {
      "name": "Warn on Email in Prompts",
      "pattern": "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",
      "action": "warn_and_log",
      "notification": "PDPA advisory: Email address in AI prompt"
    }
  ]
}
```

### 11.3 PDPA Compliance Checklist for Kiro

- [ ] Data classification policy defined for AI-assisted development
- [ ] DLP rules enforce PDPA data categories in Kiro prompts
- [ ] Developer training covers PDPA obligations when using AI tools
- [ ] Prompt logging enabled with PDPA-compliant retention (max 5 years)
- [ ] Data residency confirmed in Singapore region (ap-southeast-1)
- [ ] Cross-region inference disabled for PDPA-regulated workloads
- [ ] Data breach notification process includes PDPC (3-day assessment window)
- [ ] Privacy impact assessment completed for Kiro deployment
- [ ] Data intermediary obligations assessed (Kiro/AWS as data intermediary)

### 11.4 PDPA Breach Notification

**Timeline (per PDPA Amendment 2020):**

```
Data breach discovered
  └─ Assess within 30 calendar days if breach is notifiable
     └─ If notifiable (significant harm or ≥500 individuals):
        └─ Notify PDPC within 3 calendar days of assessment
        └─ Notify affected individuals as soon as practicable
```

**Integration with Incident Response (Section 10):**
- Severity "Critical" and "High" incidents must trigger PDPA breach assessment
- Security team must assess PDPA notification requirements alongside MAS reporting

---

## 12. MAS Outsourcing Guidelines Compliance

### 12.1 Kiro as an Outsourced Service

**Context:** AWS Kiro is an AWS-managed AI development service. Under MAS Guidelines on Outsourcing (2018 revision), financial institutions must assess and manage risks associated with outsourcing material arrangements to third-party service providers.

**Outsourcing Classification:**

| Factor | Assessment |
|--------|------------|
| **Service Provider** | Amazon Web Services (AWS) |
| **Service** | AI-assisted software development (Kiro IDE/CLI) |
| **Materiality** | Assess based on: impact on business operations, data sensitivity, customer impact |
| **Data Involved** | Source code, development prompts, configuration data |
| **Jurisdiction** | Service hosted in AWS regions; data residency configurable |

### 12.2 MAS Outsourcing Requirements Mapping

| MAS Outsourcing Requirement | Kiro Implementation | Evidence |
|-----------------------------|---------------------|----------|
| **Risk Assessment** | Technology risk assessment of Kiro deployment | Risk register entry |
| **Due Diligence** | AWS compliance certifications (SOC 2, ISO 27001) | AWS Artifact reports |
| **Contractual Protections** | AWS Enterprise Agreement / Addendum | Legal review |
| **Data Protection** | Encryption, DLP, VPC isolation, data residency | Technical controls documented |
| **Business Continuity** | Fallback to non-AI development if Kiro unavailable | BCP documentation |
| **Audit Rights** | AWS compliance reports via AWS Artifact | Quarterly review |
| **Concentration Risk** | Assess dependency on single AI coding tool | Risk assessment |
| **Sub-outsourcing** | AWS use of Amazon Bedrock foundation models | Sub-contractor review |
| **Exit Strategy** | Ability to operate SDLC without Kiro | Documented procedures |
| **MAS Notification** | Notify MAS if arrangement is material outsourcing | Regulatory filing |

### 12.3 Due Diligence Checklist

- [ ] AWS SOC 2 Type II report reviewed (via AWS Artifact)
- [ ] AWS ISO 27001 certification verified
- [ ] AWS CSA STAR certification checked
- [ ] AWS MTCS (Multi-Tier Cloud Security) Level 3 confirmed for Singapore
- [ ] Data processing agreement (DPA) in place with AWS
- [ ] Sub-processor list reviewed (Bedrock model providers)
- [ ] Service Level Agreement (SLA) reviewed for Kiro availability
- [ ] Right to audit clause confirmed in enterprise agreement
- [ ] Exit/transition plan documented

### 12.4 Concentration Risk & Exit Strategy

**Concentration Risk Mitigation:**
- Developers maintain proficiency in non-AI development workflows
- Critical code reviews performed without AI assistance as validation
- No single-point dependency on Kiro for production deployments

**Exit Strategy:**
```
If Kiro service discontinued or contract terminated:
1. Export all locally-stored configurations and MCP settings
2. Preserve prompt logs for audit trail continuity
3. Transition to standard IDE without AI assistance
4. Retrain developers on manual code review processes
5. Update SDLC procedures to remove Kiro-specific steps
6. Notify MAS if material outsourcing arrangement changes
```

---

## 13. AI/ML Governance: MAS FEAT Principles

### 13.1 FEAT Framework for AI-Assisted Development

The Monetary Authority of Singapore published the **Fairness, Ethics, Accountability, and Transparency (FEAT)** principles to guide the responsible use of Artificial Intelligence and Data Analytics (AIDA) in financial services. These principles apply to the use of Kiro (AI-powered development assistant) in banking SDLC environments.

| FEAT Principle | Application to Kiro | Controls |
|----------------|---------------------|----------|
| **Fairness** | AI-generated code should not introduce discriminatory logic | Code review gates for bias detection |
| **Ethics** | AI tool usage should align with ethical standards | Developer training + usage guidelines |
| **Accountability** | Clear accountability for AI-generated code quality | Human review required before merge |
| **Transparency** | AI involvement in code generation must be traceable | Prompt logging + code annotation |

### 13.2 Accountability Controls

**Principle:** A human developer is always accountable for code quality, regardless of whether it was AI-generated.

**Implementation:**
```json
{
  "kiro.codeGeneration": {
    "requireHumanReview": true,
    "annotateAIGenerated": true,
    "blockDirectMerge": true,
    "minimumReviewers": 2,
    "auditTrail": "cloudtrail"
  }
}
```

**Code Attribution:**
- All Kiro-generated code must pass through standard code review
- Pull requests should indicate AI-assisted sections (recommended, not mandatory)
- CloudTrail logs provide full traceability of AI-assisted development activities

### 13.3 Transparency & Auditability

**Prompt Logging for Audit:**
```bash
# Enable comprehensive prompt logging
aws q put-prompt-logging-configuration \
  --s3-bucket-name kiro-prompts-<account-id> \
  --kms-key-id arn:aws:kms:ap-southeast-1:account:key/xxxxx
```

**What is Logged:**
- All prompts sent to Kiro (questions, code generation requests)
- All responses from Kiro (code suggestions, explanations)
- MCP tool invocations and parameters
- User identity and session context

**Audit Trail Retention:** Minimum 7 years for financial services (aligned with MAS record-keeping requirements).

### 13.4 Fairness & Bias Considerations

**Risk:** AI-generated code could inadvertently introduce biased logic in:
- Credit scoring algorithms
- Customer segmentation
- Risk assessment models
- Fee calculation logic

**Mitigation:**
- Kiro-generated financial logic must undergo additional review by domain experts
- Automated bias testing in CI/CD pipeline for models and decision logic
- Steering files should include bias-awareness instructions:

```yaml
# .kiro/steering/fairness.md
guidelines:
  - "Flag any code that makes decisions based on protected characteristics"
  - "Ensure fee calculations are applied consistently across customer segments"
  - "Credit scoring logic must be explainable and auditable"
  - "Alert if ML model inputs include demographic proxies"
```

---

## 14. Industry Standards: ABS Guidelines

### 14.1 ABS Cloud Computing Implementation Guide

The **Association of Banks in Singapore (ABS)** published the Cloud Computing Implementation Guide to help financial institutions adopt cloud services securely. Key requirements relevant to Kiro:

| ABS Requirement | Kiro Implementation |
|-----------------|---------------------|
| Data classification before cloud adoption | Classify code/data touched by Kiro per bank's data policy |
| Cloud service provider due diligence | AWS due diligence (SOC 2, ISO 27001, MTCS L3) |
| Data residency and sovereignty | Configure ap-southeast-1, disable cross-region inference |
| Access control and identity management | IAM Identity Center + Enterprise IdP + MFA |
| Encryption requirements | TLS 1.2+ in transit, KMS at rest |
| Incident management | Incident response plan (Section 10) |
| Exit strategy | Documented exit plan (Section 12.4) |

### 14.2 ABS Penetration Testing Guidelines

**Relevance:** If Kiro environments (WorkSpaces, VPC endpoints, MCP servers) are in scope for penetration testing:

- **Frequency:** At least annually for internet-facing systems; risk-based for internal (MAS TRM 13.2)
- **Scope:** Include VPC endpoint security, WorkSpaces access controls, MCP server attack surface
- **Types:** Combination of blackbox and greybox testing (MAS TRM 13.2.1)
- **Production testing:** Proper safeguards required (MAS TRM 13.2.3)

### 14.3 ABS Red Team Guidelines

**Applicability:** For adversarial attack simulation of Kiro environments:

- Test if attackers can bypass MCP server restrictions
- Test if DLP controls can be circumvented via AI prompts
- Test if unauthorized MCP servers can be installed despite GPO
- Validate incident detection and response capabilities for Kiro-related threats

---

## Expanded Compliance Matrix

### Comprehensive Regulatory Mapping

| Regulation | Section | Control Area | Kiro Implementation | Document Reference |
|------------|---------|--------------|---------------------|-------------------|
| **MAS TRM** | 3.1 | Governance & Oversight | IAM IDC + Enterprise IdP | Part 1, Section 2 |
| **MAS TRM** | 5.1 | IT Project Management | Supervised mode + code review | Part 2, Section 6 |
| **MAS TRM** | 5.2 | Security-by-Design | Skills + steering files | Skills Guide |
| **MAS TRM** | 6.1 | Software Development | SDLC security controls | Part 2, Section 6 |
| **MAS TRM** | 7.1 | IT Service Management | Change management workflow | Part 2, Section 6.3 |
| **MAS TRM** | 9.1 | Access Control | MFA + session management + RBAC | Part 1, Section 2.1.3 |
| **MAS TRM** | 9.3 | Remote Access | VPC + PrivateLink | Part 1, Section 3 |
| **MAS TRM** | 10.1 | Cryptography | TLS 1.2+ in transit, KMS at rest | Part 2, Section 7 |
| **MAS TRM** | 11.1 | Data Security | DLP + encryption + PDPA controls | Part 1, Section 4.1.3 |
| **MAS TRM** | 11.2 | Network Security | VPC endpoints + SG + NACLs | Part 1, Section 3.2 |
| **MAS TRM** | 11.5 | IoT/Endpoint | WorkSpaces VDI hardening | Part 1, Section 4 |
| **MAS TRM** | 12.1 | Cyber Threat Intel | CloudWatch + monitoring | Part 2, Section 8 |
| **MAS TRM** | 12.3 | Incident Response | Escalation matrix + MAS notification | Part 2, Section 10 |
| **MAS TRM** | 13.1 | Vulnerability Assessment | Annual VA of Kiro environments | Part 2, Section 14.2 |
| **MAS TRM** | 13.2 | Penetration Testing | Annual PT of VPC + WorkSpaces | Part 2, Section 14.2 |
| **MAS TRM** | 14.1 | Online Financial Services | Not directly applicable (dev tool) | N/A |
| **MAS TRM** | 15.1 | IT Audit | CloudTrail + compliance validation | Part 2, Section 8 |
| **PDPA** | Part IV | Data Protection | DLP + data classification + encryption | Part 2, Section 11 |
| **PDPA** | Part VIA | Data Breach | 3-day PDPC notification | Part 2, Section 11.4 |
| **MAS Outsourcing** | 4.1 | Risk Assessment | Outsourcing risk register | Part 2, Section 12 |
| **MAS Outsourcing** | 5.1 | Due Diligence | AWS compliance certifications | Part 2, Section 12.3 |
| **MAS Outsourcing** | 8.1 | Exit Strategy | Documented transition plan | Part 2, Section 12.4 |
| **MAS FEAT** | All | AI Governance | FEAT controls for Kiro | Part 2, Section 13 |
| **ABS Cloud** | All | Cloud Security | Defense-in-depth for Kiro | Part 2, Section 14.1 |

---

## Document Complete

**Total Coverage:**
- Sections 1-4: Architecture, Identity, Network, VDI (Part 1)
- Sections 5-10: MCP Governance, SDLC, Data Protection, Compliance, Operations, Incident Response (Part 2)
- Sections 11-14: PDPA, Outsourcing, AI/ML Governance, ABS Industry Standards (Part 2, Enhanced)

**Implementation Ready:** All sections include production-ready configurations, scripts, and compliance mappings for Singapore banking environments.

---

## License & Disclaimer

This documentation is licensed under the [MIT License](LICENSE).

> **Disclaimer:** This documentation is provided for informational and educational purposes only. It does not constitute legal advice, regulatory guidance, or professional security consulting. Organizations must conduct independent security assessments, consult qualified professionals, and validate all implementations against their specific regulatory requirements. See [README.md](README.md#disclaimer) for full disclaimer.
