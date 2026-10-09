# MCP Security Best Practices

> **Source:** https://kiro.dev/docs/mcp/security/ (updated 2026-08-04), with https://kiro.dev/docs/enterprise/governance/mcp/ (2026-08-04), https://kiro.dev/docs/mcp/registry/ (2026-10-01) and https://kiro.dev/docs/permissions/ (2026-10-01).
> **Last verified:** 2026-10-08.

## Understanding MCP security

MCP servers extend Kiro's capabilities by connecting to external services and APIs. MCP servers are third-party code, which introduces security considerations:

- **Access to sensitive information:** MCP servers may require API keys or tokens.
- **External code execution:** MCP servers run code outside of Kiro's sandbox.
- **Data transmission:** information flows between Kiro and external services.
- **Source verification:** review the source code and verify that the server comes from a trusted source before using it.
- **Isolation:** run servers in isolated environments when possible and limit the permissions granted.

**Official security warning (summary):** MCP stdio servers execute arbitrary commands in your environment with the same privileges as the agent: full access to the workspace filesystem, environment variables, secrets and session credentials. They run outside the agent's tool-execution sandbox and are not subject to the restrictions on agent tool calls, so a compromised or malicious server can exfiltrate code, credentials and data without further confirmation. Kiro does not vet, sandbox or restrict third-party MCP servers. For a bank, every MCP server is a third-party service to assess (MAS TRM 3.4) before it is added to the registry.

## Organization controls (enterprise)

Use these before relying on per-user configuration. Settings are in Kiro console > Settings > Shared settings and are part of the Kiro profile (organization level, overridable per account).

| Control | Effect | Notes |
|---------|--------|-------|
| MCP on/off toggle | Off suppresses all MCP servers: user-configured, legacy, registry and session-injected | Simplest option if MCP is not needed |
| MCP Registry URL | Only servers in the registry can run; all others are hidden, including the user's own `mcp.json` entries | Format and example: [`../managed-settings/mcp-registry.example.json`](../managed-settings/mcp-registry.example.json) |
| Pinned versions | `version` must be exact; ranges are rejected; a different local version is relaunched at the registry version | Pin to the version your third-party review approved |
| Refresh | Registry fetched at startup and every 24 hours; servers removed from the registry are terminated | Plan registry changes through change management (MAS TRM 7.5) |
| Fail closed | If the client cannot reach the governance API, MCP is disabled ("Failed to retrieve MCP settings — MCP disabled") | Usually transient; clears on reconnect |

- **Scope:** IAM Identity Center and API-key users, in the IDE and CLI. Builder ID and social sign-in users are not subject to organization MCP controls, which is another reason to restrict sign-in to the corporate method with `managed-settings.json` (see [`../managed-settings/`](../managed-settings/)). MCP governance and the registry do not apply to Kiro Web; keep Cloud Sessions off.
- **Hosting the registry:** HTTPS with a certificate from a trusted CA (no self-signed certificates); the URL may be private to the corporate network.
- **Client-side enforcement:** both the toggle and the registry "can be circumvented by users, e.g., via administrative access to their local machine". Developers should not have local admin rights.
- **Admin permission rule (optional):** `{"capability": "mcp", "effect": "ask"}` in `managed-settings.json` forces a prompt for every MCP tool call, even if users or `autoApprove` allow it. `{"capability": "mcp", "match": ["<server>/<tool>"], "effect": "deny"}` blocks individual tools.

## Untrusted workspaces

While a workspace is untrusted, Kiro:

- does not load the workspace MCP configuration (`.kiro/settings/mcp.json`), custom agents, steering, skills or workflows from the repository;
- asks before **every** MCP tool call and before every Power activation, content read or tool call, even when a saved rule or `autoApprove` allows it, and asks again when a call is retried after MCP authentication or a URL prompt;
- still applies any matching deny rule.

Before any MCP tool runs, Kiro checks that its approval is still current, so an approval withdrawn while the call was waiting is not applied. Trust only repositories from your own Git server after review; a cloned repository cannot mark itself trusted.

## Secure configuration

### Configuration file locations

