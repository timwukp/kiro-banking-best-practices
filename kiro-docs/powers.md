# Kiro Powers: Dynamic MCP Context Loading

## The Problem Powers Solve

### 1. Without framework context, agents guess
Your agent can query Neon, but does it understand connection pooling for serverless? It can call APIs, but does it know the right patterns? Without built-in expertise, you're both manually reading documentation and refining approaches.

### 2. With too much context, agents slow down
Connect five MCP servers and your agent loads 100+ tool definitions before writing code. Five servers might consume 50,000+ tokens—40% of context window—before your first prompt. This leads to slower responses and lower quality output (context rot).

## What are Powers?

Powers provide unified approach: MCP tools + framework expertise—packaged together and loaded dynamically.

A power is a bundle that includes:
1. **POWER.md**: Entry point steering file—onboarding manual telling agent what MCP tools are available and when to use them
2. **MCP server configuration**: Tools and connection details for MCP server
3. **Additional steering or hooks**: Things you want agent to run (hooks, steering files via slash commands)

## How Powers Work

**Dynamic MCP tool loading:**
- Traditional MCP servers load all tools upfront
- Powers load tools on-demand
- Install five powers = near-zero baseline context usage
- Mention "design" → Figma power activates (8 tools)
- Switch to database → Supabase activates, Figma deactivates
- Agent only loads tools relevant to current task

## Power Ecosystem

### Partner Powers
Launch partners include:
- **UI Development:** Figma
- **Backend:** Supabase, Stripe, Postman, Neon
- **Agent Development:** Strands
- **Deployment:** Netlify, Amazon Aurora
- **Monitoring:** Datadog, Dynatrace

### Community Powers
- SaaS builder
- AWS CDK infrastructure development
- Amazon Aurora DSQL

### Installation
- **One-click install:** Browse in Kiro IDE or kiro.dev
- **GitHub import:** Import from public repository URLs
- **Local import:** Import from local directories or private repos

## Anatomy of a Power

### 1. Frontmatter: Activation Keywords

```yaml
---
name: supabase
keywords: [database, postgres, supabase, sql, auth, storage]
---
```

When you say "Let's set up the database," Kiro detects "database" and activates Supabase power.

### 2. Onboarding with POWER.md

```markdown
## Onboarding

When first activated:
1. Check if Docker is running
2. Validate Supabase CLI installation
3. Create performance review hook in workspace
```

### 3. Workflow-specific Steering

```markdown
## Steering Map

- RLS policies: `supabase-database-rls-policies.md`
- Edge Functions: `supabase-edge-functions.md`
- Auth setup: `supabase-auth.md`
```

Agent loads only relevant steering for current task.

## Powers vs Skills vs Steering

| Feature | Powers | Skills | Steering |
|---------|--------|--------|----------|
| **Purpose** | MCP tools + knowledge | Portable instructions | Project context |
| **Standard** | Kiro-specific | Open Agent Skills | Kiro-specific |
| **Loading** | Dynamic on-demand | On-demand | Always/auto/manual |
| **Includes** | MCP server + docs | Instructions + scripts | Context + conventions |
| **Best for** | Tool integrations | Reusable workflows | Project standards |

## Cross-Compatibility (Coming Soon)

Powers will work across AI development tools:
- Kiro CLI
- Cline
- Cursor
- Claude Code

Build once, use anywhere.

## The Future: Continual Learning

Powers enable continual learning model:
- Supabase ships updated RLS patterns → Agent gets them automatically
- Team builds internal design system → Package as power, all developers' agents know it
- Frameworks evolve → Powers update without agent retraining

Agents become useful by learning what they need, when they need it, continuously expanding expertise as tools evolve.

Source: https://kiro.dev/blog/introducing-powers/
