---
inclusion: always
---
# Banking Development Standards

Steering is guidance for the agent, not an enforced control. Enforcement lives in managed settings, hooks, branch protection and CI.

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
- NRIC, FIN, credit card numbers must be masked in any output (NRIC/FIN `S****567D`; card and account numbers: last 4 digits)
- Do not use NRIC numbers as an authenticator or default password (PDPC/CSA advisory: cease by 31 Dec 2026)
- Application data and infrastructure: deploy in the workload region `ap-southeast-1` (institutional policy; MAS TRM does not mandate data localisation)
- Never put customer data, NRIC/FIN or production data in Kiro prompts or code context: Kiro stores and processes content in its profile region (`us-east-1` or `eu-central-1`), not in Singapore (PDPA s26 Transfer Limitation; banking secrecy)
- Audit logs retained for at least 90 days and financial records archived for 7 years (example institutional policy, not prescribed by MAS TRM; set per your record-keeping obligations)

## Code Review and Delivery

- When a change is ready, remind the user that it reaches `main` only through a pull request approved under branch protection (the number of approvals is institutional policy). Never merge, push to `main`, force-push, or bypass branch protection yourself.
- When you generate or change financial decision logic (credit, pricing, fees, eligibility), say so in your summary and ask the user to have it reviewed for bias and explainability.
- Do not describe a change as ready to deploy while it has unresolved Critical or High security findings; list them instead.
- Before suggesting a commit, scan the changed files for PII and secrets (pii-detection skill) and report the result.
