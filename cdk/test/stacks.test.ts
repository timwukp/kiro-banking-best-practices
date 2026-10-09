import * as cdk from 'aws-cdk-lib';
import { Template, Match, Annotations } from 'aws-cdk-lib/assertions';
import { Aspects } from 'aws-cdk-lib';
import { AwsSolutionsChecks } from 'cdk-nag';
import { NetworkStack } from '../lib/stacks/network-stack';
import { EncryptionStack } from '../lib/stacks/encryption-stack';
import { MonitoringStack, transitionsBeforeExpiration } from '../lib/stacks/monitoring-stack';
import { ComplianceStack } from '../lib/stacks/compliance-stack';
import { BackupStack } from '../lib/stacks/backup-stack';
import { devConfig, prodConfig, KiroBankingConfig } from '../config/environments';
import {
  KIRO_OPTIONAL_HOSTS,
  KIRO_SOCIAL_SIGNIN_HOSTS,
  kiroEgressDomains,
  kiroInterfaceEndpointServices,
} from '../config/kiro-endpoints';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as fs from 'fs';
import * as path from 'path';

// Use the feature flags from cdk.json so that the templates under test match `cdk synth`.
const cdkJsonContext = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'cdk.json'), 'utf8')).context;

function newApp(): cdk.App {
  return new cdk.App({ context: cdkJsonContext });
}

const account = '123456789012';
const env = { region: 'ap-southeast-1', account };

const natConfig: KiroBankingConfig = {
  ...devConfig,
  egress: { mode: 'nat-dns-firewall', allowedDomains: ['updates.example.com'] },
};

/** An ARN as CDK renders it: arn:<AWS::Partition><rest>. */
function partitionArn(rest: string): Record<string, unknown> {
  return { 'Fn::Join': ['', ['arn:', { Ref: 'AWS::Partition' }, rest]] };
}

/** Logical ID of the only resource of `type` whose properties match `props`. */
function logicalIdOf(template: Template, type: string, props: Record<string, unknown> = {}): string {
  const ids = Object.keys(template.findResources(type, { Properties: props }));
  expect(ids).toHaveLength(1);
  return ids[0];
}

/** Key policy statements of the KMS key whose logical ID starts with `prefix`. */
function keyPolicyStatements(template: Template, prefix: string): Record<string, unknown>[] {
  const keys = Object.entries(template.findResources('AWS::KMS::Key')).filter(([id]) => id.startsWith(prefix));
  expect(keys).toHaveLength(1);
  return keys[0][1].Properties.KeyPolicy.Statement;
}

