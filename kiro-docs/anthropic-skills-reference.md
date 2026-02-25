# Anthropic Agent Skills - Reference Implementation

Source: https://github.com/anthropics/skills

## Overview

Public repository containing Anthropic's implementation of skills for Claude. Demonstrates what's possible with Claude's skills system.

**Note:** This is Anthropic's implementation. For Agent Skills standard, see agentskills.io

## Repository Structure

### Skills Categories

1. **Creative & Design**
   - Art, music, design applications

2. **Development & Technical**
   - Testing web apps
   - MCP server generation

3. **Enterprise & Communication**
   - Communications workflows
   - Branding guidelines

4. **Document Skills** (Source-available, not open source)
   - `skills/docx` - Word document creation
   - `skills/pdf` - PDF manipulation
   - `skills/pptx` - PowerPoint creation
   - `skills/xlsx` - Excel spreadsheet handling

These document skills power Claude's document capabilities in production.

### Repository Contents

- `./skills` - Skill examples across all categories
- `./spec` - Agent Skills specification
- `./template` - Skill template for creating new skills

## Using Skills

### In Claude Code

Register repository as marketplace:
```bash
/plugin marketplace add anthropics/skills
```

Install specific skill sets:
1. Select `Browse and install plugins`
2. Select `anthropic-agent-skills`
3. Select `document-skills` or `example-skills`
4. Select `Install now`

Or directly:
```bash
/plugin install document-skills@anthropic-agent-skills
/plugin install example-skills@anthropic-agent-skills
```

Usage example:
```
"Use the PDF skill to extract the form fields from path/to/some-file.pdf"
```

### In Claude.ai

All example skills already available to paid plans in Claude.ai.

### Via Claude API

Use pre-built skills and upload custom skills via Claude API. See Skills API Quickstart.

## Creating a Basic Skill

Template structure:

```markdown
---
name: my-skill-name
description: A clear description of what this skill does and when to use it
---

# My Skill Name

[Add your instructions here that Claude will follow when this skill is active]

## Examples
- Example usage 1
- Example usage 2

## Guidelines
- Guideline 1
- Guideline 2
```

### Required Frontmatter Fields

- `name` - Unique identifier (lowercase, hyphens for spaces)
- `description` - Complete description of what skill does and when to use it

### Content Structure

Markdown content contains:
- Instructions
- Examples
- Guidelines

Claude follows these when skill is active.

## Partner Skills

Skills teach Claude how to use specific software better. Highlighted partner examples:

- **Notion** - [Notion Skills for Claude](https://www.notion.so/notiondevs/Notion-Skills-for-Claude-28da4445d27180c7af1df7d8615723d0)

## License

Many skills are open source (Apache 2.0). Document creation skills (docx, pdf, pptx, xlsx) are source-available for reference only.

## Disclaimer

**These skills are for demonstration and educational purposes only.** Implementations and behaviors in Claude may differ from what's shown. Always test skills thoroughly in your environment before relying on them for critical tasks.

## Key Takeaways for Banking Implementation

1. **Skills are portable** - Follow open standard, can be shared across tools
2. **Production-ready examples** - Document skills show complex, production-grade implementations
3. **Clear structure** - Simple YAML frontmatter + markdown instructions
4. **Marketplace model** - Can be distributed via plugin marketplaces
5. **Partner ecosystem** - Companies can create skills for their platforms

## Banking Use Cases

Potential banking skill applications:
- **Compliance review** - Automated MAS compliance checking
- **Security audit** - Code security scanning with banking standards
- **Documentation generation** - Regulatory documentation creation
- **Data validation** - PII detection and data quality checks
- **Deployment workflows** - Banking-specific deployment procedures
