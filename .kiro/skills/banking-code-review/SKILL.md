---
name: banking-code-review
description: Review application source code and pull requests against Singapore banking secure-coding standards (OWASP Top 10, injection, IDOR and access control, authentication and sessions, cryptography, hardcoded secrets, logging, error handling, transaction integrity and race conditions) and recommend approve or request changes against the approval criteria. Use when asked to review this code for banking standards, do a code review of this pull request, check whether this code is ready for production, do a security review of this change, check this PR against banking guidelines, or review AI-generated code before merge. Not for mapping infrastructure or controls to MAS TRM sections, MAS notices or PDPA obligations, or for audit preparation (use mas-compliance-review), and not for scanning or masking PII and secrets on their own (use pii-detection).
metadata:
  author: Development Standards Team
  version: 1.1.0
  regulations: MAS TRM, PDPA, MAS Guidelines on Artificial Intelligence Risk Management
---

# Banking Code Review Skill

## Purpose

Structured code review process for Singapore banking applications, ensuring security, compliance, and quality standards are met before code is merged or deployed.

## Scope and related skills

- **This skill:** application code review, covering:
  - secure coding and OWASP Top 10 risks;
  - banking transaction logic;
  - AI-generated code;
  - a recommended verdict against the approval criteria below.
- **mas-compliance-review:** use it to map controls or infrastructure-as-code (CDK, CloudFormation, Terraform) to MAS TRM sections, MAS notices and PDPA obligations, or to prepare audit evidence. This review cites TRM sections for each check, but leaves the regulatory mapping and IaC review to that skill.
- **pii-detection:** the approval criteria call for a clean PII and secrets scan. Use that skill for it, and for masking or redacting any value found.
- The verdict is a recommendation. Humans approve and merge under branch protection; never approve, merge or push to `main` on the user's behalf.

## Review Checklist

When reviewing code, check each category in order:

### 1. Secure Coding (MAS TRM 6.1) - CRITICAL

- [ ] No hardcoded credentials, API keys, or secrets
- [ ] TLS 1.2+ for all network connections (TLS 1.3 recommended) (TRM 10.1)
- [ ] Input validation on ALL user inputs (whitelist approach)
- [ ] SQL injection prevention (parameterized queries only)
- [ ] XSS prevention (output encoding/escaping)
- [ ] CSRF protection on state-changing endpoints
- [ ] No use of deprecated crypto (MD5, SHA-1, DES, 3DES, RC4) (TRM 10.1)
- [ ] Secure random number generation for tokens/keys

### 2. Access Control (MAS TRM Section 9)

- [ ] Authentication required for all sensitive endpoints
- [ ] Authorization checks at both API and data layer
- [ ] No Insecure Direct Object References (IDOR)
- [ ] Session timeout configured (example institutional policy, not prescribed by MAS TRM: 15 min for customer-facing)
- [ ] Failed login lockout (example institutional policy, not prescribed by MAS TRM: 3 attempts max)
- [ ] Privilege escalation prevention (TRM 9.2)
- [ ] Customer-facing authentication uses MFA / transaction signing where required (TRM 14.2)
- [ ] NRIC numbers not used as an authenticator or default password (PDPC/CSA advisory: cease by 31 Dec 2026)

### 3. Data Protection (MAS TRM 11.1 + PDPA)

- [ ] PII encrypted at rest (KMS) and in transit (TLS)
- [ ] No PII in logs, error messages, or stack traces; where a value must be shown, it is masked (NRIC/FIN `S****567D`; card and account numbers: last 4 digits)
- [ ] Data retention policy enforced in code
- [ ] Secure deletion when data no longer needed
- [ ] PDPA consent checks before data collection
- [ ] Data minimization (collect only what's needed)

### 4. Audit & Logging (MAS TRM 12.2)

The logs also serve as evidence for the independent IT audit function (TRM 15.1).

- [ ] All financial transactions logged with:
  - Timestamp, user ID, action, resource, outcome
- [ ] Log integrity protected (append-only, immutable)
- [ ] No sensitive data in log messages
- [ ] Error handling doesn't leak internal details
- [ ] Structured logging format (JSON preferred)

### 5. Error Handling & Resilience

- [ ] No sensitive data in error messages returned to users
- [ ] Proper exception handling (no bare except/catch)
- [ ] Graceful degradation for external service failures
- [ ] Circuit breaker pattern for downstream calls
- [ ] Retry logic with exponential backoff

### 6. AI-Generated Code Quality (MAS TRM 6.1, 6.3; MAS Guidelines on Artificial Intelligence Risk Management)

- [ ] AI-generated code reviewed by human developer
- [ ] No bias in financial decision logic
- [ ] Explainability for automated decisions
- [ ] Test coverage for AI-generated functions

## Common Banking Vulnerabilities

### SQL Injection
```python
# FAIL
query = f"SELECT * FROM accounts WHERE id = {user_input}"

# PASS
cursor.execute("SELECT * FROM accounts WHERE id = %s", (user_input,))
```

### Insecure Direct Object Reference (IDOR)
```python
# FAIL - Any user can access any account
account = Account.objects.get(id=request.GET['account_id'])

# PASS - Scoped to authenticated user
account = Account.objects.get(id=request.GET['account_id'], user=request.user)
```

### Missing Rate Limiting
```python
# FAIL - No rate limiting on login
@app.route('/login', methods=['POST'])
def login():
    return authenticate(request.json)

# PASS - Rate limited (Flask-Limiter 3.x)
from flask import Flask, request
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

app = Flask(__name__)
limiter = Limiter(
    get_remote_address,
    app=app,
    storage_uri="redis://ratelimit.internal:6379",  # shared store, so the limit holds across instances
)

@app.route('/login', methods=['POST'])
@limiter.limit("5 per minute")
def login():
    return authenticate(request.json)
```

### Credential Exposure
```python
# FAIL - Credentials in environment config
DATABASE_URL = "postgresql://admin:password123@db.internal:5432/banking"

# PASS - Secrets Manager
import json
import boto3

secret = boto3.client('secretsmanager', region_name='ap-southeast-1')
db_creds = json.loads(secret.get_secret_value(SecretId='/banking/db')['SecretString'])
```

## Approval Criteria

Recommend APPROVE only when:
- All CRITICAL security checks passed
- No unresolved high-severity findings
- MAS TRM alignment checks passed (see the checklist above)
- All automated tests passing
- PII detection scan clean (pii-detection skill)

Then remind the user that the change still needs the human approvals required by branch protection (the number of reviewers is set by institutional policy) before it is merged. Kiro does not approve, merge or push to `main`.

## Output Format

```markdown
# Banking Code Review
Date: {date}
PR: #{pr_number}
Reviewer: Kiro (AI-assisted) + {human_reviewer}

## Recommended verdict: {APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION}
(Recommendation only; merge requires the human approvals set by branch protection.)

## Security: {pass_count}/{total_count} checks passed
## Data Protection: {pass_count}/{total_count} checks passed
## Code Quality: {pass_count}/{total_count} checks passed

## Issues Found
{categorized list with severity and remediation}

## Recommendation
{summary recommendation with specific actions}
```

## References

- See `references/banking-security-checklist.md` for the full review checklist with code examples
- See `references/owasp-banking-top10.md` for OWASP Top 10 mapped to MAS TRM sections
