# Kiro IDE Agent Skills

## What are skills?

Skills are portable instruction packages that follow the open Agent Skills standard. They bundle instructions, scripts, and templates into reusable packages that Kiro can activate when relevant to your task.

Kiro supports the Agent Skills standard, so you can import skills from the community or other compatible AI tools, and share your own skills across the ecosystem.

## How skills work

AI agents are increasingly capable, but they often lack the specific context needed for real work. Without knowledge of your team's deployment process, your company's code review standards, or your project's data analysis pipeline, agents guess and iterate.

Skills solve this with progressive disclosure:
1. **Discovery** - At startup, Kiro loads only the name and description of each skill
2. **Activation** - When your request matches a skill's description, Kiro loads the full instructions
3. **Execution** - Kiro follows the instructions, loading scripts or reference files only as needed

## Skill scope

### Workspace skills
- Location: `.kiro/skills/`
- Scope: Project-specific
- Use for: Project-specific workflows, deployment procedures, team conventions

### Global skills
- Location: `~/.kiro/skills/`
- Scope: All workspaces
- Use for: Personal workflows, code review process, documentation standards

**Priority:** Workspace skills override global skills with same name.

## Creating a skill

Structure:
```
my-skill/
├── SKILL.md           # Required
├── scripts/           # Optional executable code
├── references/        # Optional documentation
└── assets/            # Optional templates
```

### SKILL.md format

```markdown
---
name: pr-review
description: Review pull requests for code quality, security issues, and test coverage. Use when reviewing PRs or preparing code for review.
---

## Review process

1. Check for security vulnerabilities
2. Verify error handling
3. Confirm test coverage
4. Review naming and structure
```

### Frontmatter fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Must match folder name. Lowercase, numbers, hyphens only (max 64 chars) |
| `description` | Yes | When to use this skill. Kiro matches this against requests (max 1024 chars) |
| `license` | No | License name or reference to bundled license file |
| `compatibility` | No | Environment requirements (e.g., required tools, network access) |
| `metadata` | No | Additional key-value data like author or version |

## How skills differ from steering and powers

**Skills:** Portable packages following open standard. Load on-demand, can include scripts. Use for reusable workflows to share or import.

**Steering:** Kiro-specific context that shapes agent behavior. Supports `always`, `auto`, `fileMatch`, `manual` modes. Use for project standards.

**Powers:** Bundle MCP tools with knowledge and workflows. Activate dynamically based on context. Use for integrations needing both tools and guidance.

## Best practices

1. **Write precise descriptions** - Include specific keywords: "Review pull requests for security and test coverage" beats "helps with code review"
2. **Keep SKILL.md focused** - Put detailed docs in `references/` files
3. **Use scripts for deterministic tasks** - Validation, file generation, API calls
4. **Choose the right scope** - Global for personal workflows, workspace for team procedures

## Importing skills

1. Open **Agent Steering & Skills** in Kiro panel
2. Click **+** and select **Import a skill**
3. Choose source:
   - **GitHub** - Import from public repository URL
   - **Local folder** - Import from filesystem

Source: https://kiro.dev/docs/skills/
