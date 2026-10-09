/**
 * Environment configuration for Kiro Banking CDK stacks.
 * Customize these values for your organization.
 *
 * Two regions matter and they are usually different:
 * - Workload region (`region`, ap-southeast-1 by default): where this app deploys
 *   the VPC, WorkSpaces networking, CloudTrail, AWS Config and AWS Backup.
 * - Kiro profile region (`kiroProfileRegion`, us-east-1 or eu-central-1): where
 *   Kiro stores prompts, code context and responses and runs inference (content
 *   may be processed in other regions of the same geography, and Global-scope
 *   models such as GPT-5.6 may be processed in AWS Regions worldwide; see
 *   https://kiro.dev/docs/models/). Kiro has no Asia Pacific profile region.
 *   See config/kiro-endpoints.ts.
 */

import { KiroProfileRegion } from './kiro-endpoints';

/**
 * How the WorkSpaces subnets reach the public Kiro hosts (sign-in, downloads,
 * app.kiro.dev and, outside the profile region, the Kiro API itself).
 *
 * - `none` (default): no internet path in this VPC (no internet gateway, no NAT,
 *   isolated subnets). Provide egress centrally, e.g. a landing-zone egress /
 *   inspection VPC or an explicit proxy that enforces the Kiro allowlist.
 * - `nat-dns-firewall`: a self-contained option for experimentation or small
 *   estates. Adds public subnets, one NAT gateway, and a Route 53 Resolver DNS
 *   Firewall that only resolves the Kiro allowlist plus `allowedDomains`.
 */
export type EgressMode = 'none' | 'nat-dns-firewall';

export const EGRESS_MODES: readonly EgressMode[] = ['none', 'nat-dns-firewall'];

export interface EgressConfig {
  readonly mode: EgressMode;
  /**
   * Extra exact hostnames (an optional leading `*.` is accepted) to allow
   * through DNS Firewall in addition to the Kiro allowlist, e.g. OS patching or
   * package mirrors. Used only when `mode` is `nat-dns-firewall`.
   */
  readonly allowedDomains: string[];
}

export interface KiroBankingConfig {
  readonly environment: string;
  /** Workload region for all stacks in this app. */
  readonly region: string;
  readonly vpcCidr: string;
  readonly tags: Record<string, string>;
  /**
   * Optional subset of Kiro VPC interface endpoint service names to create.
   * Leave empty (recommended) to create all Kiro endpoints of the profile
   * region (see `kiroInterfaceEndpointServices`). Kiro endpoints are only
   * created when the workload region equals `kiroProfileRegion`; any entry that
   * does not exist in the workload region fails synthesis.
   */
  readonly kiroEndpoints: string[];
  /** Kiro profile region: where Kiro data is stored and processed. */
  readonly kiroProfileRegion: KiroProfileRegion;
  /** Region of the IAM Identity Center instance. @default 'ap-southeast-1' */
  readonly identityCenterRegion?: string;
  /** AWS access portal host for the egress allowlist, e.g. 'd-xxxxxxxxxx.awsapps.com'. */
  readonly identityCenterPortalHost?: string;
  /** External IdP sign-in host (Option B), e.g. 'login.microsoftonline.com' or '<your-org>.okta.com'. */
  readonly externalIdpDomain?: string;
  readonly egress: EgressConfig;
  readonly workspaceBundleId?: string;
  readonly cloudTrailRetentionDays: number;
  readonly enableCdkNag: boolean;
}

export const devConfig: KiroBankingConfig = {
  environment: 'dev',
  region: 'ap-southeast-1',
  vpcCidr: '10.0.0.0/16',
  tags: {
    Environment: 'Development',
    Project: 'kiro-banking',
    Compliance: 'MAS-TRM',
    ManagedBy: 'CDK',
  },
  // No Kiro endpoints exist in ap-southeast-1; see config/kiro-endpoints.ts.
  kiroEndpoints: [],
  kiroProfileRegion: 'us-east-1',
  identityCenterRegion: 'ap-southeast-1',
  egress: {
    mode: 'none',
    allowedDomains: [],
  },
  cloudTrailRetentionDays: 90,
  enableCdkNag: true,
};

export const prodConfig: KiroBankingConfig = {
  environment: 'prod',
  region: 'ap-southeast-1',
  vpcCidr: '10.1.0.0/16',
  tags: {
    Environment: 'Production',
    Project: 'kiro-banking',
    Compliance: 'MAS-TRM',
    ManagedBy: 'CDK',
  },
  // No Kiro endpoints exist in ap-southeast-1; see config/kiro-endpoints.ts.
  kiroEndpoints: [],
  kiroProfileRegion: 'us-east-1',
  identityCenterRegion: 'ap-southeast-1',
  egress: {
    mode: 'none',
    allowedDomains: [],
  },
  workspaceBundleId: 'wsb-gm4b5tx0y', // PowerPro bundle - update with your actual bundle ID
  cloudTrailRetentionDays: 2555, // ~7 years; set per your record-keeping obligations (commonly 5-7 years)
  enableCdkNag: true,
};
