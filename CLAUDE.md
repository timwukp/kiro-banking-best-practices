# Kiro Banking Best Practices - Project Guide

## Project Overview

MAS-compliant best practices for deploying AWS Kiro in Singapore banking SDLC environments. This repo contains documentation, AWS CDK infrastructure (TypeScript), and Kiro Skills.

## Repository Structure

```
├── README.md                                  # Main README with architecture diagrams
├── Kiro-Agentic-SDLC-Banking-Best-Practices.md  # Sections 1-4: Auth, Network, VDI
├── Kiro-Banking-Best-Practices-Part2.md          # Sections 5-14: MCP, SDLC, PDPA, FEAT
├── Banking-Skills-Development-Guide.md           # How to build Kiro Skills for banking
├── cdk/                                          # AWS CDK TypeScript infrastructure
│   ├── lib/stacks/                               # 4 stacks: network, encryption, monitoring, compliance
│   ├── config/environments.ts                    # Dev/prod configs (ap-southeast-1)
│   ├── test/stacks.test.ts                       # Jest unit tests (17 tests)
│   └── bin/kiro-banking.ts                       # CDK app entry point
├── .kiro/skills/                                 # 3 Kiro Skills with reference materials
│   ├── mas-compliance-review/
│   ├── pii-detection/
│   └── banking-code-review/
└── kiro-docs/                                    # Kiro platform reference docs
```

## CDK Commands

```bash
cd cdk
npm install
npm test          # Run 17 Jest tests
npx cdk synth     # Generate CloudFormation templates
npx cdk diff      # Preview changes
```

## Key Conventions

- **Region:** ap-southeast-1 (Singapore) for all resources
- **Compliance:** All infrastructure maps to specific MAS TRM sections
- **CDK Nag:** Enabled by default - all stacks must pass AwsSolutionsChecks
- **Encryption:** Customer-managed KMS keys, key rotation enabled, RETAIN removal policy
- **Network:** Zero trust - no public subnets, no NAT gateways, no internet gateways
- **Architecture:** Two options - via IAM Identity Center (Option A) or direct IdP federation (Option B)

## When Editing

- CDK stacks are TypeScript in `cdk/lib/stacks/` - run `npm test` after changes
- Skills are Markdown in `.kiro/skills/` - each has a `SKILL.md` and optional `references/`
- Documentation references specific MAS TRM sections - maintain these cross-references
- If adding AWS Config rules to compliance-stack.ts, update the rule count in the CfnOutput and test
