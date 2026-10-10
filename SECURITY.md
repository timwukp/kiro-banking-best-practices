# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.9.x   | Yes       |
| < 1.9   | No        |

Fixes are made on `main` and released in the next version; older versions are not patched.

## Reporting a Vulnerability

If you discover a security vulnerability in this repository, please report it privately.

**Do NOT put vulnerability details in a public GitHub issue, pull request or discussion.**

### How to Report

1. **Preferred: GitHub private vulnerability reporting.** Open the repository's **Security** tab
   and choose **Report a vulnerability**. The report is visible only to you and the maintainers.
2. **If that button is not available** (private reporting is not enabled), open a minimal public
   issue titled "Request for a private security contact". Do not include any details about the
   vulnerability; a maintainer will reply with a private channel.

In the private report, include:

- A description of the vulnerability and its impact
- The affected files, versions or commits
- Steps to reproduce
- Any relevant screenshots or logs, with credentials, PII and customer data removed

### What to Expect

- Acknowledgment within 48 hours
- Assessment and severity classification within 5 business days
- A remediation timeline communicated based on severity

### Scope

This repository contains documentation, infrastructure-as-code (CDK), Kiro managed-settings
policies, agent hooks, MDM reference scripts and Kiro Skills for banking environments. Security
concerns may include:

- Insecure infrastructure patterns in CDK stacks
- Managed-settings or permission examples that are weaker than documented
- Hooks, MDM scripts or tests that can be bypassed, or that execute untrusted input
- Credentials or PII accidentally committed
- MAS TRM compliance gaps in recommended configurations
- Incorrect security guidance that could lead to vulnerabilities
- MCP server configurations that could expose sensitive data

### Out of Scope

- Vulnerabilities in AWS services themselves (report to [AWS Security](https://aws.amazon.com/security/vulnerability-reporting/))
- Vulnerabilities in Kiro IDE/CLI (report to [AWS](https://aws.amazon.com/security/vulnerability-reporting/))
- General MAS regulatory interpretation questions

## Automated Checks

These checks are pattern-based safety nets, not a full secret scanner. They do not scan git
history, binary files or encoded content, and they do not recognise every credential format
(for example GitHub tokens, passwords or generic API keys). Enable GitHub secret scanning and
push protection on the repository as well.

### `./validate-repo.sh` (read-only, run locally and in CI)

It never modifies files and makes no network calls. It fails (exit 1) on ERRORs only.

| Check | Result on a finding |
|-------|--------------------|
| Required files present (README, AGENTS, SECURITY, CONTRIBUTING, CHANGELOG, Part 1/Part 2, Skills guide, `managed-settings/README.md`, `agent-hooks/README.md`, ...) | ERROR |
| No PDF files tracked; nothing tracked under `.kiro/specs/`, `.kiro/hooks/`, `.kiro/settings/` | ERROR |
| AWS access key IDs (`AKIA` + 16 characters); lines containing `EXAMPLE`/`example` are ignored | ERROR |
| PEM private-key headers (RSA, EC, DSA, OpenSSH, encrypted, PKCS#8 and PGP private keys) | ERROR |
| Email addresses (except `example.com`, placeholder and `noreply` addresses, badge URLs and `scheme://user:pass@host` samples) | WARNING |
| NRIC/FIN-shaped values (except lines documenting a regex and the synthetic `1234567` examples) | WARNING |
| Broken relative Markdown links in every tracked Markdown file, resolved from the linking file's directory | WARNING |
| TODO/FIXME markers in documentation, tracked files over 1 MB, root Markdown without an H1 | WARNING |

The secret and PII checks scan the root `*.md` and `*.sh` files, `kiro-docs/`, `.kiro/`, `cdk/`
(without `node_modules/`, `cdk.out/` and `build/`), `agent-hooks/`, `managed-settings/`, `mdm/`,
`security-tests/`, `diagrams/` and `.github/`. Two paths are excluded from the private-key, email
and NRIC checks because they document or assemble detection signatures on purpose:
`.kiro/skills/pii-detection/` (the skill, its reference patterns and its tests) and
`agent-hooks/tests/fixtures/`. The AWS key check has no path exclusions.

### CI (`.github/workflows/validate.yml`)

Runs on every pull request to `main`, on pushes to `main` and on manual dispatch, with
`contents: read` permissions only.

- **validate-docs**: required files, no PDFs, no `.kiro` private config, an inline secret scan
  (AWS key IDs in `*.md`, `*.ts`, `*.json`, `*.sh`, `*.tsv`; PEM private-key headers in `*.md`,
  `*.ts`, `*.pem`, `*.key`, `*.tsv`, with the same exclusions), H1 headings, then `./validate-repo.sh`.
- **validate-cdk**: `npm ci`, `npm audit --audit-level=high` (blocking: the job fails on any high
  or critical advisory), `tsc`, ESLint, the Jest tests and `cdk synth` with cdk-nag
  `AwsSolutionsChecks`.
- **validate-skills**: Skill frontmatter and the PII pattern regression tests
  (`.kiro/skills/pii-detection/tests/patterns.test.sh`).
- **validate-governance**: agent-hook regression tests, `agent-hooks/SHA256SUMS` verification,
  managed-settings JSON validity with deny/ask-only effects, hook/agent JSON validity, the MDM
  lockdown dry-run tests (non-root, no system changes) and `bash -n` on every shell script.

### Integration test (manual, sandbox AWS account)

CI has no AWS credentials and makes no system changes. The checks that need a real host or account are in
[`security-tests/aws-integration/`](security-tests/aws-integration/README.md), run manually in a
**sandbox account only**. It covers a real CDK deployment, the root and SYSTEM MDM lockdowns, the full
chaos harness, the DNS Firewall egress mode and the Kiro CLI behind the allowlist.

The test environment is isolated:
- the runners are reachable only through Systems Manager (no inbound rules, no SSH keys);
- IMDSv2 is required and volumes are encrypted;
- an on-instance failsafe shuts the runners down, and they terminate on shutdown;
- results go to a short-lived bucket;
- everything is torn down afterwards and checked with a leftover scan.

The sanitized results are in
[`kiro-docs/aws-integration-test-evidence.md`](kiro-docs/aws-integration-test-evidence.md).

## Security Best Practices

When contributing to this repository:

- Never commit real credentials, API keys, account IDs or PII
- Use example/placeholder values (e.g., `AKIAIOSFODNN7EXAMPLE`, `123456789012`, `example.com`)
- Run `./validate-repo.sh` before opening a pull request (see [CONTRIBUTING.md](CONTRIBUTING.md))
- Follow the MAS TRM guidelines documented in this repo
- All CDK changes must pass `cdk-nag` AwsSolutionsChecks