/** Fails if CDK Nag reported any AwsSolutions error or warning on these stacks. */
function expectNoNagFindings(stacks: cdk.Stack[]): void {
  for (const stack of stacks) {
    const annotations = Annotations.fromStack(stack);
    expect(annotations.findError('*', Match.stringLikeRegexp('AwsSolutions-.*'))).toHaveLength(0);
    expect(annotations.findWarning('*', Match.stringLikeRegexp('AwsSolutions-.*'))).toHaveLength(0);
  }
}

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
  const app = newApp();
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

  test('AuditKey lets CloudWatch alarms use the encrypted SNS topic, only for this account', () => {
    expect(keyPolicyStatements(template, 'AuditKey')).toContainEqual({
      Sid: 'AllowCloudWatchAlarmsToEncryptedSns',
      Effect: 'Allow',
      Principal: { Service: 'cloudwatch.amazonaws.com' },
      Action: ['kms:Decrypt', 'kms:GenerateDataKey*'],
      Resource: '*',
      Condition: { StringEquals: { 'aws:SourceAccount': account } },
    });
  });

  test('AuditKey CloudTrail statements are scoped to this trail and to trails of this account', () => {
    const trailArn = partitionArn(`:cloudtrail:ap-southeast-1:${account}:trail/kiro-banking-audit-dev`);
    const statements = keyPolicyStatements(template, 'AuditKey');
    expect(statements).toContainEqual({
      Sid: 'AllowCloudTrailEncrypt',
      Effect: 'Allow',
      Principal: { Service: 'cloudtrail.amazonaws.com' },
      Action: 'kms:GenerateDataKey*',
      Resource: '*',
      Condition: {
        StringEquals: { 'aws:SourceArn': trailArn },
        StringLike: { 'kms:EncryptionContext:aws:cloudtrail:arn': partitionArn(`:cloudtrail:*:${account}:trail/*`) },
      },
    });
    expect(statements).toContainEqual({
      Sid: 'AllowCloudTrailDescribeKey',
      Effect: 'Allow',
      Principal: { Service: 'cloudtrail.amazonaws.com' },
      Action: 'kms:DescribeKey',
      Resource: '*',
      Condition: { StringEquals: { 'aws:SourceArn': trailArn } },
    });
    // The old region-wide wildcard (any account's trails) is gone.
    expect(JSON.stringify(statements)).not.toContain('arn:aws:cloudtrail:ap-southeast-1:*');
  });

  test('AuditKey CloudWatch Logs statement is limited to log groups of this account and region', () => {
    expect(keyPolicyStatements(template, 'AuditKey')).toContainEqual({
      Sid: 'AllowCloudWatchLogs',
      Effect: 'Allow',
      Principal: { Service: 'logs.ap-southeast-1.amazonaws.com' },
      Action: ['kms:Decrypt*', 'kms:Describe*', 'kms:Encrypt*', 'kms:GenerateDataKey*', 'kms:ReEncrypt*'],
      Resource: '*',
      Condition: {
        ArnLike: { 'kms:EncryptionContext:aws:logs:arn': partitionArn(`:logs:ap-southeast-1:${account}:log-group:*`) },
      },
    });
  });

  test('WorkspacesKey service statement is limited to this account', () => {
    expect(keyPolicyStatements(template, 'WorkspacesKey')).toContainEqual({
      Sid: 'AllowWorkSpacesEncrypt',
      Effect: 'Allow',
      Principal: { Service: 'workspaces.amazonaws.com' },
      Action: ['kms:CreateGrant', 'kms:Decrypt', 'kms:DescribeKey', 'kms:Encrypt', 'kms:GenerateDataKey*', 'kms:ReEncrypt*'],
      Resource: '*',
      Condition: { StringEquals: { 'aws:SourceAccount': account } },
    });
  });

  test('every service-principal statement has a condition', () => {
    for (const prefix of ['AuditKey', 'DataKey', 'WorkspacesKey']) {
      for (const statement of keyPolicyStatements(template, prefix)) {
        if ((statement.Principal as Record<string, unknown>).Service !== undefined) {
          expect(statement.Condition).toBeDefined();
        }
      }
    }
  });
});

