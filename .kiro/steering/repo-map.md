---
inclusion: always
---
# Repo map — Kiro Banking Best Practices

MAS-aligned Kiro banking SDLC: docs + CDK + Skills/hooks (workload region `ap-southeast-1`; Kiro profile region `us-east-1` or `eu-central-1`).

- **Full doc map & onboarding:** `AGENTS.md` (agents) and the "Start Here" section of `README.md` (humans).
- **Admin policy (client-enforced):** `managed-settings/` (`managed-settings.json`, `permissions.yaml` template, MCP registry example).
- **Governance model and console settings:** `kiro-docs/agent-runtime-governance.md` (Layer 4); console/registry layer and model approval matrix: `kiro-docs/security-governance-features.md`; MDM deployment across OSes: `kiro-docs/mdm-endpoint-enforcement.md`.
- **Reference agent + hooks (defense in depth):** `agent-hooks/`. **Red-team validation:** `security-tests/chaos/` + report `kiro-docs/chaos-pentest-evidence.md`.
- **Rules:** never commit secrets/PII; nothing under `.kiro/specs|hooks|settings/`; hooks live in top-level `agent-hooks/`; validate with `./validate-repo.sh` + `bash agent-hooks/tests/run-tests.sh`.
