# MCP Server Directory

## Featured MCP Servers

### Amazon Devices Builder Tools MCP
- **Description**: Context and tools to develop, test, and debug apps for Amazon devices
- **Requirements**: Node installed
- **Documentation**: https://developer.amazon.com/docs/vega/latest/mcp-server.html

### AWS Documentation
- **Description**: Access to AWS documentation, search capabilities, and content recommendations
- **Requirements**: UV Installed

### Azure
- **Description**: Interact with Azure services and resources
- **Requirements**: Node installed

### Chrome DevTools
- **Description**: Control and inspect live Chrome browser with DevTools
- **Requirements**: Node installed

### Context7
- **Description**: Up-to-date code documentation for any library or framework
- **Requirements**: Node installed

### Datadog
- **Description**: Interact with Datadog AI-Powered Observability and Security Platform

### Docker
- **Description**: Manage Docker containers and images
- **Requirements**: Node installed

### Dynatrace
- **Description**: Interact with Dynatrace Observability Platform
- **Requirements**: Node installed

### Filesystem
- **Description**: Secure file operations within allowed directories
- **Requirements**: Node installed

### GCP
- **Description**: Manage Google Cloud Platform resources
- **Requirements**: Node installed

### Git
- **Description**: Read, search, and manipulate Git repositories
- **Requirements**: UV Installed

### GitHub
- **Description**: Interact with GitHub repositories, issues, and pull requests

### Kubernetes
- **Description**: Interact with Kubernetes clusters
- **Requirements**: Node installed

### LLM.txt
- **Description**: Access to LLM.txt documentation and resources

### Memory
- **Description**: Knowledge graph-based persistent memory system for AI agents
- **Requirements**: Node installed

### MongoDB
- **Description**: Interact with MongoDB databases
- **Requirements**: Node installed

### New Relic
- **Description**: Monitor and analyze application performance

### Pinecone
- **Description**: Vector database for semantic search, RAG workflows, and AI applications
- **Requirements**: Node installed

### Playwright
- **Description**: Browser automation for web scraping, screenshots, and test code generation
- **Requirements**: Node installed

### PostgreSQL
- **Description**: Query and manage PostgreSQL databases
- **Requirements**: Node installed

### Sequential Thinking
- **Description**: Dynamic and reflective problem-solving through iterative thinking
- **Requirements**: Node installed

### Strands Agent
- **Description**: Access documentation about Strands Agents
- **Requirements**: UV Installed

### Web Search
- **Description**: Search the web using Brave Search API
- **Requirements**: Node installed

## Share Your MCP Server

### Install Link Schema

**URL Format:**
```
https://kiro.dev/launch/mcp/add?name=<server-name>&config=<url-encoded-config>
```

**Query Parameters:**
- `name` (String, Required): Display name for the MCP server
- `config` (String, Required): URL-encoded JSON configuration object

### Generate Install Link (JavaScript)

```javascript
function createKiroInstallLink(name, config) {
  const encodedName = encodeURIComponent(name);
  const encodedConfig = encodeURIComponent(JSON.stringify(config));
  return `https://kiro.dev/launch/mcp/add?name=${encodedName}&config=${encodedConfig}`;
}

// Example: Local server
const localServerLink = createKiroInstallLink('aws-docs', {
  command: 'uvx',
  args: ['awslabs.aws-documentation-mcp-server@latest'],
  env: { FASTMCP_LOG_LEVEL: 'ERROR' },
  disabled: false,
  autoApprove: []
});

// Example: Remote server
const remoteServerLink = createKiroInstallLink('aws-knowledge', {
  url: 'https://knowledge-mcp.global.api.aws',
  disabled: false,
  autoApprove: []
});
```

### Add Kiro Badge

**HTML:**
```html
<a href="https://kiro.dev/launch/mcp/add?name=my-server&config=%7B%22command%22%3A%22npx%22...%7D">
  <img src="https://kiro.dev/images/add-to-kiro.svg" alt="Add to Kiro" />
</a>
```

**Markdown:**
```markdown
[![Add to Kiro](https://kiro.dev/images/add-to-kiro.svg)](https://kiro.dev/launch/mcp/add?name=my-server&config=%7B%22command%22%3A%22npx%22...%7D)
```

## Discover More MCP Servers

### Official Resources
- **MCP Registry**: Browse official registry of community-contributed servers
- **Model Context Protocol Organization**: Reference implementations and official servers

### Package Registries
- **npm (Node.js)**: Search for `mcp-server` or `@modelcontextprotocol/server-*`
- **PyPI (Python)**: Search for `mcp-server` or packages with MCP in the name