describe('NetworkStack', () => {
  const app = newApp();
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

  test('declares no 0.0.0.0/0 security group egress rules', () => {
    for (const type of ['AWS::EC2::SecurityGroup', 'AWS::EC2::SecurityGroupEgress']) {
      expect(JSON.stringify(template.findResources(type))).not.toContain('0.0.0.0/0');
    }
  });

  test('WorkSpaces security group removes EC2 default allow-all egress: inline no-traffic rule plus HTTPS to endpoints', () => {
    // An inline egress rule makes EC2 drop its default allow-all rule; this one matches no traffic.
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupName: 'kiro-workspaces-sg-dev',
      GroupDescription: 'Security group for WorkSpaces - outbound to VPC endpoints only',
      SecurityGroupEgress: [
        { CidrIp: '255.255.255.255/32', Description: 'Disallow all traffic', IpProtocol: 'icmp', FromPort: 252, ToPort: 86 },
      ],
    });
    const workspacesSg = logicalIdOf(template, 'AWS::EC2::SecurityGroup', { GroupName: 'kiro-workspaces-sg-dev' });
    const endpointSg = logicalIdOf(template, 'AWS::EC2::SecurityGroup', { GroupName: 'kiro-vpc-endpoint-sg-dev' });
    template.resourceCountIs('AWS::EC2::SecurityGroupEgress', 1);
    template.hasResourceProperties('AWS::EC2::SecurityGroupEgress', {
      GroupId: { 'Fn::GetAtt': [workspacesSg, 'GroupId'] },
      DestinationSecurityGroupId: { 'Fn::GetAtt': [endpointSg, 'GroupId'] },
      IpProtocol: 'tcp',
      FromPort: 443,
      ToPort: 443,
    });
  });

  test('Endpoints NACL is associated with both Endpoints subnets (and no others)', () => {
    const nacl = logicalIdOf(template, 'AWS::EC2::NetworkAcl');
    const subnetCidrs = Object.fromEntries(Object.entries(template.findResources('AWS::EC2::Subnet'))
      .map(([id, r]) => [id, r.Properties.CidrBlock as string]));
    const associations = Object.values(template.findResources('AWS::EC2::SubnetNetworkAclAssociation'));
    expect(associations).toHaveLength(2);
    for (const association of associations) {
      expect(association.Properties.NetworkAclId).toEqual({ Ref: nacl });
    }
    const associatedCidrs = associations.map((a) => subnetCidrs[a.Properties.SubnetId.Ref]).sort();
    expect(associatedCidrs).toEqual(['10.0.2.0/24', '10.0.3.0/24']);
  });

  test('Endpoints NACL allows only HTTPS and ephemeral return traffic within the VPC CIDR', () => {
    const nacl = logicalIdOf(template, 'AWS::EC2::NetworkAcl');
    template.resourceCountIs('AWS::EC2::NetworkAclEntry', 4);
    for (const egress of [false, true]) {
      for (const [ruleNumber, from, to] of [[100, 443, 443], [110, 1024, 65535]]) {
        template.hasResourceProperties('AWS::EC2::NetworkAclEntry', {
          NetworkAclId: { Ref: nacl },
          CidrBlock: devConfig.vpcCidr,
          Egress: egress,
          Protocol: 6,
          PortRange: { From: from, To: to },
          RuleAction: 'allow',
          RuleNumber: ruleNumber,
        });
      }
    }
  });

  test('creates VPC flow logs', () => {
    template.resourceCountIs('AWS::EC2::FlowLog', 1);
  });

  test('flow-log group is encrypted with a dedicated rotating KMS key and keeps its retention and generated name', () => {
    const flowLogKey = logicalIdOf(template, 'AWS::KMS::Key');
    expect(flowLogKey).toMatch(/^FlowLogKey/);
    template.hasResource('AWS::KMS::Key', {
      Properties: { EnableKeyRotation: true, PendingWindowInDays: 30 },
      DeletionPolicy: 'Retain',
      UpdateReplacePolicy: 'Retain',
    });
    template.hasResourceProperties('AWS::KMS::Alias', { AliasName: 'alias/kiro-banking-flow-logs-dev' });

    const logGroups = template.findResources('AWS::Logs::LogGroup');
    expect(Object.keys(logGroups)).toHaveLength(1);
    const [logGroupId, logGroup] = Object.entries(logGroups)[0];
    expect(logGroupId).toMatch(/^KiroVpcVpcFlowLogsLogGroup/);
    expect(logGroup.Properties.KmsKeyId).toEqual({ 'Fn::GetAtt': [flowLogKey, 'Arn'] });
    expect(logGroup.Properties.RetentionInDays).toBe(731);
    expect(logGroup.Properties.LogGroupName).toBeUndefined();

    // CloudFormation names the group <stack name>-<logical ID>-<suffix>; only that group may use the key.
    expect(keyPolicyStatements(template, 'FlowLogKey')).toContainEqual({
      Sid: 'AllowCloudWatchLogsFlowLogGroup',
      Effect: 'Allow',
      Principal: { Service: 'logs.ap-southeast-1.amazonaws.com' },
      Action: ['kms:Decrypt*', 'kms:Describe*', 'kms:Encrypt*', 'kms:GenerateDataKey*', 'kms:ReEncrypt*'],
      Resource: '*',
      Condition: {
        ArnLike: {
          'kms:EncryptionContext:aws:logs:arn': partitionArn(`:logs:ap-southeast-1:${account}:log-group:TestNetwork-${logGroupId}-*`),
        },
      },
    });
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
    const app = newApp();
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
    const app = newApp();
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
    const app = newApp();
    const stack = new NetworkStack(app, 'TestNetworkMismatch', {
      env: { account, region: 'us-east-1' },
      config: { ...devConfig, region: 'us-east-1', kiroProfileRegion: 'eu-central-1' },
    });
    Template.fromStack(stack).resourceCountIs('AWS::EC2::VPCEndpoint', 5);
  });

  test('kiroEndpoints can select a subset of the Kiro endpoints', () => {
    const app = newApp();
    const stack = new NetworkStack(app, 'TestNetworkSubset', {
      env: { account, region: 'us-east-1' },
      config: { ...devConfig, region: 'us-east-1', kiroEndpoints: ['com.amazonaws.us-east-1.q'] },
    });
    const template = Template.fromStack(stack);
    template.resourceCountIs('AWS::EC2::VPCEndpoint', 6);
    template.hasResourceProperties('AWS::EC2::VPCEndpoint', { ServiceName: 'com.amazonaws.us-east-1.q' });
  });

  test('rejects Kiro endpoint names that do not exist in the workload region', () => {
    const app = newApp();
    expect(() => new NetworkStack(app, 'TestNetworkBadEndpoints', {
      env,
      config: { ...devConfig, kiroEndpoints: ['com.amazonaws.ap-southeast-1.q'] },
    })).toThrow(/do not exist/);
  });
});

