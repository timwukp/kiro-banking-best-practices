# Contributing Guidelines

This repository contains MAS-aligned best practices for AWS Kiro in Singapore banking
environments: documentation, AWS CDK infrastructure, Kiro managed-settings policies, agent hooks,
MDM reference scripts and Kiro Skills. AI agents should also read [`AGENTS.md`](AGENTS.md).

## Pull-request flow

All changes go through a pull request. **Never push directly to `main`.**

1. Create a feature branch from an up-to-date `main`, for example
   `git switch -c docs/fix-mcp-registry-example` (prefixes such as `docs/`, `feat/`, `fix/`, `ci/`).
2. Make the change and run the local checks below.
3. Push the branch (`git push -u origin <branch>`) and open a pull request against `main`.
   Describe what changed, why, and which sources you verified.
4. CI (`.github/workflows/validate.yml`) must be green.
5. A maintainer reviews and merges the pull request.

## Local checks

Run the checks for the areas you touched; run all of them for cross-cutting changes. CI runs the
same commands. The shell tests need `bash` and `jq`; the PII pattern tests also use `perl`
(the PCRE checks are skipped without it).

| Area | Command | Expected |
|------|---------|----------|
| Whole repo (read-only) | `./validate-repo.sh` | `RESULT: PASSED`, 0 errors; review warnings (broken links, PII-shaped values) |
| CDK unit tests | `cd cdk && npm ci && npm test` | 86 tests pass |
| CDK lint | `cd cdk && npm run lint` | no errors |
| CDK synth + cdk-nag | `cd cdk && CDK_DEFAULT_ACCOUNT=000000000000 CDK_DEFAULT_REGION=ap-southeast-1 npx cdk synth --context env=dev` | synthesizes; cdk.json compiles with `tsc` first |
| Agent hooks | `bash agent-hooks/tests/run-tests.sh` | `PASS=98 FAIL=0` |
| PII skill patterns | `bash .kiro/skills/pii-detection/tests/patterns.test.sh` | `PASS=346 FAIL=0` |
| MDM (Linux script, dry run) | `bash mdm/tests/test-lockdown.sh` | `FAIL=0`; non-root, makes no system changes |

Optional per-OS MDM tests (also dry run by default, no root or admin):
`bash mdm/tests/test-lockdown-macos.sh` and
`powershell -ExecutionPolicy Bypass -File mdm\tests\test-lockdown-windows.ps1`.

If you change a hook script in `agent-hooks/`, regenerate `agent-hooks/SHA256SUMS` in the same
change as described in [`agent-hooks/README.md`](agent-hooks/README.md) and confirm
`(cd agent-hooks && shasum -a 256 -c SHA256SUMS)` passes (`sha256sum -c` on Linux; CI checks it).

## Content rules

### Sources

- Cite **primary sources**: the official Kiro documentation on [kiro.dev](https://kiro.dev/docs/)
  for Kiro behaviour, and [mas.gov.sg](https://www.mas.gov.sg/) for MAS requirements (TRM
  Guidelines, notices, FEAT). AWS service behaviour should cite docs.aws.amazon.com.
- Record when you checked a source, for example `> **Last verified:** 2026-10-08.` at the top of a
  page or "(verified 2026-10-08)" next to a claim. Update the date when you re-verify.
- Where official pages conflict, follow the newer one and note the conflict. Do not describe a
  control as "tamper-proof" or "fail-closed" unless Kiro documents it that way.
- Keep the MAS TRM section cross-references accurate when you edit mapped content.

### CDK (`cdk/`)

- **Never rename physical resource names**, stack IDs, construct IDs of deployed resources or
  CfnOutput export names (see `cdk/lib/naming.ts`). A rename replaces or orphans retained
  resources and breaks cross-stack references.
- Every stack must pass cdk-nag `AwsSolutionsChecks`; a suppression needs a written reason.
- When you add or remove an AWS Config rule in `compliance-stack.ts`, update the
  `ComplianceRuleCount` CfnOutput and the count in `test/stacks.test.ts` in the same change.

### Managed settings and hooks

- Admin rules in `managed-settings/managed-settings*.json` may only use the `deny` or `ask`
  effect (CI rejects anything else).
- Hooks live in top-level `agent-hooks/`, not `.kiro/hooks/`.

### Diagrams

- The architecture diagrams are **Mermaid** blocks in `README.md`; edit them there.
- `diagrams/generate_diagrams.py` is optional and only produces the PNG exports in `diagrams/`
  (needs `pip install diagrams` and Graphviz).

## What to include

- Markdown documentation files (`*.md`)
- Code examples and configuration samples with placeholder data
- `.kiro/skills/` and `.kiro/steering/` sample configuration (intentional, documented in the README)

## What NOT to include

- PDF files (regulatory documents)
- `.kiro/specs/`, `.kiro/hooks/`, `.kiro/settings/` (local Kiro configuration; CI rejects them)
- Secrets or key material (`.env` files, `*.pem`, `*.key`, `*.p12`, `*.pfx`; see `.gitignore`)
- Any personally identifiable information (PII): real NRIC/FIN, account or card numbers
- Customer names, email addresses or contact information
- Real AWS account IDs or access keys (use `123456789012` and `AKIAIOSFODNN7EXAMPLE`)
- Proprietary or confidential information

## Pre-pull-request checklist

1. `./validate-repo.sh` passes with 0 errors, and you reviewed its warnings
2. The test suites for the areas you changed pass (table above)
3. No PDF, `.kiro/specs|hooks|settings` or secret files are staged (`git status`)
4. No PII or customer data is present; all examples use placeholder data
5. New or changed claims cite a primary source with a verified date

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Disclaimer

This documentation is provided "as is" without warranty. Contributors and maintainers assume no liability for implementations based on this guidance.
