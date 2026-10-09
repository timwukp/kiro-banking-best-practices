import * as cdk from 'aws-cdk-lib';
import { Template, Match, Annotations } from 'aws-cdk-lib/assertions';
import { Aspects } from 'aws-cdk-lib';
import { AwsSolutionsChecks } from 'cdk-nag';
import { NetworkStack } from '../lib/stacks/network-stack';
import { EncryptionStack } from '../lib/stacks/encryption-stack';
import { MonitoringStack } from '../lib/stacks/monitoring-stack';
import { ComplianceStack } from '../lib/stacks/compliance-stack';
import { BackupStack } from '../lib/stacks/backup-stack';
import { devConfig, KiroBankingConfig } from '../config/environments';
import {
  KIRO_OPTIONAL_HOSTS,
  KIRO_SOCIAL_SIGNIN_HOSTS,
  kiroEgressDomains,
  kiroInterfaceEndpointServices,
} from '../config/kiro-endpoints';

const account = '123456789012';
const env = { region: 'ap-southeast-1', account };

const natConfig: KiroBankingConfig = {
  ...devConfig,
  egress: { mode: 'nat-dns-firewall', allowedDomains: ['updates.example.com'] },
};

/** Service names of all VPC endpoints in a template. */
function endpointServiceNames(template: Template): string[] {
  return Object.values(template.findResources('AWS::EC2::VPCEndpoint'))
    .map((r) => JSON.stringify(r.Properties.ServiceName));
}

