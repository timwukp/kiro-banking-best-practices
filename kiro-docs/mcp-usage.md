# MCP Tools Usage Guide

> **Source:** https://kiro.dev/docs/mcp/usage/ (updated 2026-09-30), with https://kiro.dev/docs/mcp/registry/ (2026-10-01) and https://kiro.dev/docs/permissions/ (2026-10-01).
> **Last verified:** 2026-10-08.

## Interacting with MCP Tools

### Direct Questions
Ask questions related to the server's domain:
```
Tell me about Amazon Bedrock
How do I configure S3 bucket policies?
```

### Specific Tool Requests
Request specific MCP tools by describing what you want:
```
Search AWS documentation for information about ECS task definitions
Get recommendations for AWS CloudFormation best practices
```

### Explicit Context
Provide explicit context for more control:
```
#[aws-docs] search_documentation Tell me about AWS Lambda
```

## MCP Tools Panel

Access the MCP panel:
1. Select Kiro icon in activity bar
2. Navigate to MCP servers tab
3. View all connected servers and available tools

### Managing Individual Tools

**Via Kiro Panel:**
1. Open Kiro panel → MCP servers
2. Expand a server to see tools
3. Click on a tool to:
   - Enable - Activate a disabled tool
   - Disable - Temporarily disable without removing server

**Via JSON Config:**
```json
{
  "mcpServers": {
    "github": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "-e", "GITHUB_PERSONAL_ACCESS_TOKEN", "ghcr.io/github/github-mcp-server"],
      "disabledTools": ["delete_repository", "force_push", "merge_pull_request"]
    }
  }
}
```

### Server-Level Actions
Right-click on server for:
- **Reconnect** - Restart connection
- **Disable** - Temporarily disable entire server
- **Disable All Tools** - Disable all tools at once
- **Enable All Tools** - Re-enable all tools
- **Show MCP Logs** - View detailed logs

## Tool Approval Process

When Kiro wants to use an MCP tool:
1. You'll see a prompt describing the tool
2. Review tool details and parameters
3. Click "Approve" or "Deny"

### Auto-Approving Trusted Tools

To avoid repeated prompts for tools you trust, add tool names to the `autoApprove` array of the server (official example):

```json
{
  "mcpServers": {
    "aws-docs": {
      "autoApprove": [
        "mcp_aws_docs_search_documentation",
        "mcp_aws_docs_read_documentation"
      ]
    }
  }
}
```

- **Naming:** the property is `autoApprove`. This page shows prefixed tool names (`mcp_<server>_<tool>`), while the configuration page describes the entries as plain "tool names". Check the name shown in the MCP panel (see [mcp-configuration.md](mcp-configuration.md)).
- **Permission rules win:** `autoApprove` only removes Kiro's own prompt. An `mcp` rule with `ask` or `deny` in `managed-settings.json` or any `permissions.yaml` still applies (deny > ask > allow). Permission rules for MCP use `<server>/<tool>` patterns, for example `aws-docs/*`.
- **Untrusted workspaces:** every MCP tool call asks for approval, including tools listed in `autoApprove`, and a call retried after the server asks you to sign in or open a URL asks again.
- **Approval freshness:** before any MCP tool runs, Kiro checks that its approval is still current, so an approval withdrawn or changed while the call was waiting is not applied.

### Registry Mode (Enterprise)

When an administrator configures an MCP registry (Kiro console > Settings > Shared settings > MCP Registry URL), the registry is the only source of servers that can run:

- Approved servers appear in the MCP panel; select one to add it to your configuration.
- Servers in your own `mcp.json` load only if their name matches a registry entry; others are hidden and never started (the IDE shows an "N servers hidden" notice). Ask the administrator to add a server you need.
- You can still override a registry server's environment variables (local servers), HTTP headers (remote servers) and timeout:

```json
{
  "mcpServers": {
    "github": {
      "type": "registry",
      "env": {
        "GITHUB_TOKEN": "$GITHUB_TOKEN",
        "GITHUB_ORG": "my-org"
      },
      "timeout": 60000
    }
  }
}
```

`env` and `headers` merge per key with the registry defaults; `timeout` is in milliseconds. Registry mode applies to IAM Identity Center and API-key users in the IDE and CLI, not to Kiro Web. If the client cannot reach the governance API, MCP is disabled until it reconnects (fails closed). See [mcp-security.md](mcp-security.md).

## Examples by Server Type

### AWS Documentation Server

**Searching documentation:**
```
Search AWS documentation for S3 bucket versioning
```

**Reading documentation:**
```
Read the AWS Lambda function URLs documentation
```

**Getting recommendations:**
```
Find related content to AWS ECS task definitions
```

### GitHub MCP Server

**Repository information:**
```
Show me information about the tensorflow/tensorflow repository
```

**Code search:**
```
Find examples of React hooks in facebook/react
```

**Issue management:**
```
Create an issue in my repository about the login bug
```

## Advanced Usage Techniques

### Chaining MCP Tools
```
First search AWS documentation for ECS task definitions, then find related content about service discovery
```

### Combining with Local Context
```
Based on my Terraform code, help me optimize my AWS Lambda configuration using best practices from AWS documentation
```

### Using MCP Tools in Specs
```
In the implementation phase, use AWS documentation to ensure our S3 bucket configuration follows best practices
```

## MCP Prompts

MCP servers can expose reusable prompt templates. Prompts appear in the `#` mention list in chat.

### Accessing Prompts
1. Type `#` in chat input
2. MCP prompts appear with MCP icon
3. Select a prompt to insert

### Prompts with Arguments
Some prompts accept arguments. When selected, an inline form appears to fill in parameters before the prompt is added.

## MCP Resource Templates

Resource templates are parameterized URI templates that resolve to specific content.

### Accessing Resource Templates
1. Type `#` in chat input
2. Resource templates appear with MCP icon
3. Select template to see argument form

### Filling in Template Parameters
After selecting a template, fill in the inline form. Kiro resolves the URI and includes the resource content as context.

## MCP Elicitation

During tool execution, an MCP server may need additional information from you.

### Form-Based Elicitation
Kiro renders an inline form with fields based on data type:
- **Text**: Text input (may include format hints)
- **Number**: Number input
- **Yes/No**: Checkbox
- **Choice**: Select dropdown

Required fields are marked, and default values are pre-filled.

### URL-Based Elicitation
Some servers request you visit an external URL (e.g., OAuth flow). Kiro displays the URL with an **Open** button.

### Security Considerations
- Kiro always shows which server is requesting information
- You can decline any elicitation request
- Servers should not request sensitive information like passwords

## Troubleshooting

### Tool Not Responding
1. Check MCP server status in Kiro panel
2. Review MCP logs for errors
3. Use Ask Kiro feature to resolve errors

### Incorrect Results
1. Rephrase request to be more specific
2. Check you're using appropriate tool
3. Verify MCP server has necessary permissions

### Tool Not Available
1. Ensure MCP server is properly configured
2. Check server is running and connected
3. Verify you have necessary permissions

## Best Practices

- Be specific in requests for relevant results
- Start with direct questions before explicit tool references
- Auto-approve only trusted, frequently used, read-only tools (in an untrusted workspace Kiro asks anyway)
- Combine MCP tools with local context for best results
- Check tool parameters before approval
