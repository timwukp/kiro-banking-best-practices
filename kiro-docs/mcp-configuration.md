# MCP Configuration Guide

> **Source:** https://kiro.dev/docs/mcp/configuration/ (updated 2026-10-07), with governance details from https://kiro.dev/docs/enterprise/governance/mcp/ (2026-08-04) and https://kiro.dev/docs/mcp/registry/ (2026-10-01).
> **Last verified:** 2026-10-08.

## Configuration File Structure

MCP configuration files use JSON format:

```json
{
  "mcpServers": {
    "local-server-name": {
      "command": "command-to-run-server",
      "args": ["arg1", "arg2"],
      "env": {
        "ENV_VAR1": "hard-coded-variable",
        "ENV_VAR2": "${EXPANDED_VARIABLE}"
      },
      "disabled": false,
      "autoApprove": ["tool_name1", "tool_name2"],
      "disabledTools": ["tool_name3"]
    },
    "remote-server-name": {
      "url": "https://endpoint.to.connect.to",
      "headers": {
        "HEADER1": "value1",
        "HEADER2": "value2"
      },
      "disabled": false,
      "autoApprove": ["tool_name1", "tool_name2"],
      "disabledTools": ["tool_name3"]
    }
  }
}
```

## Configuration Properties

### Local Server

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `command` | String | Yes | The command to run the MCP server |
| `args` | Array | No | Arguments to pass to the command |
| `env` | Object | No | Environment variables for the server process |
| `disabled` | Boolean | No | Whether the server is disabled (default: false) |
| `autoApprove` | Array | No | Tool names to auto-approve without prompting (`"*"` for all) |
| `disabledTools` | Array | No | Tool names to omit when calling the Agent |

### Remote Server

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `url` | String | Yes | HTTPS endpoint for the remote MCP server (HTTP only for localhost) |
| `headers` | Object | No | Headers to pass during connection |
| `env` | Object | No | Environment variables for the server process |
| `oauth` | Object | No | OAuth settings: `clientId`, `clientSecret` (CLI only; the IDE supports public PKCE clients only), `redirectUri` (http on `127.0.0.1` or `localhost`), `clientMetadataUrl`, `oauthScopes` |
| `oauthScopes` | Array | No | Fallback scopes; `oauth.oauthScopes` takes priority. Default: `openid`, `email`, `profile`, `offline_access` |
| `disabled` | Boolean | No | Whether the server is disabled (default: false) |
| `autoApprove` | Array | No | Tool names to auto-approve without prompting (`"*"` for all) |
| `disabledTools` | Array | No | Tool names to omit when calling the Agent |

**`autoApprove` naming.** The property name is `autoApprove` on both the configuration and the usage pages. The entry format differs: the configuration page says "tool names" (for example `search_documentation`), while the usage and security pages show prefixed names (`mcp_aws_docs_search_documentation` for server `aws-docs`). Check the name Kiro shows for the tool in the MCP panel before relying on an entry. For banking, prefer no `autoApprove` and use `mcp` permission rules instead (pattern `<server>/<tool>`, see [permissions-and-managed-settings.md](permissions-and-managed-settings.md)); in an untrusted workspace Kiro asks for every MCP tool call even when `autoApprove` lists it.

## Configuration Locations

1. **Workspace level:** `.kiro/settings/mcp.json`
   - Applies only to the current workspace.
   - Loaded only when the workspace is trusted.
2. **User level:** `~/.kiro/settings/mcp.json`
   - Applies globally across all workspaces.

If both exist, configurations are merged with workspace settings taking precedence. When the same server name is defined in several places, the priority is (highest first): agent config `mcpServers` > workspace `mcp.json` > user `mcp.json`. A higher-priority definition replaces the lower one completely; servers with different names are all used; `"disabled": true` at a higher level suppresses the server.

**Documented locations only.** `~/.kiro/settings/mcp.json` and `.kiro/settings/mcp.json` are the documented Kiro locations (Kiro Web loads local MCP servers from `.kiro/settings/mcp.json` in the repository). `C:\ProgramData\Kiro\mcp.json` is **not** a documented Kiro location; do not rely on a file placed there (the documented admin file in that folder is `managed-settings.json`). Centralized control of MCP is done with MCP governance and the MCP registry (below), not by deploying or symlinking `mcp.json` files.

**Docs conflict:** the MCP registry page refers to `~/.kiro/mcp.json` (global) and `.kiro/mcp.json` (workspace). This reference follows the configuration page (`~/.kiro/settings/mcp.json`, `.kiro/settings/mcp.json`); verify on your Kiro version.

