# Kiro Privacy and Security

> **Source:** https://kiro.dev/docs/privacy-and-security/ and its sub-pages: [Data protection](https://kiro.dev/docs/privacy-and-security/data-protection/) (updated 2026-09-30), [Firewalls, proxies, and data perimeters](https://kiro.dev/docs/privacy-and-security/firewalls/) (2026-10-01), [VPC endpoints](https://kiro.dev/docs/privacy-and-security/vpc-endpoints/) (2026-08-04), [Compliance validation](https://kiro.dev/docs/privacy-and-security/compliance-validation/) (2026-09-03), plus [Permissions](https://kiro.dev/docs/permissions/) (2026-10-01) and [Supported regions](https://kiro.dev/docs/enterprise/supported-regions/) (2026-08-04).
> **Last verified:** 2026-10-08.

## Data Storage

Kiro stores your questions, its responses and additional context to provide the service. Where content is stored depends on the user type:

- **Free Tier users and individual subscribers** (paid, social login or AWS Builder ID): content is stored in US East (N. Virginia) `us-east-1`. Subject to opt-out, it may be used for service improvement. Free Tier inputs may also be stored for up to 60 days for abuse detection.
- **Enterprise users:** content may be stored in the AWS Region where the Kiro profile is configured (for example for prompt logging and daily activity reports). It is not used for service improvement. Prompt logs and user activity reports, when enabled, are written to a customer-selected Amazon S3 bucket in the customer's account, in the profile Region.

**Kiro profile Regions:** US East (N. Virginia) `us-east-1`, Europe (Frankfurt) `eu-central-1`, AWS GovCloud (US-East) and AWS GovCloud (US-West). There is no Asia Pacific profile Region. IAM Identity Center can be in 19 Regions, including Asia Pacific (Singapore) `ap-southeast-1`; the Identity Center Region holds identities and subscriptions and can differ from the profile Region. Data storage and inference happen in the profile Region.

**Client telemetry (IDE 1.2+):** the IDE sends telemetry and activity data to the Kiro telemetry endpoint in the Region of the selected enterprise profile; if there is no endpoint in that Region, it drops the telemetry rather than sending it elsewhere.

## Cross-region Processing

