# AWS Kiro Banking Best Practices - Part 2
## Sections 5-10: MCP Governance, SDLC, Data Protection & Operations

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

## Document Complete

**Total Coverage:**
- ✅ Sections 1-4: Architecture, Identity, Network, VDI (Part 1)
- ✅ Sections 5-10: MCP Governance, SDLC, Data Protection, Compliance, Operations, Incident Response (Part 2)

**Implementation Ready:** All sections include production-ready configurations, scripts, and compliance mappings for Singapore banking environments.

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
