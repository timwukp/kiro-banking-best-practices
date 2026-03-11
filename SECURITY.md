# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this repository, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

### How to Report

1. Email the maintainers with a description of the vulnerability
2. Include steps to reproduce the issue
3. Provide any relevant screenshots or logs (with sensitive data redacted)

### What to Expect

- Acknowledgment within 48 hours
- Assessment and severity classification within 5 business days
- Remediation timeline communicated based on severity

### Scope

This repository contains documentation, infrastructure-as-code (CDK), and Kiro Skills for banking environments. Security concerns may include:

- Insecure infrastructure patterns in CDK stacks
- Credentials or PII accidentally committed
- MAS TRM compliance gaps in recommended configurations
- Incorrect security guidance that could lead to vulnerabilities
- MCP server configurations that could expose sensitive data

### Out of Scope

- Vulnerabilities in AWS services themselves (report to [AWS Security](https://aws.amazon.com/security/vulnerability-reporting/))
- Vulnerabilities in Kiro IDE/CLI (report to [AWS](https://aws.amazon.com/security/vulnerability-reporting/))
- General MAS regulatory interpretation questions

## Security Best Practices

When contributing to this repository:

- Never commit real credentials, API keys, or PII
- Use example/placeholder values (e.g., `AKIAIOSFODNN7EXAMPLE`)
- Run `./validate-repo.sh` before pushing to scan for secrets
- Follow the MAS TRM guidelines documented in this repo
- All CDK changes must pass `cdk-nag` AwsSolutionsChecks

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.5.x   | Yes       |
| < 1.5   | No        |