Kiro is powered by Amazon Bedrock and uses cross-region inference to distribute traffic across AWS Regions. For Geography-scope models, which include all Claude models, traffic stays within the same geography; Global-scope models may be processed in AWS Regions worldwide (see [Inference scope per model](#inference-scope-per-model)). This does not change where data is stored.

| Geography | Inference Regions |
|-----------|-------------------|
| United States | us-east-1, us-west-2, us-east-2, AWS GovCloud (US-East), AWS GovCloud (US-West) |
| Europe | eu-central-1, eu-west-1, eu-west-3, eu-north-1, eu-south-1, eu-south-2 |

There is no APAC geography.

### Inference scope per model

Some Kiro models and capabilities use global cross-region inference. The Inference endpoint regions table on the [models page](https://kiro.dev/docs/models/) (updated 2026-10-08) gives each model an inference scope, and a capability that uses Global routing says so in its documentation:

| Scope | Where inference may run | Endpoint | Models (2026-10-08) |
|-------|-------------------------|----------|---------------------|
| Geography | Within the endpoint geography | US for US profiles; EU for Frankfurt (`eu-central-1`) profiles | Every model not marked Global, including all Claude models (Fable 5.1 Preview: US only), Auto, DeepSeek 3.2, MiniMax, GLM-5 and Qwen3 Coder Next |
| Global | Across supported commercial AWS Regions worldwide, including outside the endpoint geography | US for both US and Frankfurt profiles | GPT-5.6 Sol, Terra and Luna |

Cross-region inference, including global routing, does not change where Kiro stores data, and global routing does not apply to AWS GovCloud (US). Lifecycle status and inference scope are independent: Claude Opus 5.5 and Sonnet 5.5 launched with "experimental support" and have Geography scope.

There is no documented setting to disable cross-region inference. The available lever is **model governance** (Kiro console > Settings > Shared settings > model availability > Manage approved list): with a managed list, new models are not available until an administrator adds them, so Global-scope models can be kept out when processing must stay within one geography, and preview models can be held back until their terms (for example, Claude Fable 5.1's 30-day retention) are assessed.

### Abuse detection retention

- All users, all models: automated abuse detection through Amazon Bedrock.
- OpenAI GPT models: classifier-flagged traffic retained for up to 30 days.
- Anthropic Claude Fable 5.1 (Preview): **all** traffic retained for up to 30 days; classifier-flagged traffic may be reviewed by AWS personnel.
- Free Tier: inputs may additionally be stored for up to 60 days.

### Banking note (Singapore)

Identity can stay in Singapore (IAM Identity Center in `ap-southeast-1`), but prompts, code context and responses are stored and processed in the Kiro profile Region (`us-east-1` or `eu-central-1`) and may be processed in other Regions of the same geography (or, for Global-scope models such as GPT-5.6, in AWS Regions worldwide). Treat this as a cross-border transfer: apply the PDPA Transfer Limitation Obligation (section 26), assess Kiro under MAS TRM 3.4 and the outsourcing guidelines, keep customer information out of prompts, and use model governance to exclude Global-scope models (and review preview terms such as Claude Fable 5.1's 30-day retention). MAS TRM does not impose a data-localisation mandate; data location is an institution's own policy choice.

## Data Encryption

### Encryption in transit

All communication between customers and Kiro, and between Kiro and its downstream dependencies, uses TLS 1.2 or higher.

### Encryption at rest

- Kiro encrypts data with AWS owned keys from AWS KMS by default.
- Enterprise administrators can configure a customer managed key in Kiro console > Settings > Encryption key. Only symmetric keys are supported. Customer managed keys do not apply to Kiro Web.
- The documentation does not list exactly which features the customer managed key covers or its Region constraint; verify with AWS before relying on it in a control statement.

## Service Improvement

Kiro may use content from Free Tier users and individual subscribers (including paid users who sign in with GitHub, Google or AWS Builder ID) for service improvement: questions, other inputs, and generated responses and code.

**Enterprise users' content is NOT used for service improvement.** Users who access Kiro through an Amazon Q Developer Pro subscription in their AWS account are also excluded.

## Opt Out of Data Sharing

Enterprise users are automatically opted out of telemetry and content collection by AWS. Telemetry for user activity reports is controlled by the administrator in the Kiro console and cannot be changed by enterprise users.

Free Tier users and individual subscribers can opt out:

- **IDE:** Settings > User > Application > Telemetry and Content. Uncheck "Data Sharing and Prompt Logging: Usage Analytics And Performance Metrics" (telemetry) and "Data Sharing and Prompt Logging: Content Collection for Service Improvement" (content).
- **CLI:** open Preferences in Kiro CLI, then toggle off the Telemetry setting and the "Share Kiro content with AWS" setting.

Opting out does not affect storage of Free Tier inputs for abuse detection.

## Types of Telemetry Collected

- **Usage data:** Kiro version, operating system and anonymous machine ID.
- **Performance metrics:** request count, errors and latency for login, tab completion, code generation, steering, hooks, spec generation, tools and MCP.

## Agent Autonomy and Permissions (IDE 1.0+, CLI V3)

The IDE 0.x "Trusted Commands" and "Command Denylist" settings were replaced in IDE 1.0 by the capability-based permission system (`permissions.yaml`). Trusted command prefixes translate to `allow` rules and denylist entries to `deny` rules; `kiroAgent.trustedCommands` and `kiroAgent.commandDenylist` are no longer used. The Kiro CLI V3 engine uses the same model.

**Agent autonomy (IDE).** Settings > Agent > Agent Autonomy, settings key `kiroAgent.agentAutonomy`:

- **Autopilot:** the agent proceeds with allowed operations without prompting.
- **Supervised:** the agent prompts before any action.

The permission rules apply after the autonomy mode decides whether to proceed.

**Permission rules.** Each rule has a `capability` (`fs_read`, `fs_write`, `shell`, `web_fetch`, `web_search`, `mcp`, …), optional `match` and `exclude` globs, and an `effect` (`deny`, `ask`, `allow`). Rules come from the Kiro hardcoded scope, the administrator policy (`managed-settings.json`), the user file (`~/.kiro/settings/permissions.yaml`), the per-user workspace file (`~/.kiro/workspace-roots/<hash>/permissions.yaml`, outside the repository), agent profiles and the session. They are combined with deny-overrides: `deny > ask > allow`, regardless of scope. Headless runs treat `ask` as `deny`.

**Workspace trust.** Kiro treats a workspace as untrusted until the user trusts it. While untrusted it does not load the workspace's custom agents, steering, MCP configuration, skills or workflows, and it asks before every shell command and MCP tool call.

Details: [permissions-and-managed-settings.md](permissions-and-managed-settings.md). Deployable banking templates: [`../managed-settings/`](../managed-settings/).

## Best Practices

### Protecting your resources

The agent runs with the user's local permissions and may access:

- local files and repositories;
- environment variables;
- AWS credentials stored in the environment;
- configuration files with sensitive information.

### Recommendations

1. **Workspace isolation and trust**
   - Keep sensitive projects in separate workspaces.
   - Leave unknown or third-party repositories untrusted.
   - Deny reads of secrets with `fs_read` deny rules (admin policy or `permissions.yaml`); `.gitignore` alone does not stop the agent from reading a file.

2. **Use a clean environment**
   - Use a dedicated user account, VDI or container for Kiro.
   - Limit access to only the repositories and resources needed.

3. **Manage AWS credentials carefully**
   - Use temporary credentials with least-privilege permissions.
   - Use AWS named profiles to isolate access.
   - Remove AWS credentials when they are not needed for the task.

4. **Repository access control**
   - Review which repositories Kiro can access.
   - Use repository-specific access tokens when possible.
   - Audit access permissions regularly.

## Code References

Kiro learns from open-source projects. Code references include information about the source used to generate recommendations.

### View code reference log

1. Go to the Output tab in the status bar.
2. From the drop-down menu, choose "code-references".

### Turn code references on or off

1. Open Settings in Kiro.
2. Switch to the User sub-tab.
3. Choose Kiro.
4. Under Code References: Reference Tracker, check or uncheck the box.

### Enterprise opt-out

Administrators can opt out of code suggestions with references for all users in the Kiro console.

## Infrastructure Security

- Kiro is protected by AWS global network security.
- TLS 1.2 is required; TLS 1.3 is recommended.
- Cipher suites with perfect forward secrecy (PFS) are required.
- Requests must be signed with IAM credentials or temporary AWS STS credentials.

## VPC Endpoints (AWS PrivateLink)

Interface VPC endpoints give a private connection from a VPC to the Kiro API **in the Kiro profile Region only**.

### Service names

- `com.amazonaws.us-east-1.q`
- `com.amazonaws.us-east-1.codewhisperer` (us-east-1 only)
- `com.amazonaws.eu-central-1.q`
- `com.amazonaws.us-gov-west-1.q`
- `com.amazonaws.us-gov-east-1.q`

### Private DNS names served

`q.<region>.amazonaws.com`, `runtime.<region>.kiro.dev`, `management.<region>.kiro.dev` and `telemetry.<region>.kiro.dev`, where `<region>` is `us-east-1` or `eu-central-1` (GovCloud has no `kiro.dev` names).

### Notes for Singapore deployments

- `com.amazonaws.ap-southeast-1.q` and `com.amazonaws.ap-southeast-1.codewhisperer` do not exist. Kiro clients do not need an Amazon Bedrock endpoint.
- AWS cross-Region PrivateLink supports only selected services, not `q` or `codewhisperer`, so a Singapore VPC cannot create a Kiro interface endpoint directly.
- Options: (a) a "Kiro access VPC" in the profile Region with the endpoints, private DNS disabled, Route 53 private hosted zones for the names above associated with the Singapore VPC, connected by inter-Region VPC peering or Transit Gateway peering; or (b) place the VDI in the profile Region.
- Either way, sign-in, downloads and `app.kiro.dev` are public HTTPS, so an allowlisted egress path is still required (next section).

## Compliance Validation

- Kiro (IDE and CLI) is HIPAA eligible.
- Kiro is in scope of the AWS ISO/IEC 27001:2022 certification (since 2026-09-01).
- No SOC report or MTCS (Singapore) certification is listed for Kiro on the compliance page; check AWS Artifact and "AWS services in Scope by Compliance Program" for the current status.
- FedRAMP High and DoD IL-4/5 (2026-06-25) apply to AWS GovCloud (US) only.
- Related AWS resources: AWS Compliance Programs, Security Compliance & Governance guides, AWS Customer Compliance Guides, AWS Config, AWS Security Hub, Amazon GuardDuty, AWS Audit Manager.

## Firewall and Proxy Configuration

Allowlist the specific host names below. The documentation also lists broad wildcards (`*.kiro.dev`, `*.app.kiro.dev`, `*.kiro.aws.dev`, `*.amazonaws.com`, `*.shortbread.aws.dev`, `*.signin.aws`); prefer the specific names, because `*.amazonaws.com` is too broad for a bank (it allows any S3 bucket).

**Core**

- `app.kiro.dev`
- `assets.app.kiro.dev`

**Kiro IDE**

- `prod.us-east-1.auth.desktop.kiro.dev`
- `prod.us-east-1.telemetry.desktop.kiro.dev`
- `prod.download.desktop.kiro.dev`
- `q.us-east-1.amazonaws.com`, `q.eu-central-1.amazonaws.com` (legacy endpoints; must still be allowlisted)
- `runtime.us-east-1.kiro.dev`, `runtime.eu-central-1.kiro.dev`
- `management.us-east-1.kiro.dev`, `management.eu-central-1.kiro.dev`
- `telemetry.us-east-1.kiro.dev`, `telemetry.eu-central-1.kiro.dev`

**Kiro CLI** (the IDE list, plus)

- `cli.kiro.dev`
- `prod.download.cli.kiro.dev`
- `desktop-release.q.us-east-1.amazonaws.com`

**IAM Identity Center**

- `<region>.signin.aws`
- `<sso-region>.signin.aws.amazon.com`
- `<idc-directory-id-or-alias>.awsapps.com`
- `portal.sso.<sso-region>.amazonaws.com`
- `assets.sso-portal.<sso-region>.amazonaws.com`
- `oidc.<sso-region>.amazonaws.com`

**External identity provider (direct federation)**

- `login.microsoftonline.com` or `<your-org>.okta.com`

**Social sign-in** (block for enterprise use)

- `cognito-identity.us-east-1.amazonaws.com`

**Optional** (extensions, Powers and MCP)

- `open-vsx.org`, `openvsx.eclipsecontent.org`, `github.com`, `raw.githubusercontent.com`

Notes:

- Browser-based sign-in bypasses proxy settings.
- Do **not** block `prod.us-east-1.auth.desktop.kiro.dev` to stop Builder ID sign-in: it is used by every IDE sign-in. Restrict sign-in methods with the `signin_method` rule in `managed-settings.json` instead (IDE 1.2+ / CLI 2.25.0+, client-enforced, fails open if unreadable); see [`../managed-settings/`](../managed-settings/).
