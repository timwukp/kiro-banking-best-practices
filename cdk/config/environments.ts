/**
 * Environment configuration for Kiro Banking CDK stacks.
 * Customize these values for your organization.
 */

export interface KiroBankingConfig {
  readonly environment: string;
  readonly region: string;
  readonly vpcCidr: string;
  readonly tags: Record<string, string>;
  readonly kiroEndpoints: string[];
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
  kiroEndpoints: [
    'com.amazonaws.ap-southeast-1.q',
    'com.amazonaws.ap-southeast-1.codewhisperer',
    'com.amazonaws.ap-southeast-1.bedrock-runtime',
  ],
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
  kiroEndpoints: [
    'com.amazonaws.ap-southeast-1.q',
    'com.amazonaws.ap-southeast-1.codewhisperer',
    'com.amazonaws.ap-southeast-1.bedrock-runtime',
  ],
  workspaceBundleId: 'wsb-gm4b5tx0y', // PowerPro bundle - update with your actual bundle ID
  cloudTrailRetentionDays: 2555, // ~7 years for MAS compliance
  enableCdkNag: true,
};
