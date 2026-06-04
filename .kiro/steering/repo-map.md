---
inclusion: always
---
# Repo map — Kiro Banking Best Practices

MAS-compliant AWS Kiro banking SDLC: docs + CDK + Skills/hooks (region `ap-southeast-1`).

- **Full doc map & onboarding:** `AGENTS.md` (agents) and the "Start Here" section of `README.md` (humans).
- **Enforced config-level security:** `kiro-docs/agent-runtime-governance.md` (CLI agent: tool permissions, hooks, OS file lockdown); enterprise/registry layer: `kiro-docs/security-governance-features.md`; MDM-managed immutable/self-healing lockdown across OSes: `kiro-docs/mdm-endpoint-enforcement.md`.
- **Reference locked-down agent + hooks:** `agent-hooks/`.
- **Rules:** never commit secrets/PII; nothing under `.kiro/specs|hooks|settings/`; hooks live in top-level `agent-hooks/`; validate with `./validate-repo.sh` + `bash agent-hooks/tests/run-tests.sh`.
