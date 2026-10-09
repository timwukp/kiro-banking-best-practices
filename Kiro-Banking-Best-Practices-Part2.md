# AWS Kiro Banking Best Practices - Part 2
## Sections 5-14: MCP Governance, SDLC, Data Protection, Operations & Regulatory Compliance

> **Audience:** security architects, compliance officers, banking developers · **Purpose:** Sections 5–14 — MCP governance, SDLC, PDPA, FEAT, operations · **Prerequisites:** read Part 1 (Sections 1–4) first · ↩ [README](README.md)

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

### 7.2 Data Location & Residency

> **⚠️ Data Location Note:** Kiro (Amazon Q Developer) profiles currently exist only in **us-east-1 (N. Virginia)** or **eu-central-1 (Frankfurt)** — there is **no** Singapore (`ap-southeast-1`) profile option. Your content, prompt logs, and user activity reports are stored in the profile region by architectural requirement. MAS TRM Guidelines do **not** impose a data localisation mandate — data residency in Singapore is a customer preference, not a regulatory requirement.

**Clarification: Data Residency vs. Regulatory Requirement**

MAS TRM Guidelines focus on **data protection controls** (encryption, access control, audit trails) rather than prescribing where data must physically reside. Financial institutions may choose to keep data in Singapore for business, contractual, or risk-appetite reasons, but this is not a MAS-imposed localisation mandate.

**Regional Reality for Kiro:**
- **Profile / Service Region:** Kiro profiles are hosted in `us-east-1` or `eu-central-1` only. Content (including customizations) is stored in the profile region. There is no `ap-southeast-1` profile.
- **Logging:** Prompt log and user activity report S3 buckets **must** reside in the AWS Region where the Kiro profile was installed. Cross-account buckets are not supported.
- **Inference:** Kiro is powered by Amazon Bedrock and uses cross-region inference. Requests are kept within the AWS Regions of the profile's geography — a US profile stays within US Regions (us-east-1, us-west-2, us-east-2) and does **not** route to Singapore.
- **Mitigation (if residency is preferred):** Use S3 Cross-Region Replication (CRR) to replicate the profile-region log bucket to `ap-southeast-1` for local access. This produces a regional **copy**; the authoritative log location remains the profile region.
- **VPC / network:** Developer traffic can still use `ap-southeast-1` VPC endpoints / PrivateLink for network-layer isolation, but this is connectivity hygiene — it does not change where Kiro processes or stores data.

