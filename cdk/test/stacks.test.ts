import * as cdk from 'aws-cdk-lib';
import { Template, Match, Annotations } from 'aws-cdk-lib/assertions';
import { Aspects } from 'aws-cdk-lib';
import { AwsSolutionsChecks } from 'cdk-nag';
import { NetworkStack } from '../lib/stacks/network-stack';
import { EncryptionStack } from '../lib/stacks/encryption-stack';
import { MonitoringStack } from '../lib/stacks/monitoring-stack';
import { ComplianceStack } from '../lib/stacks/compliance-stack';
import { BackupStack } from '../lib/stacks/backup-stack';
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

  test('CloudWatch alarms have alarm actions', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmActions: Match.anyValue(),
    });
  });

  test('creates GuardDuty detector', () => {
    template.hasResourceProperties('AWS::GuardDuty::Detector', {
      Enable: true,
    });
  });

  test('S3 audit bucket uses KMS encryption', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketEncryption: {
        ServerSideEncryptionConfiguration: Match.arrayWith([
          Match.objectLike({
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'aws:kms',
            },
          }),
        ]),
      },
    });
  });
});

describe('ComplianceStack', () => {
  const app = new cdk.App();
  const stack = new ComplianceStack(app, 'TestCompliance', { env, config: devConfig });
  const template = Template.fromStack(stack);

  test('creates AWS Config rules', () => {
    template.resourceCountIs('AWS::Config::ConfigRule', 19);
  });

  test('creates IAM Access Analyzer', () => {
    template.hasResourceProperties('AWS::AccessAnalyzer::Analyzer', {
      Type: 'ACCOUNT',
    });
  });

  test('enables SecurityHub', () => {
    template.resourceCountIs('AWS::SecurityHub::Hub', 1);
  });
});

describe('BackupStack', () => {
  const app = new cdk.App();
  const stack = new BackupStack(app, 'TestBackup', { env, config: devConfig });
  const template = Template.fromStack(stack);

  test('creates backup vault', () => {
    template.resourceCountIs('AWS::Backup::BackupVault', 1);
  });

  test('creates backup plan', () => {
    template.resourceCountIs('AWS::Backup::BackupPlan', 1);
  });

  test('backup plan has daily rule with 35-day retention', () => {
    template.hasResourceProperties('AWS::Backup::BackupPlan', {
      BackupPlan: {
        BackupPlanRule: Match.arrayWith([
          Match.objectLike({
            Lifecycle: {
              DeleteAfterDays: 35,
            },
          }),
        ]),
      },
    });
  });

  test('backup vault is KMS encrypted', () => {
    template.hasResourceProperties('AWS::Backup::BackupVault', {
      EncryptionKeyArn: Match.anyValue(),
    });
  });
});

describe('CDK Nag Compliance', () => {
  test('all stacks pass CDK Nag AwsSolutionsChecks', () => {
    const app = new cdk.App();
    const enc = new EncryptionStack(app, 'NagEnc', { env, config: devConfig });
    const mon = new MonitoringStack(app, 'NagMon', { env, config: devConfig, kmsKey: enc.auditKey });
    const comp = new ComplianceStack(app, 'NagComp', { env, config: devConfig });
    const backupStack = new BackupStack(app, 'NagBackup', { env, config: devConfig });
    const net = new NetworkStack(app, 'NagNet', { env, config: devConfig });

    Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

    // Synth triggers the aspects
    app.synth();

    // Check for error-level annotations
    for (const stack of [enc, mon, comp, backupStack, net]) {
      const errors = Annotations.fromStack(stack).findError('*', Match.stringLikeRegexp('AwsSolutions-.*'));
      expect(errors).toHaveLength(0);
    }
  });
});