describe('NetworkStack egress mode nat-dns-firewall', () => {
  const app = newApp();
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
      const badApp = newApp();
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
  const app = newApp();
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
    template.resourceCountIs('AWS::CloudWatch::Alarm', 7);
    template.resourceCountIs('AWS::Logs::MetricFilter', 7);
  });

  test('creates SNS topic for alerts', () => {
    template.resourceCountIs('AWS::SNS::Topic', 1);
  });

  test('CloudWatch alarms have alarm actions', () => {
    const topic = logicalIdOf(template, 'AWS::SNS::Topic');
    template.allResourcesProperties('AWS::CloudWatch::Alarm', {
      AlarmActions: [{ Ref: topic }],
    });
  });

  test('SNS topic policy lets CloudWatch alarms of this account and region publish', () => {
    const topic = logicalIdOf(template, 'AWS::SNS::Topic');
    template.resourceCountIs('AWS::SNS::TopicPolicy', 1);
    template.hasResourceProperties('AWS::SNS::TopicPolicy', {
      Topics: [{ Ref: topic }],
      PolicyDocument: {
        Statement: Match.arrayWith([
          // GuardDuty findings via EventBridge (SNS does not support source conditions for EventBridge)
          Match.objectLike({
            Effect: 'Allow',
            Principal: { Service: 'events.amazonaws.com' },
            Action: 'sns:Publish',
            Resource: { Ref: topic },
          }),
          {
            Sid: 'AllowCloudWatchAlarmsPublish',
            Effect: 'Allow',
            Principal: { Service: 'cloudwatch.amazonaws.com' },
            Action: 'sns:Publish',
            Resource: { Ref: topic },
            Condition: {
              StringEquals: { 'aws:SourceAccount': account },
              ArnLike: { 'aws:SourceArn': partitionArn(`:cloudwatch:ap-southeast-1:${account}:alarm:*`) },
            },
          },
        ]),
      },
    });
  });

  test('no-MFA sign-in filter only counts successful IAM user console sign-ins without MFA', () => {
    template.hasResourceProperties('AWS::Logs::MetricFilter', {
      MetricTransformations: [Match.objectLike({ MetricName: 'ConsoleSignInWithoutMfa', MetricNamespace: 'KiroBanking/Security' })],
      FilterPattern:
        '{ ($.eventName = "ConsoleLogin") && ($.additionalEventData.MFAUsed != "Yes") && ' +
        '($.userIdentity.type = "IAMUser") && ($.responseElements.ConsoleLogin = "Success") }',
    });
  });

  test('IAM policy change filter covers the CIS AWS Foundations 4.4 events for IAM only', () => {
    const filters = Object.values(template.findResources('AWS::Logs::MetricFilter', {
      Properties: { MetricTransformations: [Match.objectLike({ MetricName: 'IamPolicyChanges' })] },
    }));
    expect(filters).toHaveLength(1);
    const pattern = filters[0].Properties.FilterPattern as string;
    expect(pattern.startsWith('{ ($.eventSource = "iam.amazonaws.com") && (')).toBe(true);
    const events = [...pattern.matchAll(/\$\.eventName = (\w+)/g)].map((m) => m[1]).sort();
    expect(events).toEqual([
      'AttachGroupPolicy', 'AttachRolePolicy', 'AttachUserPolicy',
      'CreatePolicy', 'CreatePolicyVersion',
      'DeleteGroupPolicy', 'DeletePolicy', 'DeletePolicyVersion', 'DeleteRolePolicy', 'DeleteUserPolicy',
      'DetachGroupPolicy', 'DetachRolePolicy', 'DetachUserPolicy',
      'PutGroupPolicy', 'PutRolePolicy', 'PutUserPolicy',
      'SetDefaultPolicyVersion',
    ]);
  });

  test.each([
    ['root-account-usage', 'RootAccountUsage',
      '{ ($.userIdentity.type = "Root") && ($.userIdentity.invokedBy NOT EXISTS) && ($.eventType != "AwsServiceEvent") }'],
    ['cloudtrail-change', 'CloudTrailConfigChanges',
      '{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ' +
      '($.eventName = StartLogging) || ($.eventName = StopLogging) }'],
    ['kms-key-disable-or-deletion', 'KmsKeyDisableOrScheduledDeletion',
      '{ ($.eventSource = "kms.amazonaws.com") && (($.eventName = DisableKey) || ($.eventName = ScheduleKeyDeletion)) }'],
  ])('CIS alarm %s notifies the security topic on the first event', (alarmName, metricName, filterPattern) => {
    const topic = logicalIdOf(template, 'AWS::SNS::Topic');
    const trailLogGroup = logicalIdOf(template, 'AWS::Logs::LogGroup');
    template.hasResourceProperties('AWS::Logs::MetricFilter', {
      LogGroupName: { Ref: trailLogGroup },
      FilterPattern: filterPattern,
      MetricTransformations: [{ MetricName: metricName, MetricNamespace: 'KiroBanking/Security', MetricValue: '1' }],
    });
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: `kiro-banking-${alarmName}-dev`,
      MetricName: metricName,
      Namespace: 'KiroBanking/Security',
      Statistic: 'Sum',
      Period: 300,
      Threshold: 1,
      EvaluationPeriods: 1,
      ComparisonOperator: 'GreaterThanOrEqualToThreshold',
      TreatMissingData: 'notBreaching',
      AlarmActions: [{ Ref: topic }],
    });
  });

  test('audit-log bucket has Object Lock with a GOVERNANCE default retention', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      ObjectLockEnabled: true,
      ObjectLockConfiguration: {
        ObjectLockEnabled: 'Enabled',
        Rule: { DefaultRetention: { Mode: 'GOVERNANCE', Days: 30 } },
      },
      VersioningConfiguration: { Status: 'Enabled' },
    });
  });

  test('dev audit-log lifecycle: transitions strictly before the 90-day expiration, noncurrent versions expire', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      ObjectLockEnabled: true,
      LifecycleConfiguration: {
        Rules: [{
          Status: 'Enabled',
          ExpirationInDays: 90,
          NoncurrentVersionExpiration: { NoncurrentDays: 90 },
          Transitions: [{ StorageClass: 'STANDARD_IA', TransitionInDays: 30 }],
        }],
      },
    });
  });

  test('access-log bucket expires after 365 days with a Glacier transition before that', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketEncryption: { ServerSideEncryptionConfiguration: [{ ServerSideEncryptionByDefault: { SSEAlgorithm: 'AES256' } }] },
      LifecycleConfiguration: {
        Rules: [{ Status: 'Enabled', ExpirationInDays: 365, Transitions: [{ StorageClass: 'GLACIER', TransitionInDays: 90 }] }],
      },
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

describe('MonitoringStack options', () => {
  function monitoringTemplate(config: KiroBankingConfig, id: string): Template {
    const app = newApp();
    const enc = new EncryptionStack(app, `${id}Enc`, { env, config });
    return Template.fromStack(new MonitoringStack(app, id, { env, config, kmsKey: enc.auditKey }));
  }

  test('prod audit-log bucket: IA at 30 and Glacier at 90 days, 2555-day expiration, 365-day Object Lock', () => {
    const template = monitoringTemplate(prodConfig, 'TestMonitoringProd');
    template.hasResourceProperties('AWS::S3::Bucket', {
      ObjectLockConfiguration: {
        ObjectLockEnabled: 'Enabled',
        Rule: { DefaultRetention: { Mode: 'GOVERNANCE', Days: 365 } },
      },
      LifecycleConfiguration: {
        Rules: [{
          Status: 'Enabled',
          ExpirationInDays: 2555,
          NoncurrentVersionExpiration: { NoncurrentDays: 90 },
          Transitions: [
            { StorageClass: 'STANDARD_IA', TransitionInDays: 30 },
            { StorageClass: 'GLACIER', TransitionInDays: 90 },
          ],
        }],
      },
    });
  });

  test('a 30-day retention drops all transitions instead of producing an invalid lifecycle rule', () => {
    const template = monitoringTemplate(
      { ...devConfig, cloudTrailRetentionDays: 30, auditLogObjectLockDays: 7, accessLogRetentionDays: 60 },
      'TestMonitoringShort',
    );
    template.hasResourceProperties('AWS::S3::Bucket', {
      ObjectLockEnabled: true,
      LifecycleConfiguration: {
        Rules: [{
          Status: 'Enabled',
          ExpirationInDays: 30,
          NoncurrentVersionExpiration: { NoncurrentDays: 90 },
          Transitions: Match.absent(),
        }],
      },
    });
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketEncryption: { ServerSideEncryptionConfiguration: [{ ServerSideEncryptionByDefault: { SSEAlgorithm: 'AES256' } }] },
      LifecycleConfiguration: { Rules: [{ Status: 'Enabled', ExpirationInDays: 60, Transitions: Match.absent() }] },
    });
  });

  test('transitionsBeforeExpiration keeps only transitions earlier than the expiration', () => {
    const transitions = [
      { storageClass: s3.StorageClass.INFREQUENT_ACCESS, days: 30 },
      { storageClass: s3.StorageClass.GLACIER, days: 90 },
    ];
    expect(transitionsBeforeExpiration(91, transitions)?.map((t) => t.transitionAfter?.toDays())).toEqual([30, 90]);
    expect(transitionsBeforeExpiration(90, transitions)?.map((t) => t.storageClass)).toEqual([s3.StorageClass.INFREQUENT_ACCESS]);
    expect(transitionsBeforeExpiration(30, transitions)).toBeUndefined();
  });

  test('rejects an Object Lock retention longer than the log retention, and non-integer days', () => {
    expect(() => monitoringTemplate({ ...devConfig, auditLogObjectLockDays: 91 }, 'TestMonitoringBadLock'))
      .toThrow(/auditLogObjectLockDays \(91\) must not exceed cloudTrailRetentionDays \(90\)/);
    expect(() => monitoringTemplate({ ...devConfig, accessLogRetentionDays: 1.5 }, 'TestMonitoringBadDays'))
      .toThrow(/accessLogRetentionDays must be a positive whole number/);
  });

  test('enableGuardDuty: false skips the detector but still routes findings to the security topic', () => {
    const template = monitoringTemplate({ ...devConfig, enableGuardDuty: false }, 'TestMonitoringNoGd');
    template.resourceCountIs('AWS::GuardDuty::Detector', 0);
    const topic = logicalIdOf(template, 'AWS::SNS::Topic');
    template.hasResourceProperties('AWS::Events::Rule', {
      Name: 'kiro-banking-guardduty-findings-dev',
      EventPattern: { source: ['aws.guardduty'], 'detail-type': ['GuardDuty Finding'] },
      Targets: [Match.objectLike({ Arn: { Ref: topic } })],
    });
  });
});

