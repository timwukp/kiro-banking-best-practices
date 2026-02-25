# Kiro Privacy and Security

## Data Storage

Kiro stores your questions, its responses, and additional context to generate new responses. Content storage location depends on your subscription type:

- **Free Tier/Individual subscribers**: Content stored in US East (N. Virginia) Region
- **Enterprise users**: Content stored in the AWS Region where your Kiro profile was created

## Cross-region Processing

Kiro uses Amazon Bedrock with cross-region inference to distribute traffic across AWS Regions for enhanced performance and reliability. This doesn't affect where your data is stored.

### Supported regions for cross-region inference

**United States:**
- US East (N. Virginia) (us-east-1)
- US West (Oregon) (us-west-2)
- US East (Ohio) (us-east-2)
- AWS GovCloud (US-East)
- AWS GovCloud (US-West)

**Europe:**
- Europe (Frankfurt) (eu-central-1)
- Europe (Ireland) (eu-west-1)
- Europe (Paris) (eu-west-3)
- Europe (Stockholm) (eu-north-1)
- Europe (Milan) (eu-south-1)
- Europe (Spain) (eu-south-2)

### Global cross-region inference for experimental features

For experimental models and capabilities, Kiro may use global cross-region inference across supported commercial AWS Regions worldwide to optimize performance.

## Data Encryption

### Encryption in transit
All communication uses TLS 1.2 or higher connections.

### Encryption at rest
- Kiro encrypts data using AWS owned encryption keys from AWS KMS
- Enterprise administrators can create customer managed keys for additional control
- Only symmetric keys are supported

## Service Improvement

### Content used for service improvement
Kiro may use content from Free Tier and individual subscribers for service improvement, including:
- Questions asked to Kiro
- Other inputs provided
- Responses and code generated

**Enterprise users' content is NOT used for service improvement.**

## Opt Out of Data Sharing

### IDE
1. Open Settings in Kiro
2. Switch to User sub-tab
3. Choose Application → Telemetry and Content
4. Uncheck boxes for telemetry and content collection

### CLI
1. Open Preferences in Kiro CLI
2. Toggle off Telemetry setting
3. Toggle off Share Kiro content with AWS setting

## Types of Telemetry Collected

- **Usage data**: Kiro version, OS, anonymous machine ID
- **Performance metrics**: Request count, errors, latency for features like login, tab completion, code generation, tools, MCP

## Autopilot vs Supervised Mode

### Autopilot mode (default)
- Kiro executes multiple steps autonomously
- Makes decisions based on requirements
- Can be toggled on/off anytime
- Can be interrupted to regain manual control

### Supervised mode
- Kiro suggests actions but waits for confirmation
- Asks clarifying questions when needed
- User reviews and approves each change
- Maintains full control over development process

## Trusted Commands

By default, Kiro requires approval before running commands. You can configure trusted commands:
- **Exact matching**: Commands must match exactly (e.g., `npm install`)
- **Wildcard matching**: Use `*` to trust variations (e.g., `npm *`)
- **Universal trust**: Use `*` alone to trust all commands (use with extreme caution)

## Best Practices

### Protecting your resources
When using GitHub or Google authentication, Kiro may access:
- Local files and repositories
- Environment variables
- AWS credentials stored in your environment
- Configuration files with sensitive information

### Recommendations
1. **Workspace Isolation**
   - Keep sensitive projects in separate workspaces
   - Use .gitignore to prevent access to sensitive files
   - Consider using workspace trust features

2. **Use a Clean Environment**
   - Create dedicated user account or container for Kiro
   - Limit access to only needed repositories and resources

3. **Manage AWS Credentials Carefully**
   - Use temporary credentials with appropriate permissions
   - Consider using AWS named profiles to isolate access
   - Remove AWS credentials when not needed for sensitive work

4. **Repository Access Control**
   - Review which repositories Kiro can access
   - Use repository-specific access tokens when possible
   - Regularly audit access permissions

## Code References

Kiro learns from open-source projects. Code references include information about the source used to generate recommendations.

### View code reference log
1. Go to Output tab in status bar
2. From drop-down menu, choose "code-references"

### Turn code references on/off
1. Open Settings in Kiro
2. Switch to User sub-tab
3. Choose Kiro
4. Under Code References: Reference Tracker, check/uncheck the box

### Enterprise opt-out
Administrators can opt out of code suggestions with references for all users in the Kiro console.

## Infrastructure Security

- Kiro is protected by AWS global network security
- Requires TLS 1.2 (recommends TLS 1.3)
- Cipher suites with perfect forward secrecy (PFS)
- Requests must be signed using IAM credentials or AWS STS temporary credentials

## VPC Endpoints (AWS PrivateLink)

You can establish private connection between your VPC and Kiro using interface VPC endpoints.

### Service names
- com.amazonaws.us-east-1.q
- com.amazonaws.eu-central-1.q
- com.amazonaws.us-east-1.codewhisperer

### Prerequisites
- AWS account with appropriate permissions
- VPC already created
- Familiarity with AWS services

## Compliance Validation

Kiro follows AWS compliance programs. Resources:
- AWS services in Scope by Compliance Program
- AWS Compliance Programs
- Security Compliance & Governance guides
- HIPAA Eligible Services Reference
- AWS Compliance Resources
- AWS Customer Compliance Guides
- AWS Config for resource evaluation
- AWS Security Hub for comprehensive security view
- Amazon GuardDuty for threat detection
- AWS Audit Manager for continuous auditing

## Firewall and Proxy Configuration

### URLs to allowlist

**Authentication:**
- *.kiro.dev
- <idc-directory-id-or-alias>.awsapps.com
- oidc.<sso-region>.amazonaws.com
- *.sso.<sso-region>.amazonaws.com
- *.sso-portal.<sso-region>.amazonaws.com
- *.aws.dev
- *.awsstatic.com
- *.console.aws.a2z.com
- *.sso.amazonaws.com

**Kiro & Language Processing:**
- https://aws-toolkit-language-servers.amazonaws.com/
- https://aws-language-servers.us-east-1.amazonaws.com/

**Telemetry:**
- https://client-telemetry.us-east-1.amazonaws.com
- https://cognito-identity.us-east-1.amazonaws.com
- https://prod.us-east-1.telemetry.desktop.kiro.dev
- https://prod.us-east-1.auth.desktop.kiro.dev
