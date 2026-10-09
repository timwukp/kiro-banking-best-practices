/**
 * Kiro regions, VPC endpoint service names and the egress (firewall/proxy)
 * allowlist, taken from the official Kiro documentation (verified 2026-10-08):
 *
 * - Supported regions:  https://kiro.dev/docs/enterprise/supported-regions/
 * - VPC endpoints:      https://kiro.dev/docs/privacy-and-security/vpc-endpoints/
 * - Firewall allowlist: https://kiro.dev/docs/privacy-and-security/firewalls/
 *
 * Kiro adds and retires hostnames over time. Re-check these pages before each
 * release and update the lists below; do not replace them with broad wildcards.
 */

/**
 * Commercial Kiro profile regions. The Kiro profile region is where prompts,
 * code context and responses are stored and where inference runs (content may
 * be processed in other regions of the same geography, or in AWS Regions
 * worldwide for Global-scope models such as GPT-5.6; see
 * https://kiro.dev/docs/models/). There is no Asia Pacific profile region.
 *
 * AWS GovCloud (US) profile regions also exist, but this repository targets
 * the commercial `aws` partition only, so they are intentionally not listed.
 */
export const KIRO_PROFILE_REGIONS = ['us-east-1', 'eu-central-1'] as const;

export type KiroProfileRegion = (typeof KIRO_PROFILE_REGIONS)[number];

export const DEFAULT_KIRO_PROFILE_REGION: KiroProfileRegion = 'us-east-1';

/**
 * IAM Identity Center can run in many regions, including Asia Pacific
 * (Singapore). It holds identities and subscriptions and may differ from the
 * Kiro profile region.
 */
export const DEFAULT_IDENTITY_CENTER_REGION = 'ap-southeast-1';

export function isKiroProfileRegion(region: string): region is KiroProfileRegion {
  return (KIRO_PROFILE_REGIONS as readonly string[]).includes(region);
}

/**
 * VPC interface endpoint (AWS PrivateLink) service names for Kiro in `region`.
 *
 * Kiro endpoints exist only in the Kiro profile regions:
 * `com.amazonaws.<region>.q` in us-east-1 and eu-central-1, plus
 * `com.amazonaws.us-east-1.codewhisperer` in us-east-1 only. With private DNS
 * enabled, the `.q` endpoint serves `q.<region>.amazonaws.com`,
 * `runtime.<region>.kiro.dev`, `management.<region>.kiro.dev` and
 * `telemetry.<region>.kiro.dev`.
 *
 * Returns an empty list for every other region (for example ap-southeast-1):
 * `com.amazonaws.ap-southeast-1.q` and `.codewhisperer` do not exist, and
 * cross-Region PrivateLink does not support these services. Kiro clients do
 * not need an Amazon Bedrock endpoint.
 *
 * Source: https://kiro.dev/docs/privacy-and-security/vpc-endpoints/ (verified 2026-10-08)
 */
export function kiroInterfaceEndpointServices(region: string): string[] {
  if (!isKiroProfileRegion(region)) {
    return [];
  }
  const services = [`com.amazonaws.${region}.q`];
  if (region === 'us-east-1') {
    services.push('com.amazonaws.us-east-1.codewhisperer');
  }
  return services;
}

// ---------------------------------------------------------------------------
// Egress allowlist
// Source: https://kiro.dev/docs/privacy-and-security/firewalls/ (verified 2026-10-08)
//
// The page also lists broad wildcards (*.kiro.dev, *.app.kiro.dev,
// *.kiro.aws.dev, *.amazonaws.com, *.shortbread.aws.dev, *.signin.aws).
// They are deliberately NOT used here: `*.amazonaws.com` alone would allow
// traffic to any S3 bucket or AWS API endpoint, which defeats egress control
// for a regulated institution.
// ---------------------------------------------------------------------------

/** Core URLs used by all Kiro products (sign-in portal and its assets). */
export const KIRO_CORE_HOSTS: readonly string[] = [
  'app.kiro.dev',
  'assets.app.kiro.dev',
];

/**
 * Kiro IDE hosts. The official list includes the API hosts of both commercial
 * profile regions; keep both unless you have tested your client version
 * without the other region's hosts.
 */
export const KIRO_IDE_HOSTS: readonly string[] = [
  'prod.us-east-1.auth.desktop.kiro.dev',
  'prod.us-east-1.telemetry.desktop.kiro.dev',
  'prod.download.desktop.kiro.dev',
  // Legacy API hosts: "will be deprecated in a future release", but they must
  // still be allowlisted alongside the runtime/management/telemetry hosts.
  'q.us-east-1.amazonaws.com',
  'q.eu-central-1.amazonaws.com',
  'runtime.us-east-1.kiro.dev',
  'runtime.eu-central-1.kiro.dev',
  'management.us-east-1.kiro.dev',
  'management.eu-central-1.kiro.dev',
  'telemetry.us-east-1.kiro.dev',
  'telemetry.eu-central-1.kiro.dev',
];

/** Additional hosts for the Kiro CLI (on top of the IDE hosts). */
export const KIRO_CLI_HOSTS: readonly string[] = [
  'cli.kiro.dev',
  'prod.download.cli.kiro.dev',
  'desktop-release.q.us-east-1.amazonaws.com',
];

