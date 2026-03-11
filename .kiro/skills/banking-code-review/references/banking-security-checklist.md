# Banking Security Code Review Checklist

## Quick Reference for Reviewers

### Priority 1: Critical Security (Block merge if failed)

#### Credential Management
- [ ] No hardcoded passwords, API keys, tokens, or connection strings
- [ ] Secrets retrieved from AWS Secrets Manager or SSM Parameter Store
- [ ] No credentials in environment variables committed to source control
- [ ] `.env` files in `.gitignore`

#### Injection Prevention
- [ ] SQL: Parameterized queries only (no string concatenation)
- [ ] NoSQL: Input sanitization for MongoDB/DynamoDB expressions
- [ ] Command injection: No `os.system()` or `subprocess.shell=True` with user input
- [ ] LDAP injection: Escaped special characters in directory queries

#### Authentication & Authorization
- [ ] MFA enforced for privileged operations
- [ ] Authorization checked at API layer AND data layer
- [ ] No Insecure Direct Object References (IDOR)
- [ ] JWT tokens validated (signature, expiry, issuer, audience)

### Priority 2: Data Protection (Block merge if PII exposed)

#### PII Handling
- [ ] No PII in log messages (NRIC, credit cards, bank accounts)
- [ ] PII masked in UI displays
- [ ] PII encrypted at rest (KMS) and in transit (TLS 1.2+)
- [ ] Data minimization: only collect what's needed

#### Encryption
- [ ] TLS 1.2+ for all network connections (TLS 1.3 preferred)
- [ ] No deprecated algorithms: MD5, SHA-1, DES, 3DES, RC4
- [ ] AWS KMS customer-managed keys for sensitive data
- [ ] Key rotation enabled

### Priority 3: Operational Security (Warning, should fix before prod)

#### Error Handling
- [ ] No stack traces or internal details in user-facing errors
- [ ] Structured logging (JSON format preferred)
- [ ] Graceful degradation for external service failures
- [ ] Circuit breakers for downstream calls

#### Session Management
- [ ] Session timeout: 15 min for customer-facing, 2 hours for internal tools
- [ ] Session invalidation on logout
- [ ] Secure cookie flags: HttpOnly, Secure, SameSite
- [ ] CSRF protection on state-changing endpoints

#### Audit Trail
- [ ] Financial transactions logged with: timestamp, user, action, resource, outcome
- [ ] Log integrity protected (append-only)
- [ ] Minimum 90-day log retention
- [ ] No sensitive data in logs

### Priority 4: Code Quality

#### AI-Generated Code (MAS AIRG)
- [ ] Human reviewer verified AI-generated logic
- [ ] No bias in financial decision-making (credit scoring, fees, risk)
- [ ] Automated decisions are explainable
- [ ] Test coverage for AI-generated functions

#### General Quality
- [ ] No `TODO` or `FIXME` in production code paths
- [ ] Error codes are meaningful (not generic 500s)
- [ ] Rate limiting on public-facing endpoints
- [ ] Input validation uses allowlist approach

## Common Banking Vulnerability Patterns

### Pattern: Transaction Amount Manipulation
```python
# FAIL: Amount from client without validation
amount = request.json['amount']
transfer(from_account, to_account, amount)

# PASS: Server-side validation
amount = Decimal(request.json['amount'])
if amount <= 0 or amount > account.balance:
    raise ValidationError("Invalid amount")
transfer(from_account, to_account, amount)
```

### Pattern: Race Condition in Balance Check
```python
# FAIL: Check-then-act without locking
if account.balance >= amount:
    account.balance -= amount  # Race condition!

# PASS: Atomic operation with database lock
with db.atomic():
    account = Account.select().where(
        Account.id == account_id
    ).for_update().get()
    if account.balance >= amount:
        account.balance -= amount
        account.save()
```

### Pattern: Insufficient Logging
```python
# FAIL: No audit trail
def transfer(from_acc, to_acc, amount):
    execute_transfer(from_acc, to_acc, amount)

# PASS: Complete audit trail
def transfer(from_acc, to_acc, amount):
    logger.info(json.dumps({
        "event": "transfer_initiated",
        "from": from_acc, "to": to_acc,
        "amount": str(amount),
        "user": get_current_user(),
        "timestamp": datetime.utcnow().isoformat(),
        "trace_id": get_trace_id()
    }))
    result = execute_transfer(from_acc, to_acc, amount)
    logger.info(json.dumps({
        "event": "transfer_completed",
        "status": result.status,
        "reference": result.ref_id
    }))
```
