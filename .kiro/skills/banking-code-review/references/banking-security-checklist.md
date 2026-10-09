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
- [ ] Session timeout: 15 min for customer-facing, 2 hours for internal tools (example institutional policy, not prescribed by MAS TRM)
- [ ] Session invalidation on logout
- [ ] Secure cookie flags: HttpOnly, Secure, SameSite
- [ ] CSRF protection on state-changing endpoints

#### Audit Trail (MAS TRM 12.2)
- [ ] Financial transactions logged with: timestamp, user, action, resource, outcome
- [ ] Log integrity protected (append-only)
- [ ] Minimum 90-day log retention (example institutional policy, not prescribed by MAS TRM)
- [ ] No sensitive data in logs

### Priority 4: Code Quality

#### AI-Generated Code (MAS TRM 6.1; MAS Guidelines on Artificial Intelligence Risk Management)
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

# FAIL: validated, but the balance is read without a lock (same race as the next pattern)
amount = Decimal(request.json['amount'])
if amount <= 0 or amount > account.balance:
    raise ValidationError("Invalid amount")
transfer(from_account, to_account, amount)

# PASS: server-side validation, then one atomic conditional UPDATE inside a transaction
from decimal import Decimal, InvalidOperation

MAX_TRANSFER = Decimal("200000.00")  # per institutional limits

def parse_amount(raw) -> Decimal:
    try:
        amount = Decimal(str(raw))
    except (InvalidOperation, ValueError):
        raise ValidationError("Invalid amount")
    if (not amount.is_finite() or amount <= 0 or amount > MAX_TRANSFER
            or amount != amount.quantize(Decimal("0.01"))):
        raise ValidationError("Invalid amount")
    return amount

amount = parse_amount(request.json.get('amount'))
with db.transaction():
    debited = db.execute(
        "UPDATE accounts SET balance = balance - %s "
        "WHERE id = %s AND owner_id = %s AND balance >= %s",
        (amount, from_account_id, current_user.id, amount),
    ).rowcount
    if debited != 1:  # not the caller's account, or insufficient funds
        raise ValidationError("Transfer rejected")
    credit(to_account_id, amount)  # same transaction: both legs commit or neither does
```

The balance check and the debit happen in a single statement, so two concurrent requests cannot both pass the check. `SELECT ... FOR UPDATE` (next pattern) is the alternative when the logic needs the row in application code.

### Pattern: Race Condition in Balance Check
```python
# FAIL: Check-then-act without locking
if account.balance >= amount:
    account.balance -= amount  # Race condition!

# PASS: Atomic operation with database lock (SELECT ... FOR UPDATE; Peewee shown)
with db.atomic():
    account = Account.select().where(
        Account.id == account_id
    ).for_update().get()   # row stays locked until the transaction commits
    if account.balance >= amount:
        account.balance -= amount
        account.save()
```

### Pattern: Insufficient Logging
```python
# FAIL: No audit trail
def transfer(from_acc, to_acc, amount):
    execute_transfer(from_acc, to_acc, amount)

# FAIL: audit trail that logs full account numbers (PII in logs)
logger.info(json.dumps({"event": "transfer_initiated", "from": from_acc, "to": to_acc}))

# PASS: complete audit trail with internal account IDs, not account numbers
import json
from datetime import datetime, timezone

def mask_account(number: str) -> str:
    """1234567890 -> ******7890 (use only where a person must recognise the account)."""
    return "*" * (len(number) - 4) + number[-4:]

def transfer(from_account_id, to_account_id, amount):
    base = {
        "user": get_current_user_id(),
        "trace_id": get_trace_id(),
        "from_account_id": from_account_id,  # internal surrogate key, not the account number
        "to_account_id": to_account_id,
        "amount": str(amount),
    }
    audit_log.info(json.dumps({**base, "event": "transfer_initiated",
                               "timestamp": datetime.now(timezone.utc).isoformat()}))
    result = execute_transfer(from_account_id, to_account_id, amount)
    audit_log.info(json.dumps({**base, "event": "transfer_completed",
                               "outcome": result.status,
                               "reference": result.ref_id,
                               "timestamp": datetime.now(timezone.utc).isoformat()}))
```
