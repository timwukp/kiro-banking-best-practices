#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Aspects } from 'aws-cdk-lib';
import { AwsSolutionsChecks } from 'cdk-nag';

import { NetworkStack } from '../lib/stacks/network-stack';
import { EncryptionStack } from '../lib/stacks/encryption-stack';
import { MonitoringStack } from '../lib/stacks/monitoring-stack';
import { ComplianceStack } from '../lib/stacks/compliance-stack';
import { prodConfig, devConfig } from '../config/environments';

const app = new cdk.App();

// Select environment from context or default to dev
const envName = app.node.tryGetContext('env') || 'dev';
const config = envName === 'prod' ? prodConfig : devConfig;

const env: cdk.Environment = {
  region: config.region,
  account: process.env.CDK_DEFAULT_ACCOUNT,
};

// --- Encryption Stack (KMS keys - must be created first) ---
const encryptionStack = new EncryptionStack(app, `KiroBanking-Encryption-${config.environment}`, {
  env,
  config,
  description: 'KMS customer-managed keys for Kiro banking environment (MAS TRM Section 10)',
});

// --- Network Stack (VPC + PrivateLink) ---
const networkStack = new NetworkStack(app, `KiroBanking-Network-${config.environment}`, {
  env,
  config,
  description: 'VPC with PrivateLink endpoints for Kiro (MAS TRM Section 11.2)',
});

// --- Monitoring Stack (CloudTrail + CloudWatch) ---
const monitoringStack = new MonitoringStack(app, `KiroBanking-Monitoring-${config.environment}`, {
  env,
  config,
  kmsKey: encryptionStack.auditKey,
  description: 'CloudTrail audit logging and CloudWatch monitoring (MAS TRM Section 15)',
});
monitoringStack.addDependency(encryptionStack);

// --- Compliance Stack (AWS Config rules) ---
const complianceStack = new ComplianceStack(app, `KiroBanking-Compliance-${config.environment}`, {
  env,
  config,
  description: 'AWS Config rules for MAS TRM continuous compliance monitoring',
});

// Apply tags to all resources
for (const stack of [encryptionStack, networkStack, monitoringStack, complianceStack]) {
  for (const [key, value] of Object.entries(config.tags)) {
    cdk.Tags.of(stack).add(key, value);
  }
}

// Apply CDK Nag security checks
if (config.enableCdkNag) {
  Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
}

app.synth();
