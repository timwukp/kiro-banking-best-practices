import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { NetworkStack } from '../lib/stacks/network-stack';
import { EncryptionStack } from '../lib/stacks/encryption-stack';
import { MonitoringStack } from '../lib/stacks/monitoring-stack';
import { ComplianceStack } from '../lib/stacks/compliance-stack';
import { devConfig } from '../config/environments';

const env = { region: 'ap-southeast-1', account: '123456789012' };

describe('EncryptionStack', () => {
  const app = new cdk.App();
  const stack = new EncryptionStack(app, 'TestEncryption', { env, config: devConfig });
  const template = Template.fromStack(stack);

  test('creates 3 KMS keys', () => {
    template.resourceCountIs('AWS::KMS::Key', 3);
  });

  test('all KMS keys have rotation enabled', () => {
    template.allResourcesProperties('AWS::KMS::Key', {
      EnableKeyRotation: true,
    });
  });

  test('KMS keys have RETAIN removal policy', () => {
    template.allResources('AWS::KMS::Key', {
      DeletionPolicy: 'Retain',
      UpdateReplacePolicy: 'Retain',
    });
  });
});

describe('NetworkStack', () => {
  const app = new cdk.App();
  const stack = new NetworkStack(app, 'TestNetwork', { env, config: devConfig });
  const template = Template.fromStack(stack);

  test('creates a VPC', () => {
    template.resourceCountIs('AWS::EC2::VPC', 1);
  });

  test('VPC has correct CIDR', () => {
    template.hasResourceProperties('AWS::EC2::VPC', {
      CidrBlock: devConfig.vpcCidr,
    });
  });

  test('creates VPC interface endpoints for Kiro services', () => {
    // 3 Kiro endpoints + CloudWatch Logs + KMS + SSO + STS = 7
    template.resourceCountIs('AWS::EC2::VPCEndpoint', 8); // +1 S3 gateway
  });

  test('creates security groups', () => {
    template.resourceCountIs('AWS::EC2::SecurityGroup', 2);
  });

  test('creates VPC flow logs', () => {
    template.resourceCountIs('AWS::EC2::FlowLog', 1);
  });

  test('no NAT gateways (zero trust)', () => {
    template.resourceCountIs('AWS::EC2::NatGateway', 0);
  });

  test('no internet gateways (zero trust)', () => {
    template.resourceCountIs('AWS::EC2::InternetGateway', 0);
  });
});

describe('MonitoringStack', () => {
  const app = new cdk.App();
  const encStack = new EncryptionStack(app, 'TestEnc2', { env, config: devConfig });
  const stack = new MonitoringStack(app, 'TestMonitoring', {
    env,
    config: devConfig,
    kmsKey: encStack.auditKey,
  });
  const template = Template.fromStack(stack);

  test('creates CloudTrail trail', () => {
    template.resourceCountIs('AWS::CloudTrail::Trail', 1);
  });

  test('CloudTrail has log file validation', () => {
    template.hasResourceProperties('AWS::CloudTrail::Trail', {
      EnableLogFileValidation: true,
      IsMultiRegionTrail: true,
    });
  });

  test('creates S3 bucket for audit logs', () => {
    template.resourceCountIs('AWS::S3::Bucket', 2); // audit + access logs
  });

  test('S3 buckets block public access', () => {
    template.allResourcesProperties('AWS::S3::Bucket', {
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true,
      },
    });
  });

  test('creates CloudWatch alarms', () => {
    template.resourceCountIs('AWS::CloudWatch::Alarm', 4);
  });

  test('creates SNS topic for alerts', () => {
    template.resourceCountIs('AWS::SNS::Topic', 1);
  });
});

describe('ComplianceStack', () => {
  const app = new cdk.App();
  const stack = new ComplianceStack(app, 'TestCompliance', { env, config: devConfig });
  const template = Template.fromStack(stack);

  test('creates AWS Config rules', () => {
    template.resourceCountIs('AWS::Config::ConfigRule', 18);
  });
});
