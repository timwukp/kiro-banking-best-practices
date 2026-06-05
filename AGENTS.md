# AGENTS.md — Repository guide for AI agents

> Auto-loaded by Kiro's default agent (alongside `README.md`, `.kiro/skills/`, `.kiro/steering/`).
> Human entry point: the **Start Here** section in [`README.md`](README.md). Keep this file terse.

## What this repo is
MAS-compliant best practices for deploying **AWS Kiro** in Singapore **banking** SDLC. Contents: documentation, AWS **CDK** (TypeScript) infrastructure, and Kiro **Skills + hooks**. Default region: `ap-southeast-1`.

## Task → file
| If you need to… | Read / use |
|-----------------|------------|
| Lock down the Kiro CLI agent (tool permissions, hooks, OS file lockdown) — **enforced config security** | `kiro-docs/agent-runtime-governance.md` ← start here |
| Enterprise / registry governance (MCP allow-list, models, web tools, subagents) | `kiro-docs/security-governance-features.md` |
| Make controls immutable / self-healing across clients (MDM, all OSes) | `kiro-docs/mdm-endpoint-enforcement.md` |
| Secure the MCP config file (`mcp.json`) | `kiro-docs/mcp-security.md` |
| Auth, network & VDI (Sections 1–4) | `Kiro-Agentic-SDLC-Banking-Best-Practices.md` |
| MCP, SDLC, PDPA, FEAT (Sections 5–14) | `Kiro-Banking-Best-Practices-Part2.md` |
| Build a MAS-compliant Kiro Skill | `Banking-Skills-Development-Guide.md` |
| Reference locked-down agent + hooks | `agent-hooks/banking-secure.agent.json`, `agent-hooks/*.sh` |
| Red-team / validate the controls (chaos test) | `security-tests/chaos/run-chaos.sh`, `kiro-docs/chaos-pentest-evidence.md` |
| Deploy infrastructure | `cdk/` (see `cdk/README.md`) |
| MAS TRM mapping | `README.md` → "Compliance Framework" |

## Hard rules when working in this repo
- **Never commit secrets/PII** (real keys, NRIC, tokens). Use placeholders: `example.com`, `AKIA…EXAMPLE`.
- **Do not track** anything under `.kiro/specs/`, `.kiro/hooks/`, or `.kiro/settings/` (CI rejects it). `.kiro/skills/` and `.kiro/steering/` **are** committed.
- Agent **hooks live in top-level `agent-hooks/`**, not `.kiro/hooks/`.
- **Validate before pushing:** `./validate-repo.sh` (expect 0 errors) and `bash agent-hooks/tests/run-tests.sh` (expect `FAIL=0`).
- Default to **least privilege**; the enforced controls are defined in `agent-runtime-governance.md`.

## Enforced vs guidance
- **Enforced** (blocks actions): agent `toolsSettings` deny rules, `preToolUse` hooks (exit 2), OS-level file lockdown, MCP registry allow-list, `chmod 600` on `mcp.json`.
- **Guidance** (advisory only): `.kiro/steering/*`, `.kiro/skills/*`.