/** Domains of the DNS Firewall domain list with the given name. */
function domainListDomains(template: Template, name: string): string[] {
  const lists = Object.values(template.findResources('AWS::Route53Resolver::FirewallDomainList', {
    Properties: { Name: name },
  }));
  expect(lists).toHaveLength(1);
  return lists[0].Properties.Domains as string[];
}

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

  test('creates AWS service VPC endpoints (no Kiro endpoints outside the Kiro profile region)', () => {
    // CloudWatch Logs + KMS + Identity Store + STS interface endpoints + S3 gateway = 5
    template.resourceCountIs('AWS::EC2::VPCEndpoint', 5);
    for (const service of ['logs', 'kms', 'identitystore', 'sts']) {
      template.hasResourceProperties('AWS::EC2::VPCEndpoint', {
        ServiceName: `com.amazonaws.ap-southeast-1.${service}`,
        VpcEndpointType: 'Interface',
        PrivateDnsEnabled: true,
      });
    }
    template.hasResourceProperties('AWS::EC2::VPCEndpoint', { VpcEndpointType: 'Gateway' });
  });

  test('does not reference non-existent ap-southeast-1 Kiro or Bedrock endpoints', () => {
    for (const name of endpointServiceNames(template)) {
      expect(name).not.toMatch(/ap-southeast-1\.(q|codewhisperer)"/);
      expect(name).not.toMatch(/bedrock/);
    }
  });

  test('explains with an info annotation why no Kiro endpoints are created', () => {
    Annotations.fromStack(stack).hasInfo('/TestNetwork', Match.stringLikeRegexp('No Kiro VPC interface endpoints are created'));
  });

  test('creates security groups', () => {
    template.resourceCountIs('AWS::EC2::SecurityGroup', 2);
  });

  // Template-level check only: see the NOTE on WorkspacesSG in network-stack.ts
  // about EC2's default egress rule.
  test('declares no 0.0.0.0/0 security group egress rules', () => {
    for (const type of ['AWS::EC2::SecurityGroup', 'AWS::EC2::SecurityGroupEgress']) {
      expect(JSON.stringify(template.findResources(type))).not.toContain('0.0.0.0/0');
    }
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

  test('all subnets are isolated: 4 subnets and no routes', () => {
    template.resourceCountIs('AWS::EC2::Subnet', 4);
    template.resourceCountIs('AWS::EC2::Route', 0);
  });

  test('no DNS Firewall resources in the default egress mode', () => {
    template.resourceCountIs('AWS::Route53Resolver::FirewallDomainList', 0);
    template.resourceCountIs('AWS::Route53Resolver::FirewallRuleGroup', 0);
    template.resourceCountIs('AWS::Route53Resolver::FirewallRuleGroupAssociation', 0);
  });
});

describe('NetworkStack in a Kiro profile region', () => {
  test('us-east-1 creates the .q and .codewhisperer Kiro endpoints', () => {
    const app = new cdk.App();
    const stack = new NetworkStack(app, 'TestNetworkUse1', {
      env: { account, region: 'us-east-1' },
      config: { ...devConfig, region: 'us-east-1', kiroProfileRegion: 'us-east-1' },
    });
    const template = Template.fromStack(stack);
    template.resourceCountIs('AWS::EC2::VPCEndpoint', 7);
    for (const serviceName of ['com.amazonaws.us-east-1.q', 'com.amazonaws.us-east-1.codewhisperer']) {
      template.hasResourceProperties('AWS::EC2::VPCEndpoint', {
        ServiceName: serviceName,
        PrivateDnsEnabled: true,
        SubnetIds: Match.anyValue(),
      });
    }
  });

  test('eu-central-1 creates only the .q Kiro endpoint', () => {
    const app = new cdk.App();
    const stack = new NetworkStack(app, 'TestNetworkEuc1', {
      env: { account, region: 'eu-central-1' },
      config: { ...devConfig, region: 'eu-central-1', kiroProfileRegion: 'eu-central-1' },
    });
    const template = Template.fromStack(stack);
    template.resourceCountIs('AWS::EC2::VPCEndpoint', 6);
    template.hasResourceProperties('AWS::EC2::VPCEndpoint', { ServiceName: 'com.amazonaws.eu-central-1.q' });
    for (const name of endpointServiceNames(template)) {
      expect(name).not.toMatch(/codewhisperer/);
    }
  });

  test('no Kiro endpoints when the workload region differs from kiroProfileRegion', () => {
    const app = new cdk.App();
    const stack = new NetworkStack(app, 'TestNetworkMismatch', {
      env: { account, region: 'us-east-1' },
      config: { ...devConfig, region: 'us-east-1', kiroProfileRegion: 'eu-central-1' },
    });
    Template.fromStack(stack).resourceCountIs('AWS::EC2::VPCEndpoint', 5);
  });

  test('kiroEndpoints can select a subset of the Kiro endpoints', () => {
    const app = new cdk.App();
    const stack = new NetworkStack(app, 'TestNetworkSubset', {
      env: { account, region: 'us-east-1' },
      config: { ...devConfig, region: 'us-east-1', kiroEndpoints: ['com.amazonaws.us-east-1.q'] },
    });
    const template = Template.fromStack(stack);
    template.resourceCountIs('AWS::EC2::VPCEndpoint', 6);
    template.hasResourceProperties('AWS::EC2::VPCEndpoint', { ServiceName: 'com.amazonaws.us-east-1.q' });
  });

  test('rejects Kiro endpoint names that do not exist in the workload region', () => {
    const app = new cdk.App();
    expect(() => new NetworkStack(app, 'TestNetworkBadEndpoints', {
      env,
      config: { ...devConfig, kiroEndpoints: ['com.amazonaws.ap-southeast-1.q'] },
    })).toThrow(/do not exist/);
  });
});

describe('NetworkStack egress mode nat-dns-firewall', () => {
  const app = new cdk.App();
  const stack = new NetworkStack(app, 'TestNetworkNat', { env, config: natConfig });
  const template = Template.fromStack(stack);

  test('creates one NAT gateway and an internet gateway', () => {
    template.resourceCountIs('AWS::EC2::NatGateway', 1);
    template.resourceCountIs('AWS::EC2::InternetGateway', 1);
  });

  test('only the Workspaces and Public subnets get default routes; Endpoints stay isolated', () => {
    template.resourceCountIs('AWS::EC2::Subnet', 6);
    // 2 Public subnets -> internet gateway, 2 Workspaces subnets -> NAT gateway
    template.resourceCountIs('AWS::EC2::Route', 4);
    template.allResourcesProperties('AWS::EC2::Route', { DestinationCidrBlock: '0.0.0.0/0' });
  });

  test('Workspaces and Endpoints CIDRs are unchanged; public subnets do not map public IPs', () => {
    for (const cidr of ['10.0.0.0/24', '10.0.1.0/24', '10.0.2.0/24', '10.0.3.0/24']) {
      template.hasResourceProperties('AWS::EC2::Subnet', { CidrBlock: cidr, MapPublicIpOnLaunch: false });
    }
    for (const cidr of ['10.0.4.0/28', '10.0.4.16/28']) {
      template.hasResourceProperties('AWS::EC2::Subnet', { CidrBlock: cidr, MapPublicIpOnLaunch: false });
    }
  });

  test('allowlist domain list contains the Kiro, IAM Identity Center, endpoint and extra hosts only', () => {
    const domains = domainListDomains(template, 'kiro-banking-egress-allow-dev');
    expect(domains).toEqual(expect.arrayContaining([
      'prod.us-east-1.auth.desktop.kiro.dev',
      'app.kiro.dev',
      'runtime.us-east-1.kiro.dev',
      'oidc.ap-southeast-1.amazonaws.com',
      'portal.sso.ap-southeast-1.amazonaws.com',
      'kms.ap-southeast-1.amazonaws.com',
      'updates.example.com',
    ]));
    expect(domains.some((d) => d.startsWith('*'))).toBe(false);
    for (const host of [...KIRO_OPTIONAL_HOSTS, ...KIRO_SOCIAL_SIGNIN_HOSTS]) {
      expect(domains).not.toContain(host);
    }
    expect(new Set(domains).size).toBe(domains.length);
  });

  test('rule group allows the allowlist first and blocks everything else with NODATA', () => {
    expect(domainListDomains(template, 'kiro-banking-egress-block-all-dev')).toEqual(['*']);
    template.hasResourceProperties('AWS::Route53Resolver::FirewallRuleGroup', {
      FirewallRules: [
        Match.objectLike({ Action: 'ALLOW', Priority: 100, FirewallDomainRedirectionAction: 'TRUST_REDIRECTION_DOMAIN' }),
        Match.objectLike({ Action: 'BLOCK', Priority: 200, BlockResponse: 'NODATA' }),
      ],
    });
  });

  test('rule group is associated with the VPC', () => {
    template.hasResourceProperties('AWS::Route53Resolver::FirewallRuleGroupAssociation', {
      VpcId: { Ref: Match.stringLikeRegexp('^KiroVpc') },
      FirewallRuleGroupId: Match.anyValue(),
      Priority: 101,
    });
  });

  test('WorkSpaces security group allows HTTPS egress to any IPv4 address only', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupName: 'kiro-workspaces-sg-dev',
      SecurityGroupEgress: [
        Match.objectLike({ CidrIp: '0.0.0.0/0', IpProtocol: 'tcp', FromPort: 443, ToPort: 443 }),
      ],
    });
  });

  test('rejects an invalid or allow-all extra domain', () => {
    for (const bad of ['*', 'https://example.com/path']) {
      const badApp = new cdk.App();
      expect(() => new NetworkStack(badApp, 'TestNetworkBadDomain', {
        env,
        config: { ...natConfig, egress: { mode: 'nat-dns-firewall', allowedDomains: [bad] } },
      })).toThrow(/invalid DNS Firewall domains/);
    }
  });
});