/**
 * Optional hosts for extensions (Open VSX) and Powers/MCP content (GitHub).
 * Excluded by default; enable only after your third-party software review.
 */
export const KIRO_OPTIONAL_HOSTS: readonly string[] = [
  'open-vsx.org',
  'openvsx.eclipsecontent.org',
  'github.com',
  'raw.githubusercontent.com',
];

/**
 * Social sign-in (Google/GitHub). Never included by `kiroEgressDomains()`:
 * enterprise users sign in through IAM Identity Center, so leaving this host
 * off the allowlist blocks social sign-in at the network layer. Restrict
 * sign-in methods on the client as well (managed settings `signin_method`).
 */
export const KIRO_SOCIAL_SIGNIN_HOSTS: readonly string[] = [
  'cognito-identity.us-east-1.amazonaws.com',
];

/**
 * IAM Identity Center sign-in hosts for the Identity Center region.
 * Browser-based sign-in bypasses the IDE proxy settings, so these hosts must be
 * reachable at the network level.
 *
 * @param identityCenterRegion region of the IAM Identity Center instance
 * @param portalHost AWS access portal host, e.g. `d-xxxxxxxxxx.awsapps.com`
 */
export function identityCenterHosts(identityCenterRegion: string, portalHost?: string): string[] {
  const hosts = [
    `${identityCenterRegion}.signin.aws`,
    `${identityCenterRegion}.signin.aws.amazon.com`,
    `portal.sso.${identityCenterRegion}.amazonaws.com`,
    `assets.sso-portal.${identityCenterRegion}.amazonaws.com`,
    `oidc.${identityCenterRegion}.amazonaws.com`,
  ];
  if (portalHost) {
    hosts.push(portalHost);
  }
  return hosts;
}

export interface KiroEgressDomainOptions {
  /** Region of the IAM Identity Center instance (for example ap-southeast-1). */
  readonly identityCenterRegion: string;
  /** AWS access portal host, e.g. `d-xxxxxxxxxx.awsapps.com`. Added when set. */
  readonly identityCenterPortalHost?: string;
  /**
   * External identity provider sign-in host, e.g. `login.microsoftonline.com`
   * (Microsoft Entra ID) or `<your-org>.okta.com`. Added when set.
   */
  readonly externalIdpDomain?: string;
  /** Include the Kiro CLI hosts. @default true */
  readonly includeCli?: boolean;
  /** Include the optional extension and Powers/MCP hosts. @default false */
  readonly includeOptionalHosts?: boolean;
}

/**
 * Builds the hostname allowlist that Kiro clients need, from the official
 * firewall page. Only exact hostnames are returned (no wildcards). The result
 * is lower-case, de-duplicated and in a stable order.
 *
 * Source: https://kiro.dev/docs/privacy-and-security/firewalls/ (verified 2026-10-08)
 */
export function kiroEgressDomains(opts: KiroEgressDomainOptions): string[] {
  const includeCli = opts.includeCli ?? true;
  const includeOptionalHosts = opts.includeOptionalHosts ?? false;

  if (!/^[a-z]{2}(-[a-z]+)+-\d+$/.test(opts.identityCenterRegion)) {
    throw new Error(`Invalid identityCenterRegion '${opts.identityCenterRegion}' (expected an AWS region such as ap-southeast-1)`);
  }
  for (const [field, host] of [
    ['identityCenterPortalHost', opts.identityCenterPortalHost],
    ['externalIdpDomain', opts.externalIdpDomain],
  ] as const) {
    if (host !== undefined && !isExactHostname(host)) {
      throw new Error(`Invalid ${field} '${host}' (expected a hostname without scheme, path or wildcard, e.g. d-xxxxxxxxxx.awsapps.com)`);
    }
  }

  const domains = [
    ...KIRO_CORE_HOSTS,
    ...KIRO_IDE_HOSTS,
    ...(includeCli ? KIRO_CLI_HOSTS : []),
    ...identityCenterHosts(opts.identityCenterRegion, opts.identityCenterPortalHost),
    ...(opts.externalIdpDomain ? [opts.externalIdpDomain] : []),
    ...(includeOptionalHosts ? KIRO_OPTIONAL_HOSTS : []),
  ];
  return uniqueLowerCase(domains);
}

/**
 * True when `domain` is a valid Route 53 Resolver DNS Firewall domain
 * specification: an optional leading `*.` followed by at least two labels of
 * letters, digits and hyphens, at most 255 characters.
 */
export function isValidDnsFirewallDomain(domain: string): boolean {
  return domain.length <= 255 && /^(\*\.)?([A-Za-z0-9-]+\.)+[A-Za-z0-9-]+$/.test(domain);
}

/** True for an exact hostname (no wildcard, scheme, port or path). */
export function isExactHostname(host: string): boolean {
  return !host.startsWith('*') && isValidDnsFirewallDomain(host);
}

/** Lower-cases and removes duplicates, keeping the first occurrence order. */
export function uniqueLowerCase(domains: readonly string[]): string[] {
  return [...new Set(domains.map((d) => d.toLowerCase()))];
}
