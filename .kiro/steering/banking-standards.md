# Banking Development Standards

## Security Requirements

- Follow MAS Technology Risk Management Guidelines (January 2021)
- Use AWS Secrets Manager for all credentials — never hardcode secrets
- All database queries must use parameterized statements
- Log all financial transactions with timestamp, user ID, action, resource, and outcome
- Encrypt data at rest with AWS KMS customer-managed keys
- Enforce TLS 1.2+ for all connections (TLS 1.3 preferred)

## Prohibited Patterns

- Never hardcode credentials, API keys, or connection strings
- No direct database connections from frontend code
- No unencrypted data transmission
- No PII in log messages, error responses, or stack traces
- No use of deprecated crypto: MD5, SHA-1, DES, 3DES, RC4
- No 0.0.0.0/0 ingress rules on security groups

## Data Handling

- All personal data must comply with Singapore PDPA
- NRIC, FIN, credit card numbers must be masked in any output
- Data residency: ap-southeast-1 (Singapore) only
- Minimum 90-day retention for audit logs, 7-year archive for financial records

## Code Review

- All code requires minimum 2 human reviewers before merge
- AI-generated code must be explicitly reviewed for bias in financial logic
- Security findings must be resolved before deployment
- Run PII detection scan before committing
