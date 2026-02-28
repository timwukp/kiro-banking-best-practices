---
name: banking-code-review
description: Conduct code reviews following Singapore banking security standards, MAS TRM guidelines, and PDPA requirements. Use when reviewing pull requests, preparing code for deployment, conducting security audits, or validating banking application code quality.
metadata:
  author: Development Standards Team
  version: 1.0.0
  regulations: MAS TRM, PDPA, MAS AIRG
---

# Banking Code Review Skill

## Purpose

Structured code review process for Singapore banking applications, ensuring security, compliance, and quality standards are met before code is merged or deployed.

## Activation Triggers

- "Review this code for banking standards"
- "Code review for this pull request"
- "Is this code ready for production?"
- "Security review of this change"
- "Check this PR against banking guidelines"

## Review Checklist

When reviewing code, check each category in order:

### 1. Security (MAS TRM Section 10) - CRITICAL

- [ ] No hardcoded credentials, API keys, or secrets
- [ ] TLS 1.2+ for all network connections (TLS 1.3 recommended)
- [ ] Input validation on ALL user inputs (whitelist approach)
- [ ] SQL injection prevention (parameterized queries only)
- [ ] XSS prevention (output encoding/escaping)
- [ ] CSRF protection on state-changing endpoints
- [ ] No use of deprecated crypto (MD5, SHA-1, DES, RC4)
- [ ] Secure random number generation for tokens/keys

### 2. Access Control (MAS TRM Section 9)

- [ ] Authentication required for all sensitive endpoints
- [ ] Authorization checks at both API and data layer
- [ ] No Insecure Direct Object References (IDOR)
- [ ] Session timeout configured (15 min for customer-facing)
- [ ] Failed login lockout (3 attempts max)
- [ ] Privilege escalation prevention

### 3. Data Protection (MAS TRM Section 11 + PDPA)

- [ ] PII encrypted at rest (KMS) and in transit (TLS)
- [ ] No PII in logs, error messages, or stack traces
- [ ] Data retention policy enforced in code
- [ ] Secure deletion when data no longer needed
- [ ] PDPA consent checks before data collection
- [ ] Data minimization (collect only what's needed)

### 4. Audit & Logging (MAS TRM Section 15)

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

### 6. AI-Generated Code Quality (MAS AIRG)

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

# PASS - Rate limited
from flask_limiter import Limiter
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
import boto3
secret = boto3.client('secretsmanager', region_name='ap-southeast-1')
db_creds = json.loads(secret.get_secret_value(SecretId='/banking/db')['SecretString'])
```

## Approval Criteria

Code can be approved when:
- All CRITICAL security checks passed
- No unresolved high-severity findings
- MAS compliance validated
- Minimum 2 human reviewers approved
- All automated tests passing
- PII detection scan clean

## Output Format

```markdown
# Banking Code Review
Date: {date}
PR: #{pr_number}
Reviewer: Kiro (AI-assisted) + {human_reviewer}

## Verdict: {APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION}

## Security: {pass_count}/{total_count} checks passed
## Data Protection: {pass_count}/{total_count} checks passed
## Code Quality: {pass_count}/{total_count} checks passed

## Issues Found
{categorized list with severity and remediation}

## Recommendation
{summary recommendation with specific actions}
```
