# Kiro CLI Agent Skills

## How skills work

When you start a chat session, Kiro discovers available skills by reading their names and descriptions. When your request matches a skill's description, Kiro automatically loads the full instructions and follows them.

```bash
> Review this PR for security issues

[skill: pr-review activated]

I'll review the PR using the security checklist...
```

Skills activate automatically based on your request. No slash command needed. Kiro decides when skill is relevant by matching request against skill descriptions.

To see available skills: `/context show`

## Skill locations

| Location | Scope | Use case |
|----------|-------|----------|
| `.kiro/skills/` | Workspace | Project-specific workflows, team conventions |
| `~/.kiro/skills/` | Global | Personal workflows across all projects |

**Priority:** Workspace skills override global skills with same name.

### Default agent
Automatically loads skills from both locations. No configuration required.

### Custom agents
Don't load skills by default. Must explicitly add to agent's `resources` field:

```json
{
  "name": "my-agent",
  "resources": [
    "skill://.kiro/skills/*/SKILL.md",
    "skill://~/.kiro/skills/*/SKILL.md"
  ]
}
```

The `skill://` URI scheme supports specific paths, glob patterns, and home directory expansion.

## Creating a skill

Structure:
```
pr-review/
├── SKILL.md           # Required
└── references/        # Optional
    └── checklist.md
```

### SKILL.md format

```markdown
---
name: pr-review
description: Review pull requests for code quality, security issues, and test coverage. Use when reviewing PRs or preparing code for review.
---

## Review checklist

When reviewing a pull request:

1. Check for vulnerabilities, injection risks, exposed secrets
2. Verify edge cases and failure modes are handled
3. Confirm new code has appropriate tests
4. Ensure variables and functions have clear names

## Common issues to flag

- Hardcoded credentials or API keys
- Missing input validation
- Unhandled promise rejections
- Console.log statements left in production code
```

### Frontmatter fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Skill identifier. Lowercase letters, numbers, hyphens only. Max 64 characters |
| `description` | Yes | When to activate this skill. Kiro matches against requests. Max 1024 characters |

**Description determines activation.** Include specific keywords and actions matching how you'd phrase requests.

### Reference files

For extensive documentation, use `references/` folder:

```
aws-deployment/
├── SKILL.md
└── references/
    ├── ecs-guide.md
    └── troubleshooting.md
```

Reference in SKILL.md:
```markdown
For ECS deployments, follow the guide in `references/ecs-guide.md`.
```

Kiro loads reference files only when instructions direct it to.

## Example: CDK deployment skill

```
cdk-deploy/
├── SKILL.md
└── references/
    └── stack-patterns.md
```

**SKILL.md:**
```markdown
---
name: cdk-deploy
description: Deploy AWS CDK stacks with best practices. Use when deploying infrastructure, running cdk deploy, or troubleshooting CDK issues.
---

## Deployment workflow

1. Run `cdk synth` to validate templates before deploying
2. Use `cdk diff` to preview what will change
3. Run `cdk deploy` and review IAM changes

## Pre-deployment checks

- Verify AWS credentials are configured for target account
- Check CDK version matches project requirements
- Review `references/stack-patterns.md` for environment-specific patterns

## Rollback procedure

If deployment fails:
1. Check CloudFormation console for specific error
2. Run `cdk destroy` only if stack is in failed state
3. Fix issue and redeploy
```

Usage:
```bash
> Deploy my CDK stack to staging

[skill: cdk-deploy activated]

I'll follow the deployment workflow. First, let me synthesize the templates...
```

## Best practices

1. **Write precise descriptions** - Description determines activation
   - Good: "Review pull requests for security vulnerabilities and test coverage. Use when reviewing PRs or preparing code for review."
   - Vague: "Helps with code review"

2. **Keep SKILL.md actionable** - Put detailed reference material in `references/` files

3. **Choose right scope** - Global for personal workflows, workspace for team procedures

4. **Version control workspace skills** - Commit `.kiro/skills/` to repository for team sharing

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Skill not activating | Make description more specific with keywords matching request |
| Skill not found | Verify SKILL.md exists with valid frontmatter |
| Custom agent missing skills | Add `skill://` URIs to agent's `resources` field |
| Wrong skill activating | Differentiate descriptions with more specific keywords |

Source: https://kiro.dev/docs/cli/skills/