The documented locations are `~/.kiro/settings/mcp.json` (user) and `.kiro/settings/mcp.json` (workspace). The agent can never write either file (Kiro hardcoded deny). `C:\ProgramData\Kiro\mcp.json` is not a documented Kiro location. Lock MCP down with governance, the registry and workspace trust, not by deploying or symlinking `mcp.json` files.

Docs conflict: the MCP registry page refers to `~/.kiro/mcp.json` and `.kiro/mcp.json`; this reference follows the configuration page.

### Protecting API keys and tokens

1. Never commit configuration files with sensitive tokens to version control.
2. Create tokens with the minimal permissions the MCP server needs (for example, fine-grained GitHub personal access tokens instead of classic tokens).
3. Limit access scope to only the repositories or resources needed.
4. Rotate API keys and tokens used in configurations regularly.
5. Use environment variables instead of hardcoding values; store credentials in the system keychain.

### Example: Using environment variables

```json
{
  "mcpServers": {
    "github": {
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

### Approved environment variables (IDE)

Kiro IDE only expands environment variables that are explicitly approved. When you add or modify an MCP server configuration that includes unapproved environment variables, Kiro displays a security warning listing them.

To manage approved environment variables:

1. Open Kiro settings.
2. Search for "Mcp Approved Env Vars".
3. Add the environment variables you want to allow for expansion.

### Configuration file permissions

```bash
# Set restrictive permissions on user-level config
chmod 600 ~/.kiro/settings/mcp.json

# Set restrictive permissions on workspace-level config
chmod 600 .kiro/settings/mcp.json
```

## Safe tool usage

### Tool approval process

1. Review each tool request carefully before approval.
2. Check the parameters being passed to the tool.
3. Understand what the tool will do before approving it.
4. Deny any suspicious requests that don't match your current task.

### Auto-approval guidelines

Only auto-approve tools that:

1. don't have write access to sensitive systems;
2. come from trusted sources with verified code;
3. are used frequently in your workflow;
4. have limited scope of what they can access.

The property is `autoApprove`; its entry format differs between official pages (plain tool names versus prefixed names such as `mcp_aws_docs_search_documentation`; see [mcp-configuration.md](mcp-configuration.md)). In a banking deployment prefer `mcp` permission rules (`<server>/<tool>`) over `autoApprove`, keep write-capable tools prompting, and remember that an admin `ask` or `deny` overrides both.

### Access control

- Apply least privilege to server permissions.
- Limit filesystem access to the directories needed.
- Restrict network access where possible.
- Use `disabledTools` to remove dangerous operations:

```json
{
  "mcpServers": {
    "github": {
      "disabledTools": ["delete_repository", "force_push"]
    }
  }
}
```

## Workspace isolation

Workspace-level configuration keeps project-specific servers, tokens and risks contained to that project. In a bank, combine it with the registry (which decides which servers may run at all) and workspace trust (which decides whether a repository's MCP configuration is loaded).

## Monitoring and auditing

### Checking MCP logs

1. Open the Kiro panel.
2. Select the Output tab.
3. Choose "Kiro - MCP Logs" from the dropdown.

### Auditing tool usage

- Check MCP configurations for auto-approved tools.
- Review the MCP logs for tool usage patterns.
- Monitor server activity for unexpected behavior.
- Remove auto-approval for tools you no longer use frequently.
- MCP tools run on the client, and Kiro documents no CloudTrail event for individual MCP tool calls. Use Kiro prompt logging, hook-based local logs and the logs of the target systems instead.

## Responding to security incidents

If you suspect a security issue with an MCP server:

1. Disable the server immediately (remove it from the registry, or turn MCP off for the profile).
2. Revoke any tokens or API keys associated with the server.
3. Check for unauthorized activity in the connected services.
4. Report the issue to the MCP server maintainer and follow your incident process (MAS TRM 12.3).

## Additional security measures

### Network security

1. Use HTTPS for remote MCP servers and verify TLS certificates.
2. Use firewalls to restrict outbound connections from MCP servers.
3. Monitor network traffic for unusual activity.
4. Be cautious with servers that require broad network access.

### System security

1. Keep your system updated with security patches.
2. Run MCP servers with minimal privileges.
3. Use separate user accounts for running sensitive MCP servers.
4. Only install MCP servers from trusted sources and check for security advisories regularly.