describe('ComplianceStack', () => {
  const app = newApp();
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

  test('ComplianceRuleCount output equals the number of Config rules', () => {
    template.hasOutput('ComplianceRuleCount', { Value: '19' });
  });

  test('createConfigRecorder defaults to false: no recorder, no delivery channel, rules have no recorder dependency', () => {
    template.resourceCountIs('AWS::Config::ConfigurationRecorder', 0);
    template.resourceCountIs('AWS::Config::DeliveryChannel', 0);
    template.resourceCountIs('AWS::S3::Bucket', 0);
    for (const rule of Object.values(template.findResources('AWS::Config::ConfigRule'))) {
      expect(rule.DependsOn).toBeUndefined();
    }
  });
});

describe('ComplianceStack with createConfigRecorder: true', () => {
  const app = newApp();
  const stack = new ComplianceStack(app, 'TestComplianceRecorder', {
    env,
    config: { ...devConfig, createConfigRecorder: true },
  });
  const template = Template.fromStack(stack);

  test('creates one recorder for all supported resource types, including global IAM types', () => {
    template.resourceCountIs('AWS::Config::ConfigurationRecorder', 1);
    const role = logicalIdOf(template, 'AWS::IAM::Role');
    template.hasResourceProperties('AWS::Config::ConfigurationRecorder', {
      Name: 'kiro-banking-config-recorder-dev',
      RoleARN: { 'Fn::GetAtt': [role, 'Arn'] },
      RecordingGroup: { AllSupported: true, IncludeGlobalResourceTypes: true },
    });
  });

  test('creates one delivery channel to the dedicated KMS-encrypted bucket, after the recorder', () => {
    template.resourceCountIs('AWS::Config::DeliveryChannel', 1);
    const bucket = logicalIdOf(template, 'AWS::S3::Bucket', { VersioningConfiguration: { Status: 'Enabled' } });
    const key = logicalIdOf(template, 'AWS::KMS::Key');
    template.hasResource('AWS::Config::DeliveryChannel', {
      Properties: {
        Name: 'kiro-banking-config-delivery-dev',
        S3BucketName: { Ref: bucket },
        S3KmsKeyArn: { 'Fn::GetAtt': [key, 'Arn'] },
        ConfigSnapshotDeliveryProperties: { DeliveryFrequency: 'TwentyFour_Hours' },
      },
      DependsOn: Match.arrayWith(['ConfigRecorder']),
    });
  });

  test('keeps 19 rules, each depending on the recorder and the delivery channel', () => {
    const rules = Object.values(template.findResources('AWS::Config::ConfigRule'));
    expect(rules).toHaveLength(19);
    for (const rule of rules) {
      expect(rule.DependsOn).toEqual(expect.arrayContaining(['ConfigRecorder', 'ConfigDeliveryChannel']));
    }
    template.hasOutput('ComplianceRuleCount', { Value: '19' });
  });

  test('Config bucket is KMS-encrypted, versioned, SSL-only, private, access-logged and without Object Lock', () => {
    const key = logicalIdOf(template, 'AWS::KMS::Key');
    const accessLogBucket = logicalIdOf(template, 'AWS::S3::Bucket', { LoggingConfiguration: Match.absent() });
    const bucket = logicalIdOf(template, 'AWS::S3::Bucket', {
      BucketEncryption: {
        ServerSideEncryptionConfiguration: [{
          BucketKeyEnabled: true,
          ServerSideEncryptionByDefault: { SSEAlgorithm: 'aws:kms', KMSMasterKeyID: { 'Fn::GetAtt': [key, 'Arn'] } },
        }],
      },
      VersioningConfiguration: { Status: 'Enabled' },
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true, BlockPublicPolicy: true, IgnorePublicAcls: true, RestrictPublicBuckets: true,
      },
      LoggingConfiguration: { DestinationBucketName: { Ref: accessLogBucket }, LogFilePrefix: 'config-bucket-access/' },
      ObjectLockEnabled: Match.absent(),
    });
    template.hasResourceProperties('AWS::S3::BucketPolicy', {
      Bucket: { Ref: bucket },
      PolicyDocument: {
        Statement: Match.arrayWith([Match.objectLike({
          Effect: 'Deny',
          Action: 's3:*',
          Condition: { Bool: { 'aws:SecureTransport': 'false' } },
        })]),
      },
    });
    template.hasResource('AWS::KMS::Key', {
      Properties: { EnableKeyRotation: true },
      DeletionPolicy: 'Retain',
    });
  });

  test('recorder role trusts AWS Config for this account only and uses AWS_ConfigRole plus scoped delivery permissions', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [{
          Effect: 'Allow',
          Action: 'sts:AssumeRole',
          Principal: { Service: 'config.amazonaws.com' },
          Condition: {
            StringEquals: { 'aws:SourceAccount': account },
            ArnLike: { 'aws:SourceArn': partitionArn(`:config:ap-southeast-1:${account}:*`) },
          },
        }],
      },
      ManagedPolicyArns: [partitionArn(':iam::aws:policy/service-role/AWS_ConfigRole')],
    });
    const bucket = logicalIdOf(template, 'AWS::S3::Bucket', { VersioningConfiguration: { Status: 'Enabled' } });
    const key = logicalIdOf(template, 'AWS::KMS::Key');
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: {
        Statement: [
          {
            Sid: 'ConfigBucketDelivery',
            Effect: 'Allow',
            Action: ['s3:PutObject', 's3:PutObjectAcl'],
            Resource: { 'Fn::Join': ['', [{ 'Fn::GetAtt': [bucket, 'Arn'] }, `/AWSLogs/${account}/*`]] },
            Condition: { StringLike: { 's3:x-amz-acl': 'bucket-owner-full-control' } },
          },
          { Sid: 'ConfigBucketAcl', Effect: 'Allow', Action: 's3:GetBucketAcl', Resource: { 'Fn::GetAtt': [bucket, 'Arn'] } },
          { Sid: 'ConfigBucketKey', Effect: 'Allow', Action: ['kms:Decrypt', 'kms:GenerateDataKey'], Resource: { 'Fn::GetAtt': [key, 'Arn'] } },
        ],
      },
    });
  });

  test('configRecorderGlobalResources: false records regional resource types only', () => {
    const otherApp = newApp();
    const regional = new ComplianceStack(otherApp, 'TestComplianceRegional', {
      env,
      config: { ...devConfig, createConfigRecorder: true, configRecorderGlobalResources: false },
    });
    Template.fromStack(regional).hasResourceProperties('AWS::Config::ConfigurationRecorder', {
      RecordingGroup: { AllSupported: true, IncludeGlobalResourceTypes: false },
    });
  });
});

