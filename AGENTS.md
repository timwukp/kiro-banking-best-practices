# AGENTS.md — Repository guide for AI agents

> Auto-loaded by Kiro's default agent (alongside `README.md`, `.kiro/skills/`, `.kiro/steering/`).
> Human entry point: the **Start Here** section in [`README.md`](README.md). Keep this file terse.

## What this repo is
MAS-aligned best practices for deploying **AWS Kiro** in Singapore **banking** SDLC. Contents: documentation, AWS **CDK** (TypeScript) infrastructure, Kiro **managed settings**, and Kiro **Skills + hooks**. Workload region: `ap-southeast-1`; Kiro profile region: `us-east-1` or `eu-central-1` (Kiro has no Singapore profile region).

## Task → file
| If you need to… | Read / use |
|-----------------|------------|
| Deploy the admin policy (deny/ask rules, sign-in restriction), user permissions template, MCP registry example | `managed-settings/README.md` ← start here |
| Permission model reference (capabilities, precedence, hardcoded invariants, workspace trust, hooks, agents) | `kiro-docs/permissions-and-managed-settings.md` |
| Layer 4 governance model (admin policy → console settings → workspace trust → permissions → hooks → audit) | `kiro-docs/agent-runtime-governance.md` |
| Kiro console governance (models, MCP registry, web tools, API keys, Cloud Sessions) + model approval matrix | `kiro-docs/security-governance-features.md` |
| Defense-in-depth hooks and the reference agent | `agent-hooks/README.md`, `agent-hooks/hooks/banking-guards.json` |
| Deploy managed files with MDM (all OSes) | `kiro-docs/mdm-endpoint-enforcement.md`, `mdm/` |
| MCP governance (registry, pinned versions, config files) | `Kiro-Banking-Best-Practices-Part2.md` Section 5, `kiro-docs/mcp-security.md` |
| Auth, network & VDI (Sections 1–4) | `Kiro-Agentic-SDLC-Banking-Best-Practices.md` |
| MCP, SDLC, PDPA, FEAT (Sections 5–14) | `Kiro-Banking-Best-Practices-Part2.md` |
| Build a MAS-aligned Kiro Skill | `Banking-Skills-Development-Guide.md` |
| Red-team / validate the controls (chaos test) | `security-tests/chaos/run-chaos.sh`, `kiro-docs/chaos-pentest-evidence.md` |
| Deploy infrastructure | `cdk/` (see `cdk/README.md`) |
| MAS TRM mapping | `README.md` → "Compliance Framework" |

## Hard rules when working in this repo
- **Never commit secrets/PII** (real keys, NRIC, tokens, account IDs). Use placeholders: `example.com`, `AKIA…EXAMPLE`, `123456789012`.
- **Do not track** anything under `.kiro/specs/`, `.kiro/hooks/`, or `.kiro/settings/` (CI rejects it). `.kiro/skills/` and `.kiro/steering/` **are** committed.
- Agent **hooks live in top-level `agent-hooks/`**, not `.kiro/hooks/`; admin policy files live in `managed-settings/`.
- **Admin rules (`managed-settings*.json`) use only `deny` or `ask`** and only the documented fields; an `allow` rule or unknown field makes Kiro reject the whole file and deny all tool calls.
- **Kiro claims:** cite the official kiro.dev page with a verification date; where pages conflict, follow the newer one and note the conflict. Do not call a control "tamper-proof" or "fail-closed" unless Kiro documents it as such.
- **Changes go through a pull request** from a feature branch; never push to `main`. CI (`.github/workflows/validate.yml`) must pass. Run the commands below first.
- Default to **least privilege**.

## Commands (run from the repo root; CI runs the same)
| Check | Command | Expect |
|-------|---------|--------|
| Repo validator (read-only: required files, secrets/PII, links) | `./validate-repo.sh` | `RESULT: PASSED` (0 errors) |
| CDK tests / lint / synth | `cd cdk && npm test`; `npm run lint`; `npx cdk synth --context env=dev` | 86 tests pass; lint clean; synth OK (cdk.json builds with `tsc`) |
| Agent hooks (bash + jq) | `bash agent-hooks/tests/run-tests.sh` | `PASS=98 FAIL=0` |
| PII skill patterns (grep -E; perl for PCRE) | `bash .kiro/skills/pii-detection/tests/patterns.test.sh` | `PASS=346 FAIL=0` |
| MDM dry run (non-root, no system changes) | `bash mdm/tests/test-lockdown.sh` | `FAIL=0` |
| Hook manifest | `(cd agent-hooks && shasum -a 256 -c SHA256SUMS)` | all `OK` |
| Admin policy effects | `jq -e '[.rules[].effect] \| all(. == "deny" or . == "ask")' managed-settings/managed-settings*.json` | `true` |

## Hard rules for `cdk/`
- **cdk-nag** `AwsSolutionsChecks` is enabled by default and every stack must pass it; a suppression needs a written reason.
- **KMS:** customer-managed keys with key rotation enabled and `RemovalPolicy.RETAIN`.
- **Network:** the default egress mode is `none` (no public subnets, NAT gateways or internet gateways); `nat-dns-firewall` stays opt-in.
- **Regions:** workload region `ap-southeast-1`; Kiro profile region `us-east-1` or `eu-central-1` (`cdk/config/kiro-endpoints.ts`).
- **AWS Config rules:** when you add or remove a rule in `compliance-stack.ts`, update the `ComplianceRuleCount` CfnOutput and the count in `test/stacks.test.ts` in the same change.
- **Run `cd cdk && npm test`** (and `npm run lint`) after every CDK change.
- **Never rename** physical resource names, stack IDs, construct IDs of deployed resources or CfnOutput export names: renames replace or orphan retained resources and break cross-stack references.
- Map infrastructure to the MAS TRM sections it supports, and keep those cross-references in the docs.

## Enforced vs defense-in-depth vs guidance
- **Enforced by Kiro (client-side):** admin `deny`/`ask` rules and the sign-in restriction in `managed-settings.json` (an invalid file blocks all tool calls but drops the sign-in restriction); Kiro console settings (model allow list, MCP governance + registry, web tools, API keys, Cloud Sessions); workspace trust; Kiro hardcoded invariants (the agent can never write `~/.kiro/settings/` or `.kiro/settings/`, and always asks before writing `.git/**` or `.kiro` agents/hooks/workflows/powers). A user with local admin rights can bypass client-side controls; the authoritative boundaries are server-side (branch protection, IAM, egress allowlist).
- **Defense-in-depth:** user `permissions.yaml`, agent `permissions`, hooks (block only with exit code 2), OS-level protection of the managed files by MDM.
- **Guidance (advisory only):** `.kiro/steering/*`, `.kiro/skills/*`, this file.