**References:**
- [AWS Docs: Cross-region processing in Amazon Q Developer](https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/cross-region-processing.html)
- [Kiro Docs: Viewing per-user activity](https://kiro.dev/docs/cli/enterprise/monitor-and-track/user-activity/)
- [Amazon Q Developer European Region announcement (us-east-1 / eu-central-1)](https://aws.amazon.com/blogs/devops/amazon-q-developer-european-region/)
- [Amazon S3 Cross-Region Replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)

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
| Encryption | 10.1 (TLS), 10.2 (key management) | TLS 1.2+ + KMS customer-managed keys with rotation | KMS key policy |
| Data Security | 11.1 | DLP + Encryption | DLP reports |
| Network Security | 11.2 | VPC + PrivateLink | VPC flow logs |
| Audit Logging & Monitoring | 12.2 | CloudTrail + CloudWatch | S3 audit bucket |

TRM 15.1 (IT Audit) covers the independent audit function, which uses these logs as evidence; it is not the logging control itself. The matrix shows where controls support each TRM section. Each institution remains responsible for its own compliance assessment.

> **Upcoming: proposed TRM Notice amendments (MAS Consultation Paper P012-2026, 10 June 2026, not yet finalised).** MAS proposes requiring a comprehensive IT asset inventory that includes open-source and third-party components (with direct and indirect dependencies), IT risk assessments that cover the IT supply chain and the use of AI, change-management controls that prevent unauthorised changes and test all changes to critical systems, and immutable or offline backups. For AI coding assistants, this means recording Kiro, its MCP servers and the dependencies it introduces in the asset inventory, and routing Kiro-generated changes through the normal change-management controls. ([consultation paper](https://www.mas.gov.sg/publications/consultations/2026/consultation-paper-on-proposed-amendments-to-notices-on-technology-risk-management))

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

**S3 Lifecycle Policy (example institutional policy, not prescribed by MAS TRM: move to Glacier after 90 days, expire after ~7 years; set the expiry per your record-keeping obligations, commonly 5–7 years):**
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

These response times are example internal SLAs (institutional policy). Regulatory notification deadlines are separate; see Section 10.3.

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
- Compliance team: Immediately, in parallel with the security team, so that a relevant-incident decision can be made inside the MAS 1-hour window
- MAS (banks, [MAS Notice FSM-N05](https://www.mas.gov.sg/regulation/notices/notice-fsm-n05) para 7): as soon as possible, and **not later than 1 hour** after discovery of a relevant incident
- MAS root cause and impact analysis report (FSM-N05 para 8): within **14 days** of discovery of the relevant incident, or a longer period if MAS allows
- PDPC: if personal data is involved, run the PDPA breach assessment in Section 11.4 (separate clock)

A **relevant incident** under FSM-N05 is a system malfunction or IT security incident that has a severe and widespread impact on the bank's operations or materially impacts the bank's service to its customers. Most Kiro-specific events (for example a DLP violation) will not meet this threshold, but a credential exposure or a compromised pipeline that affects critical systems or customer services could.

> **Other FIs:** FSM-N05 applies to banks. Merchant banks and non-bank FIs follow their own sector TRM notice (for example FSM-N11 for merchant banks, FSM-N03 for insurers, FSM-N13 for designated payment systems and digital payment token service providers, FSM-N21 for capital markets FIs, FSM-N23 for licensed financial advisers). Verify the wording of your sector notice. The former sector notices (such as Notice 644) were cancelled with effect from 10 May 2024. The MAS Circular on FI incident reporting (effective 1 February 2026) changes the reporting template and channel, not the deadlines.

### 10.4 Escalation Matrix

```
Level 1: Developer → Team Lead (15 min)
Level 2: Team Lead → Security Team (30 min)
Level 3: Security Team → CISO (1 hour)
Level 4: CISO → MAS (relevant incident: as soon as possible, ≤1 hour from discovery; RCA report ≤14 days)
```

The MAS 1-hour clock runs from discovery, not from CISO escalation. If an incident may be a relevant incident, escalate Levels 1–4 in parallel rather than one after another.

### 10.5 Availability and Recovery (MAS Notice FSM-N05 paras 5–6)

Consider whether Kiro is part of a critical system. Usually it is not, but the CI/CD pipeline and repositories it writes to may be. For each critical system, banks must meet:

- **Availability (para 5):** maximum unscheduled downtime of 4 hours in any 12-month period.
- **Recovery (para 6):** recovery time objective (RTO) of no more than 4 hours, validated at least once every 12 months.

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
| **Accountability** | The organisation is responsible for personal data in its possession or under its control, including data that Kiro/AWS processes on its behalf | Designated DPO; data protection policies that cover AI-assisted development |
| **Consent** | Code processing personal data must have valid consent basis | Kiro prompts should reference consent requirements |
| **Purpose Limitation** | Personal data used only for stated purposes | DLP policies block unauthorized data access |
| **Notification** | Individuals informed of data collection purposes | Audit logs track what data Kiro accesses |
| **Access & Correction** | Individuals can request access to their data | Data handling code must support DSAR workflows |
| **Accuracy** | Reasonable effort to ensure data is accurate | Validation logic in Kiro-generated code |
| **Protection** | Reasonable security to protect personal data | Encryption, DLP, VPC isolation |
| **Retention Limitation** | Data not kept longer than necessary | Kiro prompt logs subject to retention policy |
| **Transfer Limitation** | Cross-border transfer restrictions | Data residency in ap-southeast-1 (Singapore) |
| **Data Breach Notification** | Assess expeditiously whether a breach is notifiable; notify PDPC no later than 3 calendar days after determining it is notifiable (see 11.4) | Incident response plan must include PDPC notification |

- **Transfer Limitation Obligation (PDPA s26):** if personal data is transferred outside Singapore (for example, personal data in prompts or code context that Kiro processes in another region; see Section 7.2), the organisation must ensure the recipient protects it to a standard comparable to the PDPA. Under the PDP Regulations 2021 this is done through legally enforceable obligations (such as contract clauses that specify the destination countries, or binding corporate rules), specified certifications (APEC/Global CBPR, or PRP for data intermediaries), or one of the deemed-compliance cases. The organisation remains responsible when its data intermediary or cloud provider transfers the data overseas (PDPC Advisory Guidelines on Key Concepts, ch. 19).

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

> **NRIC used for authentication:** in a joint advisory (PDPC press release, 2 February 2026), PDPC and CSA advised that organisations cease using NRIC numbers for authentication by **31 December 2026**. Code reviews of Kiro-generated code should flag any use of an NRIC number as a password, default password or other authenticator. The PDPC Advisory Guidelines on NRIC and other national identification numbers (31 August 2018) continue to apply to collection, use and disclosure.

### 11.3 PDPA Compliance Checklist for Kiro

- [ ] Data classification policy defined for AI-assisted development
- [ ] DLP rules enforce PDPA data categories in Kiro prompts
- [ ] Developer training covers PDPA obligations when using AI tools
- [ ] Prompt logging enabled with a documented, purpose-based retention period (PDPA s25 sets no fixed maximum; keep logs only as long as needed for legal or business purposes)
- [ ] Data residency confirmed in Singapore region (ap-southeast-1)
- [ ] Cross-region inference disabled for PDPA-regulated workloads
- [ ] Transfer limitation (s26) safeguards documented for any personal data processed outside Singapore
- [ ] Data breach notification process includes PDPC (assessment generally within 30 days; notify PDPC ≤3 calendar days after determining the breach is notifiable)
- [ ] Code review flags NRIC numbers used for authentication (cease by 31 December 2026)
- [ ] Privacy impact assessment completed for Kiro deployment
- [ ] Data intermediary obligations assessed (Kiro/AWS as data intermediary)

### 11.4 PDPA Breach Notification

**Timeline (PDPA Part 6A, introduced by the PDPA Amendment 2020; PDPC Advisory Guidelines on Key Concepts, ch. 20):**

```
Data breach discovered
  └─ Assess expeditiously whether the breach is notifiable
     (PDPC guidance: generally within 30 calendar days)
     └─ Notifiable if EITHER test is met:
        (a) significant harm: prescribed classes of personal data in the
            PDP (Notification of Data Breaches) Regulations 2021, or
        (b) significant scale: 500 or more affected individuals
        └─ Notify PDPC as soon as practicable, no later than
           3 calendar days after determining the breach is notifiable
        └─ Notify affected individuals as soon as practicable, at the same
           time as or after notifying PDPC (where significant harm is likely)
```

**Integration with Incident Response (Section 10):**
- Severity "Critical" and "High" incidents must trigger PDPA breach assessment
- Security team must assess PDPA notification requirements alongside MAS reporting (the MAS 1-hour and PDPC 3-day clocks run independently)

---

## 12. MAS Outsourcing and Third-Party Services

### 12.1 Kiro as an Outsourced Service

**Context:** AWS Kiro is an AWS-managed AI development service. Each financial institution must assess whether using it is an outsourcing arrangement and, if so, whether it is material, under the current MAS outsourcing regime (effective 11 December 2024):

- **Banks:** [MAS Notice 658](https://www.mas.gov.sg/regulation/notices/notice-658) (Management of Outsourced Relevant Services for Banks) and the [Guidelines on Outsourcing (Banks)](https://www.mas.gov.sg/regulation/guidelines/guidelines-on-outsourcing-banks) (Annex 2 covers cloud computing). Merchant banks: Notice 1121.
- **Other FIs:** [Guidelines on Outsourcing (Financial Institutions other than Banks)](https://www.mas.gov.sg/regulation/guidelines/guidelines-on-outsourcing-financial-institutions-other-than-banks) (last revised 24 January 2025; Annex 5 covers cloud computing).
- The previous Guidelines on Outsourcing (July 2016, revised October 2018) are cancelled; they applied only until 10 December 2024. Do not rely on their section numbers.

**Third-party services (MAS TRM 3.4):** TRM 3.4 (Management of Third Party Services) applies whether or not Kiro is an outsourcing arrangement. TRM 3.4.1 recognises that not every third-party service constitutes outsourcing, so perform and document a materiality assessment instead of assuming either outcome. The same applies to MCP servers and to the model providers behind Kiro.

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
| **Materiality & Risk Assessment** | Materiality assessment plus technology risk assessment of Kiro deployment | Risk register entry |
| **Third-Party Services (TRM 3.4)** | Third-party risk management for Kiro, MCP servers and model providers, even where not outsourcing | Third-party register entry |
| **Due Diligence** | Review AWS assurance reports and confirm which ones cover Kiro (see 12.3) | AWS Artifact reports |
| **Contractual Protections** | AWS Enterprise Agreement / Addendum | Legal review |
| **Data Protection** | Encryption, DLP, VPC isolation, data residency | Technical controls documented |
| **Business Continuity** | Fallback to non-AI development if Kiro unavailable | BCP documentation |
| **Audit and Access Rights** | Contractual audit and access rights for the FI and MAS; AWS compliance reports via AWS Artifact | Quarterly review |
| **Concentration Risk** | Assess dependency on single AI coding tool | Risk assessment |
| **Sub-outsourcing** | AWS use of Amazon Bedrock foundation models | Sub-contractor review |
| **Exit Strategy** | Ability to operate SDLC without Kiro | Documented procedures |
| **MAS Notification** | Notify MAS if arrangement is material outsourcing | Regulatory filing |

### 12.3 Due Diligence Checklist

> **Scope check:** Kiro's own [compliance validation page](https://kiro.dev/docs/privacy-and-security/compliance-validation/) lists only HIPAA eligibility and inclusion in AWS's ISO/IEC 27001:2022 scope. Do not assume AWS SOC 2 / MTCS L3 reports cover Kiro; check AWS Artifact and the AWS services-in-scope pages.

- [ ] Materiality assessment documented (outsourcing or other third-party service; TRM 3.4.1)
- [ ] AWS SOC 2 Type II report reviewed (via AWS Artifact) and Kiro scope checked
- [ ] AWS ISO/IEC 27001 certificate reviewed and Kiro scope checked
- [ ] AWS CSA STAR scope checked for Kiro
- [ ] AWS MTCS (Multi-Tier Cloud Security) Level 3 scope checked for Kiro (do not assume coverage)
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

## 13. AI/ML Governance: MAS FEAT Principles and AI Risk Management Guidelines

### 13.1 FEAT Framework for AI-Assisted Development

The Monetary Authority of Singapore published the **Principles to Promote Fairness, Ethics, Accountability and Transparency (FEAT) in the Use of Artificial Intelligence and Data Analytics in Singapore's Financial Sector** (12 November 2018; para 1.4 revised 7 February 2019). FEAT applies to AI and data analytics (AIDA) used in decision-making in the provision of financial products and services. It is not a direct requirement for coding assistants. This guide applies the FEAT principles **by analogy** to AI-assisted development with Kiro, and more directly to code that Kiro helps build for customer-facing decision systems (for example credit scoring or pricing). FEAT is non-prescriptive, so calibrate these controls to materiality. For MAS's supervisory expectations on AI risk management, which cover all forms of AI including generative AI and AI agents, see Section 13.5.

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

**Audit Trail Retention:** Example institutional policy (not prescribed by MAS TRM): set the retention period per your record-keeping obligations (commonly 5–7 years).

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

### 13.5 MAS Guidelines on AI Risk Management (2026)

MAS published the final [Guidelines on Artificial Intelligence Risk Management](https://www.mas.gov.sg/regulation/guidelines/guidelines-on-artificial-intelligence-risk-management-for-financial-institutions) for financial institutions on **7 October 2026**, after consultation paper P017-2025 (13 November 2025).

- **Effective dates (para 1.8):** Sections 3–4 from 7 October 2027; Sections 5–6 by 7 October 2028.
- **Scope:** all FIs and all forms of AI, explicitly including generative AI / LLMs and AI agents (response paper para 2.8). The FEAT principles continue to apply (para 1.2).
- **Proportionality (para 2.3):** an FI may apply only basic AI governance policies where poor performance or unavailability of the AI tool is unlikely to have a material adverse impact; otherwise the full set of expectations (Sections 3–6) applies.
- **Coding assistants are not among the basic-tier examples.** Para 2.4 lists emails, summarising, document review, formulas/charts, image generation and internal chatbots. Kiro is an agentic coding assistant that writes and executes code, so assess its materiality yourself; do not assume the basic tier.
- **Footnote 12:** for copilots that assist in writing, some life-cycle controls may be less relevant, but controls on data management, safety and cybersecurity remain relevant and should be applied proportionately.
- **Para 2.5(b)** gives an example basic policy: prohibit inputting confidential, proprietary or client information into public AI tools. The prompt data classification in Section 11.2 supports this.
- **Agentic AI:** MAS will consult separately on additional guidance for agentic AI (response paper para 12.9). IMDA's Model AI Governance Framework for Agentic AI is cited as a reference.

**How this guide's controls support the Guidelines' themes:**

| Guidelines theme | Supporting controls in this guide | Section |
|------------------|-----------------------------------|---------|
| Governance and oversight | Senior management oversight of AI tool adoption (TRM 3.1); named owner for Kiro; AI usage policy | 12.1, 13.2 |
| AI inventory and risk materiality | Record Kiro, its models, MCP servers and custom agents in the AI inventory; document the para 2.3 materiality assessment | 12.1, 12.3 |
| Data management | Prompt data classification, DLP rules, PDPA controls | 11.1–11.3 |
| Safety and cybersecurity | MCP allowlist, network isolation, VDI, monitoring, penetration testing | 5, 8, 14; Part 1, Sections 3–4 |
| Human oversight / review of AI-generated code | Human review before merge, code review gates (TRM 6.1, 6.3), prompt logging | 6.3, 13.2, 13.3 |

---

## 14. Industry Standards: ABS Guidelines

### 14.1 ABS Cloud Computing Implementation Guide

The **Association of Banks in Singapore (ABS)** published the Cloud Computing Implementation Guide to help financial institutions adopt cloud services securely. Key requirements relevant to Kiro:

| ABS Requirement | Kiro Implementation |
|-----------------|---------------------|
| Data classification before cloud adoption | Classify code/data touched by Kiro per bank's data policy |
| Cloud service provider due diligence | AWS due diligence; confirm which assurance reports cover Kiro (Section 12.3) |
| Data residency and sovereignty | Configure ap-southeast-1, disable cross-region inference |
| Access control and identity management | IAM Identity Center + Enterprise IdP + MFA |
| Encryption requirements | TLS 1.2+ in transit, KMS at rest |
| Incident management | Incident response plan (Section 10) |
| Exit strategy | Documented exit plan (Section 12.4) |

### 14.2 Penetration Testing (MAS TRM 13.2; ABS Penetration Testing Guidelines)

**Relevance:** If Kiro environments (WorkSpaces, VPC endpoints, MCP servers) are in scope for penetration testing:

- **Frequency:** At least annually for internet-facing systems; risk-based for internal (MAS TRM 13.2)
- **Scope:** Include VPC endpoint security, WorkSpaces access controls, MCP server attack surface
- **Types:** Combination of blackbox and greybox testing (MAS TRM 13.2.1)
- **Production testing:** Proper safeguards required (MAS TRM 13.2.3)

### 14.3 ABS Red Team Guidelines

**Applicability:** For adversarial attack simulation of Kiro environments (MAS TRM 13.4):

- Test if attackers can bypass MCP server restrictions
- Test if DLP controls can be circumvented via AI prompts
- Test if unauthorized MCP servers can be installed despite GPO
- Validate incident detection and response capabilities for Kiro-related threats

---

## Expanded Compliance Matrix

### Comprehensive Regulatory Mapping

TRM section numbers follow the MAS Technology Risk Management Guidelines (January 2021). Each row shows where this guide's controls support a requirement; each institution remains responsible for its own compliance assessment.

| Regulation | Section | Control Area | Kiro Implementation | Document Reference |
|------------|---------|--------------|---------------------|-------------------|
| **MAS TRM** | 3.1, 3.2 | Governance & Oversight; Policies | Senior management oversight of Kiro adoption + AI usage policy | Part 2, Section 13.5 |
| **MAS TRM** | 3.4 | Management of Third Party Services | Kiro, MCP servers and model providers assessed as third-party services | Part 2, Section 12 |
| **MAS TRM** | 3.6 | Security Awareness and Training | Developer training on Kiro, MCP and PDPA | Part 2, Section 9.1 |
| **MAS TRM** | 5.4 | SDLC and Security-by-Design | Skills + steering files | Skills Guide |
| **MAS TRM** | 6.1 | Secure Coding, Source Code Review and Application Security Testing | Code review of AI-generated code (incl. third-party/open-source code, 6.1.3) + secret scanning | Part 2, Section 6 |
| **MAS TRM** | 6.3 | DevSecOps Management | Supervised mode + human approval before merge (segregation of duties) | Part 2, Section 6 |
| **MAS TRM** | 7.5 | Change Management | Change management workflow | Part 2, Section 6.3 |
| **MAS TRM** | 9.1 | User Access Management | Enterprise IdP + IAM IDC + MFA + session management + RBAC | Part 1, Section 2 |
| **MAS TRM** | 9.3 | Remote Access Management | WorkSpaces VDI as the remote access path | Part 1, Section 4 |
| **MAS TRM** | 10.1 | Cryptographic Algorithm and Protocol | TLS 1.2+ in transit | Part 2, Section 7 |
| **MAS TRM** | 10.2 | Cryptographic Key Management | KMS customer-managed keys + rotation | Part 2, Section 7.1 |
| **MAS TRM** | 11.1 | Data Security | DLP + encryption + PDPA controls | Part 1, Section 4.1.3 |
| **MAS TRM** | 11.2 | Network Security | VPC endpoints + PrivateLink + SG + NACLs | Part 1, Section 3 |
| **MAS TRM** | 11.3, 11.4 | System Security; Virtualisation Security | WorkSpaces VDI hardening | Part 1, Section 4 |
| **MAS TRM** | 12.2 | Cyber Event Monitoring and Detection | CloudTrail + CloudWatch + monitoring | Part 2, Section 8 |
| **MAS TRM** | 12.3 | Incident Response | Escalation matrix + MAS notification | Part 2, Section 10 |
| **MAS TRM** | 13.1 | Vulnerability Assessment | Annual VA of Kiro environments | Part 2, Section 14.2 |
| **MAS TRM** | 13.2 | Penetration Testing | Annual PT of VPC + WorkSpaces | Part 2, Section 14.2 |
| **MAS TRM** | 13.4 | Adversarial Attack Simulation Exercise | Red team of Kiro environments | Part 2, Section 14.3 |
| **MAS TRM** | 14.1 | Online Financial Services | Not directly applicable (dev tool) | N/A |
| **MAS TRM** | 15.1 | IT Audit | Independent IT audit of Kiro controls, using CloudTrail logs and compliance reports as evidence | Part 2, Section 8 |
| **MAS Notice FSM-N05** (banks) | paras 5–8 | Availability, recovery, incident notification | ≤4h downtime / RTO ≤4h for critical systems; notify MAS ≤1h; RCA report ≤14 days | Part 2, Section 10 |
| **PDPA** | s11–12 | Accountability | DPO + data protection policies covering AI-assisted development | Part 2, Section 11.1 |
| **PDPA** | s24 (Protection), s25 (Retention), s26 (Transfer Limitation) | Care of Personal Data (Part 6) | DLP + data classification + encryption + purpose-based retention + transfer safeguards | Part 2, Section 11 |
| **PDPA** | Part 6A | Data Breach Notification | Assess (generally ≤30 days); notify PDPC ≤3 calendar days after determining notifiable | Part 2, Section 11.4 |
| **MAS Outsourcing** | Materiality & risk assessment | Risk Assessment | Materiality assessment + outsourcing/third-party risk register | Part 2, Section 12 |
| **MAS Outsourcing** | Due diligence | Due Diligence | Review AWS assurance reports; confirm Kiro is in scope | Part 2, Section 12.3 |
| **MAS Outsourcing** | Exit / termination | Exit Strategy | Documented transition plan | Part 2, Section 12.4 |
| **MAS FEAT** | All | AI Governance (applied by analogy) | FEAT controls for Kiro | Part 2, Section 13 |
| **MAS AI Risk Management Guidelines** | Sections 3–6 | AI governance, inventory, materiality, life-cycle controls | Proportionate controls for Kiro | Part 2, Section 13.5 |
| **ABS Cloud** | All | Cloud Security | Defense-in-depth for Kiro | Part 2, Section 14.1 |

"MAS Outsourcing" means MAS Notice 658 and the Guidelines on Outsourcing (Banks) for banks, and the Guidelines on Outsourcing (Financial Institutions other than Banks) for other FIs, all effective 11 December 2024. Requirements are cited by topic because the section numbers of the cancelled 2016/2018 guidelines no longer apply.

---

## Document Complete

**Total Coverage:**
- Sections 1-4: Architecture, Identity, Network, VDI (Part 1)
- Sections 5-10: MCP Governance, SDLC, Data Protection, Compliance, Operations, Incident Response (Part 2)
- Sections 11-14: PDPA, Outsourcing, AI/ML Governance, ABS Industry Standards (Part 2, Enhanced)

**Reference Material:** All sections include reference configurations, scripts, and compliance mappings for Singapore banking environments. They are designed to support alignment with MAS and PDPA expectations and are not a substitute for your own testing; each institution remains responsible for its own compliance assessment.

---

## License & Disclaimer

This documentation is licensed under the [MIT License](LICENSE).

> **Disclaimer:** This documentation is provided for informational and educational purposes only. It does not constitute legal advice, regulatory guidance, or professional security consulting. Organizations must conduct independent security assessments, consult qualified professionals, and validate all implementations against their specific regulatory requirements. See [README.md](README.md#disclaimer) for full disclaimer.