describe('ComplianceStack account-level singletons', () => {
  test('enableSecurityHub: false and enableAccessAnalyzer: false skip the hub and the analyzer only', () => {
    const app = newApp();
    const stack = new ComplianceStack(app, 'TestComplianceNoSingletons', {
      env,
      config: { ...devConfig, enableSecurityHub: false, enableAccessAnalyzer: false },
    });
    const template = Template.fromStack(stack);
    template.resourceCountIs('AWS::SecurityHub::Hub', 0);
    template.resourceCountIs('AWS::AccessAnalyzer::Analyzer', 0);
    template.resourceCountIs('AWS::Config::ConfigRule', 19);
  });

  test('defaults keep the analyzer name and the hub', () => {
    const app = newApp();
    const template = Template.fromStack(new ComplianceStack(app, 'TestComplianceDefaults', { env, config: devConfig }));
    template.hasResourceProperties('AWS::AccessAnalyzer::Analyzer', { AnalyzerName: 'kiro-banking-analyzer-dev', Type: 'ACCOUNT' });
    template.resourceCountIs('AWS::SecurityHub::Hub', 1);
  });
});

describe('BackupStack', () => {
  const app = newApp();
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
    const key = logicalIdOf(template, 'AWS::KMS::Key');
    template.hasResourceProperties('AWS::Backup::BackupVault', {
      EncryptionKeyArn: { 'Fn::GetAtt': [key, 'Arn'] },
    });
  });

  test('backup schedule defaults to 18:00 UTC (02:00 Singapore time)', () => {
    template.hasResourceProperties('AWS::Backup::BackupPlan', {
      BackupPlan: {
        BackupPlanName: 'kiro-banking-daily-dev',
        BackupPlanRule: [Match.objectLike({ RuleName: 'DailyBackup', ScheduleExpression: 'cron(0 18 * * ? *)' })],
      },
    });
  });

  test('backupScheduleCron overrides the schedule and must be an AWS cron expression', () => {
    const customApp = newApp();
    const custom = new BackupStack(customApp, 'TestBackupCustom', {
      env,
      config: { ...devConfig, backupScheduleCron: 'cron(30 16 ? * SUN *)' },
    });
    Template.fromStack(custom).hasResourceProperties('AWS::Backup::BackupPlan', {
      BackupPlan: { BackupPlanRule: [Match.objectLike({ ScheduleExpression: 'cron(30 16 ? * SUN *)' })] },
    });
    for (const bad of ['0 18 * * ? *', 'rate(1 day)', 'cron(0 18 * *)']) {
      const badApp = newApp();
      expect(() => new BackupStack(badApp, 'TestBackupBad', { env, config: { ...devConfig, backupScheduleCron: bad } }))
        .toThrow(/backupScheduleCron/);
    }
  });
});