**Agent write protection:** Kiro hardcodes a deny on agent writes to `~/.kiro/settings/` and `.kiro/settings/`, so the agent cannot add or change MCP servers in these files.

## Creating Configuration Files

### Using Command Palette

1. Open the command palette (Cmd+Shift+P on Mac, Ctrl+Shift+P on Windows/Linux).
2. Search for "MCP".
3. Select:
   - **Kiro: Open workspace MCP config (JSON)** for workspace level
   - **Kiro: Open user MCP config (JSON)** for user level

### Using Kiro Panel

1. Open the Kiro panel.
2. Select the **Open MCP Config** icon.

### Enabling MCP support

Open Settings (Cmd+, or Ctrl+,), search for "MCP" and enable the MCP support setting. Organization governance can still turn MCP off (below).

## Environment Variables

Example configuration with environment variables:

```json
{
  "mcpServers": {
    "server-name": {
      "env": {
        "API_KEY": "${YOUR_API_KEY}",
        "DEBUG": "true",
        "TIMEOUT": "30000"
      }
    }
  }
}
```

Kiro only expands environment variables that are explicitly approved (setting "Mcp Approved Env Vars"); unapproved variables trigger a security warning.

## Disabling Servers Temporarily

```json
{
  "mcpServers": {
    "server-name": {
      "disabled": true
    }
  }
}
```

## MCP Governance and Registry (Enterprise)

Administrators control MCP in Kiro console > Settings > Shared settings. The settings are part of the Kiro profile (organization level, overridable per account).

- **MCP on/off toggle.** When off, the client suppresses all MCP servers (user-configured, legacy, registry and session-injected) and `/mcp` shows "MCP has been disabled by your administrator".
- **MCP Registry URL.** An HTTPS URL to a JSON allow list. Only servers in the registry can run; servers not in the registry are hidden and never started, including entries in the user's own `mcp.json` (the IDE shows "N servers hidden"). A local entry whose name matches a registry server is still used to supply overrides.
- **Registry file format:** a subset of the MCP registry standard v0.1 server schema: `servers[].server` with `name`, optional `title`, `description`, `version`, and either one `remotes` entry (`streamable-http` or `sse`, optional `headers`) or one `packages` entry (`registryType` `npm` | `pypi` | `oci`, run with `npx` | `uvx` | `docker`; `identifier`; `transport: {"type": "stdio"}`; optional `runtimeArguments`, `packageArguments`, `environmentVariables`). Example: [`../managed-settings/mcp-registry.example.json`](../managed-settings/mcp-registry.example.json).
- **Pinned versions.** `version` must be exact; ranges (`^1.2.3`, `~1.2.3`, `>=1.2.3`, `1.x`, `1.*`) are rejected. If a locally installed server has a different version, Kiro relaunches it with the registry version.
- **Refresh.** Kiro fetches the registry at startup and every 24 hours. A server removed from the registry is terminated and cannot be added back.
- **Hosting.** HTTPS with a certificate signed by a trusted CA (self-signed certificates are not supported). The URL can be private to the corporate network. The client machines need the package runners installed.
- **User overrides.** Registry parameters are read-only, but users can add environment variables (local servers), HTTP headers (remote servers), a timeout, the scope (global, workspace or agent) and tool trust. Overrides use a `"type": "registry"` entry; `env` and `headers` merge per key.
- **Fails closed.** If the client cannot reach the governance API, MCP is disabled and `/mcp` shows "Failed to retrieve MCP settings — MCP disabled" until it reconnects.
- **Scope.** Applies to users who authenticate with IAM Identity Center or API keys, in the IDE and CLI. It does not apply to Builder ID or social sign-in users, or to Kiro Web. (The user-facing registry page phrases this as "Pro-tier customers using IAM Identity Center".)
- **Client-side enforcement.** "As with any client-enforced configuration, they can be circumvented by users, e.g., via administrative access to their local machine."

## Security Considerations

- Use environment variable references (e.g., `${API_TOKEN}`) instead of hardcoding.
- Never commit configuration files with credentials to version control.
- Only connect to trusted remote servers; in an enterprise, list them in the MCP registry.
- Review tool permissions before adding to `autoApprove`.
- Use `disabledTools` to restrict access to dangerous operations.
- Leave unknown repositories untrusted: Kiro does not load their workspace MCP configuration until the workspace is trusted.

## Troubleshooting

1. **Validate JSON syntax:** check for missing commas, quotes or brackets.
2. **Verify command paths:** ensure the command exists in your PATH.
3. **Check environment variables:** verify all required variables are set and approved.
4. **Save configuration changes:** changes hot-reload when you save; only the changed servers restart.
5. **Server not visible with a registry active:** the server is not in the registry (or the name does not match); ask the administrator to add it.