describe('Kiro endpoint and allowlist helpers', () => {
  test('kiroInterfaceEndpointServices returns endpoints only for Kiro profile regions', () => {
    expect(kiroInterfaceEndpointServices('ap-southeast-1')).toEqual([]);
    expect(kiroInterfaceEndpointServices('us-east-1')).toEqual([
      'com.amazonaws.us-east-1.q',
      'com.amazonaws.us-east-1.codewhisperer',
    ]);
    expect(kiroInterfaceEndpointServices('eu-central-1')).toEqual(['com.amazonaws.eu-central-1.q']);
  });

  test('kiroEgressDomains uses exact hostnames and derives IAM Identity Center hosts', () => {
    const domains = kiroEgressDomains({
      identityCenterRegion: 'ap-southeast-1',
      identityCenterPortalHost: 'd-1234567890.awsapps.com',
      externalIdpDomain: 'login.microsoftonline.com',
    });
    expect(domains).toEqual(expect.arrayContaining([
      'app.kiro.dev',
      'assets.app.kiro.dev',
      'q.us-east-1.amazonaws.com',
      'telemetry.eu-central-1.kiro.dev',
      'cli.kiro.dev',
      'ap-southeast-1.signin.aws',
      'ap-southeast-1.signin.aws.amazon.com',
      'assets.sso-portal.ap-southeast-1.amazonaws.com',
      'd-1234567890.awsapps.com',
      'login.microsoftonline.com',
    ]));
    expect(domains.some((d) => d.includes('*'))).toBe(false);
    expect(domains).not.toContain('github.com');
    expect(domains).not.toContain('cognito-identity.us-east-1.amazonaws.com');
  });

  test('kiroEgressDomains adds optional hosts only on request and validates input', () => {
    const withOptional = kiroEgressDomains({ identityCenterRegion: 'ap-southeast-1', includeOptionalHosts: true });
    expect(withOptional).toEqual(expect.arrayContaining([...KIRO_OPTIONAL_HOSTS]));
    const withoutCli = kiroEgressDomains({ identityCenterRegion: 'ap-southeast-1', includeCli: false });
    expect(withoutCli).not.toContain('cli.kiro.dev');
    expect(() => kiroEgressDomains({ identityCenterRegion: 'singapore' })).toThrow(/identityCenterRegion/);
    expect(() => kiroEgressDomains({
      identityCenterRegion: 'ap-southeast-1',
      identityCenterPortalHost: 'https://d-1234567890.awsapps.com/start',
    })).toThrow(/identityCenterPortalHost/);
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

  test('NetworkStack variants (nat-dns-firewall, Kiro profile region) pass CDK Nag AwsSolutionsChecks', () => {
    const app = new cdk.App();
    const natNet = new NetworkStack(app, 'NagNetNat', { env, config: natConfig });
    const use1Net = new NetworkStack(app, 'NagNetUse1', {
      env: { account, region: 'us-east-1' },
      config: { ...natConfig, region: 'us-east-1' },
    });

    Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
    app.synth();

    for (const stack of [natNet, use1Net]) {
      const errors = Annotations.fromStack(stack).findError('*', Match.stringLikeRegexp('AwsSolutions-.*'));
      expect(errors).toHaveLength(0);
      const warnings = Annotations.fromStack(stack).findWarning('*', Match.stringLikeRegexp('AwsSolutions-.*'));
      expect(warnings).toHaveLength(0);
    }
  });
});
