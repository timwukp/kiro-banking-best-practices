#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Aspects } from 'aws-cdk-lib';
import { AwsSolutionsChecks } from 'cdk-nag';

import { NetworkStack } from '../lib/stacks/network-stack';
import { EncryptionStack } from '../lib/stacks/encryption-stack';
import { MonitoringStack } from '../lib/stacks/monitoring-stack';
import { ComplianceStack } from '../lib/stacks/compliance-stack';
import { BackupStack } from '../lib/stacks/backup-stack';
import { prodConfig, devConfig, EGRESS_MODES, EgressMode, KiroBankingConfig } from '../config/environments';

const app = new cdk.App();

// Select environment from context or default to dev
const envName = app.node.tryGetContext('env') || 'dev';
let config: KiroBankingConfig = envName === 'prod' ? prodConfig : devConfig;

// Optional overrides for experimentation (defaults come from config/environments.ts):
//   -c region=<aws-region>       workload region for all stacks (e.g. us-east-1 to
//                                create the Kiro endpoints in the Kiro profile region)
//   -c egress=nat-dns-firewall   egress mode (none | nat-dns-firewall)
const regionOverride = app.node.tryGetContext('region');
if (regionOverride !== undefined) {
  if (typeof regionOverride !== 'string' || !/^[a-z]{2}(-[a-z]+)+-\d+$/.test(regionOverride)) {
    throw new Error(`Invalid -c region=${String(regionOverride)} (expected an AWS region such as ap-southeast-1)`);
  }
  config = { ...config, region: regionOverride };
}

const egressOverride = app.node.tryGetContext('egress');
if (egressOverride !== undefined) {
  if (!(EGRESS_MODES as readonly unknown[]).includes(egressOverride)) {
    throw new Error(`Invalid -c egress=${String(egressOverride)} (expected one of: ${EGRESS_MODES.join(', ')})`);
  }
  config = { ...config, egress: { ...config.egress, mode: egressOverride as EgressMode } };
}

const env: cdk.Environment = {
  region: config.region,
  account: process.env.CDK_DEFAULT_ACCOUNT,
};

// --- Encryption Stack (KMS keys - must be created first) ---
const encryptionStack = new EncryptionStack(app, `KiroBanking-Encryption-${config.environment}`, {
  env,
  config,
  description: 'KMS customer-managed keys for Kiro banking environment (MAS TRM 10.2 Cryptographic Key Management)',
});

// --- Network Stack (VPC, VPC endpoints, optional filtered egress) ---
const networkStack = new NetworkStack(app, `KiroBanking-Network-${config.environment}`, {
  env,
  config,
  description: 'VPC with VPC endpoints and optional filtered egress for Kiro (MAS TRM Section 11.2)',
});

// --- Monitoring Stack (CloudTrail + CloudWatch) ---
const monitoringStack = new MonitoringStack(app, `KiroBanking-Monitoring-${config.environment}`, {
  env,
  config,
  kmsKey: encryptionStack.auditKey,
  description: 'CloudTrail audit logging and CloudWatch monitoring (MAS TRM 12.2 Cyber Event Monitoring and Detection)',
});
monitoringStack.addDependency(encryptionStack);

// --- Compliance Stack (AWS Config rules) ---
const complianceStack = new ComplianceStack(app, `KiroBanking-Compliance-${config.environment}`, {
  env,
  config,
  description: 'AWS Config rules for MAS TRM continuous compliance monitoring',
});

// --- Backup Stack (AWS Backup for system backup and recovery) ---
const backupStack = new BackupStack(app, `KiroBanking-Backup-${config.environment}`, {
  env,
  config,
  description: 'AWS Backup vault and plan for system backup and recovery (MAS TRM Section 8 IT Resilience, 8.4)',
});

// Apply tags to all resources
for (const stack of [encryptionStack, networkStack, monitoringStack, complianceStack, backupStack]) {
  for (const [key, value] of Object.entries(config.tags)) {
    cdk.Tags.of(stack).add(key, value);
  }
}

// Apply CDK Nag security checks
if (config.enableCdkNag) {
  Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
}

app.synth();
