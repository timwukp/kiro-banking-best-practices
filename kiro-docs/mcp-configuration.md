# MCP Configuration Guide

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

### Remote Server

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `url` | String | Yes | HTTPS endpoint for the remote MCP server |
| `headers` | Object | No | Headers to pass during connection |
| `env` | Object | No | Environment variables for the server process |
| `disabled` | Boolean | No | Whether the server is disabled (default: false) |
| `autoApprove` | Array | No | Tool names to auto-approve ("*" for all) |
| `disabledTools` | Array | No | Tool names to omit when calling the Agent |

### Local Server

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `command` | String | Yes | The command to run the MCP server |
| `args` | Array | Yes | Arguments to pass to the command |
| `env` | Object | No | Environment variables for the server process |
| `disabled` | Boolean | No | Whether the server is disabled (default: false) |
| `autoApprove` | Array | No | Tool names to auto-approve ("*" for all) |
| `disabledTools` | Array | No | Tool names to omit when calling the Agent |

## Configuration Locations

1. **Workspace Level**: `.kiro/settings/mcp.json`
   - Applies only to current workspace
   - Ideal for project-specific MCP servers

2. **User Level**: `~/.kiro/settings/mcp.json`
   - Applies globally across all workspaces
   - Best for frequently used MCP servers

If both exist, configurations are merged with workspace settings taking precedence.

## Creating Configuration Files

### Using Command Palette
1. Open command palette (Cmd+Shift+P on Mac, Ctrl+Shift+P on Windows/Linux)
2. Search for "MCP"
3. Select:
   - **Kiro: Open workspace MCP config (JSON)** - For workspace-level
   - **Kiro: Open user MCP config (JSON)** - For user-level

### Using Kiro Panel
1. Open the Kiro panel
2. Select the **Open MCP Config** icon

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

## Security Considerations

- Use environment variable references (e.g., `${API_TOKEN}`) instead of hardcoding
- Never commit configuration files with credentials to version control
- Only connect to trusted remote servers
- Review tool permissions before adding to `autoApprove`

## Troubleshooting

1. **Validate JSON syntax**: Check for missing commas, quotes, or brackets
2. **Verify command paths**: Ensure command exists in your PATH
3. **Check environment variables**: Verify all required variables are set
4. **Save configuration changes**: Changes apply automatically when you save the file