describe('CDK Nag Compliance', () => {
  test('all stacks pass CDK Nag AwsSolutionsChecks', () => {
    const app = newApp();
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
    expectNoNagFindings([enc, mon, comp, backupStack, net]);
  });

  test('prodConfig: all five stacks synthesize and pass CDK Nag AwsSolutionsChecks', () => {
    const app = newApp();
    const enc = new EncryptionStack(app, 'NagProdEnc', { env, config: prodConfig });
    const stacks = [
      enc,
      new NetworkStack(app, 'NagProdNet', { env, config: prodConfig }),
      new MonitoringStack(app, 'NagProdMon', { env, config: prodConfig, kmsKey: enc.auditKey }),
      new ComplianceStack(app, 'NagProdComp', { env, config: prodConfig }),
      new BackupStack(app, 'NagProdBackup', { env, config: prodConfig }),
    ];
    Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
    const assembly = app.synth();
    expect(assembly.stacks.map((s) => s.stackName).sort()).toEqual(stacks.map((s) => s.stackName).sort());
    expectNoNagFindings(stacks);
  });

  test('ComplianceStack with createConfigRecorder and the singleton opt-outs pass CDK Nag AwsSolutionsChecks', () => {
    const app = newApp();
    const stacks = [
      new ComplianceStack(app, 'NagCompRecorder', { env, config: { ...devConfig, createConfigRecorder: true } }),
      new ComplianceStack(app, 'NagCompProdRecorder', { env, config: { ...prodConfig, createConfigRecorder: true } }),
      new ComplianceStack(app, 'NagCompNoSingletons', {
        env,
        config: { ...devConfig, enableSecurityHub: false, enableAccessAnalyzer: false },
      }),
    ];
    Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
    app.synth();
    expectNoNagFindings(stacks);
  });

  test('NetworkStack variants (nat-dns-firewall, Kiro profile region) pass CDK Nag AwsSolutionsChecks', () => {
    const app = newApp();
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
