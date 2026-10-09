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
  /**
   * Days to keep CloudTrail log files in the audit-log bucket (also used for the
   * AWS Config history bucket when `createConfigRecorder` is true).
   */
  readonly cloudTrailRetentionDays: number;
  /**
   * Default S3 Object Lock retention, in days, for new objects in the audit-log
   * bucket. Uses GOVERNANCE mode: users with s3:BypassGovernanceRetention can
   * still shorten or remove the lock. COMPLIANCE mode cannot be shortened or
   * removed by anyone, including the root user, until it expires, so only switch
   * after legal review. Must not exceed `cloudTrailRetentionDays`.
   * @default 30
   */
  readonly auditLogObjectLockDays?: number;
  /**
   * Days to keep S3 server access logs of the audit-log bucket. They record who
   * read or changed the audit logs; raise this to `cloudTrailRetentionDays` if
   * your record-keeping policy requires access records for the same period.
   * @default 365
   */
  readonly accessLogRetentionDays?: number;
  /**
   * Create an AWS Config configuration recorder and delivery channel in this
   * account and region. Each account and region supports only one recorder, so
   * leave this false where AWS Control Tower, an organization-wide setup or
   * another stack already records; the Config rules then use that recorder.
   * @default false
   */
  readonly createConfigRecorder?: boolean;
  /**
   * When `createConfigRecorder` is true, also record the global IAM resource
   * types (users, groups, roles, customer managed policies). Record them in one
   * region only: set false for every other region you deploy this app to.
   * @default true
   */
  readonly configRecorderGlobalResources?: boolean;
  /**
   * Create the GuardDuty detector. A region supports one detector per account;
   * set false where GuardDuty is enabled by a delegated administrator. Findings
   * are still routed to the security topic either way.
   * @default true
   */
  readonly enableGuardDuty?: boolean;
  /**
   * Enable AWS Security Hub (one hub per account and region). Set false where
   * Security Hub is enabled centrally for the organization.
   * @default true
   */
  readonly enableSecurityHub?: boolean;
  /**
   * Create an account-level IAM Access Analyzer (external access). Each account
   * and region allows one account-level analyzer per type: set false where one
   * already exists or analyzers are managed centrally.
   * @default true
   */
  readonly enableAccessAnalyzer?: boolean;
  /**
   * AWS Backup schedule in UTC (AWS cron syntax).
   * @default DEFAULT_BACKUP_SCHEDULE_CRON (02:00 Singapore time)
   */
  readonly backupScheduleCron?: string;
  readonly enableCdkNag: boolean;
}

/** 18:00 UTC = 02:00 Singapore time (UTC+8, no daylight saving). */
export const DEFAULT_BACKUP_SCHEDULE_CRON = 'cron(0 18 * * ? *)';

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
  auditLogObjectLockDays: 30,
  accessLogRetentionDays: 365,
  // Account-level singletons: set to false (or true for the recorder) to match
  // what your landing zone already provides in this account and region.
  createConfigRecorder: false,
  enableGuardDuty: true,
  enableSecurityHub: true,
  enableAccessAnalyzer: true,
  backupScheduleCron: DEFAULT_BACKUP_SCHEDULE_CRON,
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
  auditLogObjectLockDays: 365,
  accessLogRetentionDays: 365,
  // Account-level singletons: set to false (or true for the recorder) to match
  // what your landing zone already provides in this account and region.
  createConfigRecorder: false,
  enableGuardDuty: true,
  enableSecurityHub: true,
  enableAccessAnalyzer: true,
  backupScheduleCron: DEFAULT_BACKUP_SCHEDULE_CRON,
  enableCdkNag: true,
};
