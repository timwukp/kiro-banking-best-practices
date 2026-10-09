import * as cdk from 'aws-cdk-lib';
import * as config from 'aws-cdk-lib/aws-config';
import * as accessanalyzer from 'aws-cdk-lib/aws-accessanalyzer';
import * as securityhub from 'aws-cdk-lib/aws-securityhub';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct, IDependable } from 'constructs';
import { NagSuppressions } from 'cdk-nag';
import { KiroBankingConfig } from '../../config/environments';

/**
 * Compliance Stack: AWS Config rules for continuous monitoring of controls
 * aligned with the MAS TRM Guidelines.
 *
 * Implements automated configuration checks mapped to MAS TRM Guidelines:
 * - 9.1 / 9.2: User and privileged access management
 * - 10.1 / 10.2: Cryptographic protocols and key management
 * - 11.1 / 11.2: Data and network security
 * - 12.2: Cyber event monitoring and detection (audit logging; the logs serve
 *   as evidence for the independent IT audit function, TRM 15.1)
 *
 * Also covers:
 * - PDPA: Data protection controls
 *
 * Note: the AWS Config rule names (e.g. mas-trm-15-*) keep their original
 * numbering so that deployed rules are not replaced. The rule description
 * carries the current TRM mapping.
 *
 * Prerequisite: AWS Config rules need a configuration recorder in the account
 * and region. Set createConfigRecorder: true to create one here (with its
 * delivery channel and bucket), or keep the default (false) where AWS Control
 * Tower or an organization-wide setup already records.
 */
export interface ComplianceStackProps extends cdk.StackProps {
  readonly config: KiroBankingConfig;
}

export class ComplianceStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: ComplianceStackProps) {
    super(scope, id, props);

    const { config: envConfig } = props;

    // Each account and region supports one configuration recorder; see
    // KiroBankingConfig.createConfigRecorder.
    const recorderResources = (envConfig.createConfigRecorder ?? false) ? this.addConfigRecorder(envConfig) : [];

    // ═══════════════════════════════════════════════════════════
    // MAS TRM Section 9: Access Control
    // ═══════════════════════════════════════════════════════════

    // IAM root access key check
    new config.ManagedRule(this, 'IamRootAccessKeyCheck', {
      identifier: 'IAM_ROOT_ACCESS_KEY_CHECK',
      configRuleName: `mas-trm-9-iam-root-key-${envConfig.environment}`,
      description: 'MAS TRM 9.2: Ensure root account does not have access keys',
    });

    // MFA enabled for IAM console access
    new config.ManagedRule(this, 'MfaEnabledForConsole', {
      identifier: 'MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS',
      configRuleName: `mas-trm-9-mfa-console-${envConfig.environment}`,
      description: 'MAS TRM 9.1: Ensure MFA is enabled for all IAM users with console access',
    });

    // Root account MFA
    new config.ManagedRule(this, 'RootAccountMfa', {
      identifier: 'ROOT_ACCOUNT_MFA_ENABLED',
      configRuleName: `mas-trm-9-root-mfa-${envConfig.environment}`,
      description: 'MAS TRM 9.2: Ensure root account has MFA enabled',
    });

    // IAM password policy
    new config.ManagedRule(this, 'IamPasswordPolicy', {
      identifier: 'IAM_PASSWORD_POLICY',
      configRuleName: `mas-trm-9-password-policy-${envConfig.environment}`,
      description: 'MAS TRM 9.1: Ensure IAM password policy is set per institutional password policy',
      inputParameters: {
        RequireUppercaseCharacters: 'true',
        RequireLowercaseCharacters: 'true',
        RequireSymbols: 'true',
        RequireNumbers: 'true',
        MinimumPasswordLength: '14',
        PasswordReusePrevention: '24',
        MaxPasswordAge: '90',
      },
    });

    // No IAM policies attached directly to users
    new config.ManagedRule(this, 'IamNoInlinePolicy', {
      identifier: 'IAM_USER_NO_POLICIES_CHECK',
      configRuleName: `mas-trm-9-no-user-policies-${envConfig.environment}`,
      description: 'MAS TRM 9.1: IAM policies should be attached to groups/roles, not users',
    });

    // ═══════════════════════════════════════════════════════════
    // MAS TRM Section 10: Cryptography
    // ═══════════════════════════════════════════════════════════

    // KMS key rotation enabled
    new config.ManagedRule(this, 'KmsKeyRotation', {
      identifier: 'CMK_BACKING_KEY_ROTATION_ENABLED',
      configRuleName: `mas-trm-10-kms-rotation-${envConfig.environment}`,
      description: 'MAS TRM 10.2: Ensure KMS customer-managed key rotation is enabled',
    });

    // ═══════════════════════════════════════════════════════════
    // MAS TRM Section 11: Data & Network Security
    // ═══════════════════════════════════════════════════════════

    // S3 bucket encryption
    new config.ManagedRule(this, 'S3BucketEncryption', {
      identifier: 'S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED',
      configRuleName: `mas-trm-11-s3-encryption-${envConfig.environment}`,
      description: 'MAS TRM 11.1: Ensure all S3 buckets have server-side encryption',
    });

    // S3 bucket public access blocked
    new config.ManagedRule(this, 'S3PublicAccessBlocked', {
      identifier: 'S3_BUCKET_PUBLIC_READ_PROHIBITED',
      configRuleName: `mas-trm-11-s3-no-public-read-${envConfig.environment}`,
      description: 'MAS TRM 11.1: Ensure S3 buckets prohibit public read access',
    });

    new config.ManagedRule(this, 'S3PublicWriteBlocked', {
      identifier: 'S3_BUCKET_PUBLIC_WRITE_PROHIBITED',
      configRuleName: `mas-trm-11-s3-no-public-write-${envConfig.environment}`,
      description: 'MAS TRM 11.1: Ensure S3 buckets prohibit public write access',
    });

    // S3 SSL-only access
    new config.ManagedRule(this, 'S3SslOnly', {
      identifier: 'S3_BUCKET_SSL_REQUESTS_ONLY',
      configRuleName: `mas-trm-11-s3-ssl-only-${envConfig.environment}`,
      description: 'MAS TRM 10.1: Ensure S3 buckets require SSL/TLS connections',
    });

    // VPC flow logs enabled
    new config.ManagedRule(this, 'VpcFlowLogsEnabled', {
      identifier: 'VPC_FLOW_LOGS_ENABLED',
      configRuleName: `mas-trm-11-vpc-flow-logs-${envConfig.environment}`,
      description: 'MAS TRM 11.2 / 12.2: Ensure VPC flow logs are enabled for network monitoring',
    });

    // Security groups: no unrestricted SSH
    new config.ManagedRule(this, 'NoUnrestrictedSsh', {
      identifier: 'INCOMING_SSH_DISABLED',
      configRuleName: `mas-trm-11-no-open-ssh-${envConfig.environment}`,
      description: 'MAS TRM 11.2: Ensure security groups do not allow unrestricted SSH',
    });

    // Security groups: restrict default SG
    new config.ManagedRule(this, 'RestrictDefaultSg', {
      identifier: 'VPC_DEFAULT_SECURITY_GROUP_CLOSED',
      configRuleName: `mas-trm-11-default-sg-closed-${envConfig.environment}`,
      description: 'MAS TRM 11.2: Ensure default security group restricts all traffic',
    });

    // EBS encryption by default
    new config.ManagedRule(this, 'EbsEncryption', {
      identifier: 'EC2_EBS_ENCRYPTION_BY_DEFAULT',
      configRuleName: `mas-trm-11-ebs-encryption-${envConfig.environment}`,
      description: 'MAS TRM 11.1: Ensure EBS volume encryption is enabled by default',
    });

    // ═══════════════════════════════════════════════════════════
    // MAS TRM 12.2: Cyber Event Monitoring and Detection (audit logging)
    // The logs serve as evidence for the IT audit function (TRM 15.1).
    // ═══════════════════════════════════════════════════════════

    // CloudTrail enabled
    new config.ManagedRule(this, 'CloudTrailEnabled', {
      identifier: 'CLOUD_TRAIL_ENABLED',
      configRuleName: `mas-trm-15-cloudtrail-enabled-${envConfig.environment}`,
      description: 'MAS TRM 12.2: Ensure CloudTrail is enabled for audit logging (evidence for the TRM 15.1 IT audit function)',
    });

    // CloudTrail log file validation
    new config.ManagedRule(this, 'CloudTrailLogValidation', {
      identifier: 'CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED',
      configRuleName: `mas-trm-15-log-validation-${envConfig.environment}`,
      description: 'MAS TRM 12.2: Ensure CloudTrail log file integrity validation is enabled',
    });

    // CloudTrail encrypted
    new config.ManagedRule(this, 'CloudTrailEncrypted', {
      identifier: 'CLOUD_TRAIL_ENCRYPTION_ENABLED',
      configRuleName: `mas-trm-15-cloudtrail-encrypted-${envConfig.environment}`,
      description: 'MAS TRM 12.2/10.2: Ensure CloudTrail logs are encrypted with KMS',
    });

    // ═══════════════════════════════════════════════════════════
    // PDPA: Data Protection
    // ═══════════════════════════════════════════════════════════

    // RDS encryption
    new config.ManagedRule(this, 'RdsEncryption', {
      identifier: 'RDS_STORAGE_ENCRYPTED',
      configRuleName: `pdpa-rds-encryption-${envConfig.environment}`,
      description: 'PDPA: Ensure RDS instances have encryption at rest for personal data protection',
    });

    // RDS public access
    new config.ManagedRule(this, 'RdsNoPublicAccess', {
      identifier: 'RDS_INSTANCE_PUBLIC_ACCESS_CHECK',
      configRuleName: `pdpa-rds-no-public-${envConfig.environment}`,
      description: 'PDPA: Ensure RDS instances are not publicly accessible',
    });

    // ═══════════════════════════════════════════════════════════
    // Security Services
    // ═══════════════════════════════════════════════════════════

    // Account-level singletons: skip them where they are managed centrally
    // (e.g. a delegated administrator for the organization).

    // IAM Access Analyzer
    if (envConfig.enableAccessAnalyzer ?? true) {
      new accessanalyzer.CfnAnalyzer(this, 'AccessAnalyzer', {
        analyzerName: `kiro-banking-analyzer-${envConfig.environment}`,
        type: 'ACCOUNT',
      });
    }

    // SecurityHub (one hub per account and region)
    if (envConfig.enableSecurityHub ?? true) {
      new securityhub.CfnHub(this, 'SecurityHub', {});
    }

    // Rules can only be created once a recorder exists.
    const rules = this.node.children.filter((child): child is config.ManagedRule => child instanceof config.ManagedRule);
    for (const rule of rules) {
      rule.node.addDependency(...recorderResources);
    }

    // --- Outputs ---
    new cdk.CfnOutput(this, 'ComplianceRuleCount', {
      value: String(rules.length),
      description: 'Number of AWS Config compliance rules deployed',
    });
  }

  /**
   * Configuration recorder (all supported resource types), delivery channel and
   * a dedicated encrypted, versioned, SSL-only bucket with server access logs.
   * AWS Config does not support delivery to a bucket with Object Lock, so the
   * audit-log bucket is not reused. Returns the resources the rules depend on.
   */
  private addConfigRecorder(envConfig: KiroBankingConfig): IDependable[] {
    const env = envConfig.environment;

    const accessLogBucket = new s3.Bucket(this, 'ConfigAccessLogBucket', {
      bucketName: `kiro-banking-config-access-logs-${env}-${cdk.Aws.ACCOUNT_ID}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      lifecycleRules: [{ expiration: cdk.Duration.days(envConfig.accessLogRetentionDays ?? 365) }],
    });

    const bucketKey = new kms.Key(this, 'ConfigBucketKey', {
      alias: `kiro-banking-config-${env}`,
      description: 'Encrypts AWS Config configuration history and snapshots (MAS TRM 10.2, 12.2)',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      pendingWindow: cdk.Duration.days(30),
    });

    const bucket = new s3.Bucket(this, 'ConfigBucket', {
      bucketName: `kiro-banking-config-${env}-${cdk.Aws.ACCOUNT_ID}`,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: bucketKey,
      bucketKeyEnabled: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      serverAccessLogsBucket: accessLogBucket,
      serverAccessLogsPrefix: 'config-bucket-access/',
      lifecycleRules: [
        {
          expiration: cdk.Duration.days(envConfig.cloudTrailRetentionDays),
          noncurrentVersionExpiration: cdk.Duration.days(90),
        },
      ],
    });

    // Role permissions from
    // https://docs.aws.amazon.com/config/latest/developerguide/iamrole-permissions.html
    const role = new iam.Role(this, 'ConfigRecorderRole', {
      description: 'Lets AWS Config record resource configurations and deliver them to the Config bucket',
      assumedBy: new iam.ServicePrincipal('config.amazonaws.com').withConditions({
        StringEquals: { 'aws:SourceAccount': this.account },
        ArnLike: { 'aws:SourceArn': this.formatArn({ service: 'config', resource: '*' }) },
      }),
      managedPolicies: [iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWS_ConfigRole')],
    });
    role.addToPolicy(new iam.PolicyStatement({
      sid: 'ConfigBucketDelivery',
      actions: ['s3:PutObject', 's3:PutObjectAcl'],
      resources: [bucket.arnForObjects(`AWSLogs/${this.account}/*`)],
      conditions: { StringLike: { 's3:x-amz-acl': 'bucket-owner-full-control' } },
    }));
    role.addToPolicy(new iam.PolicyStatement({
      sid: 'ConfigBucketAcl',
      actions: ['s3:GetBucketAcl'],
      resources: [bucket.bucketArn],
    }));
    role.addToPolicy(new iam.PolicyStatement({
      sid: 'ConfigBucketKey',
      actions: ['kms:Decrypt', 'kms:GenerateDataKey'],
      resources: [bucketKey.keyArn],
    }));

    const recorder = new config.CfnConfigurationRecorder(this, 'ConfigRecorder', {
      name: `kiro-banking-config-recorder-${env}`,
      roleArn: role.roleArn,
      recordingGroup: {
        allSupported: true,
        // Record the global IAM resource types in one region only.
        includeGlobalResourceTypes: envConfig.configRecorderGlobalResources ?? true,
      },
    });
    recorder.node.addDependency(role);

    // A delivery channel can only be created after the recorder; CloudFormation
    // starts the recorder once the delivery channel exists.
    const deliveryChannel = new config.CfnDeliveryChannel(this, 'ConfigDeliveryChannel', {
      name: `kiro-banking-config-delivery-${env}`,
      s3BucketName: bucket.bucketName,
      s3KmsKeyArn: bucketKey.keyArn,
      configSnapshotDeliveryProperties: { deliveryFrequency: 'TwentyFour_Hours' },
    });
    deliveryChannel.addDependency(recorder);
    deliveryChannel.node.addDependency(role, bucket);

    NagSuppressions.addResourceSuppressions(role, [
      {
        id: 'AwsSolutions-IAM4',
        reason: 'AWS_ConfigRole is the AWS managed policy for AWS Config recorder roles; AWS keeps it up to date ' +
          'with the read permissions needed for every resource type that Config records',
        appliesTo: ['Policy::arn:<AWS::Partition>:iam::aws:policy/service-role/AWS_ConfigRole'],
      },
      {
        id: 'AwsSolutions-IAM5',
        reason: 'AWS Config writes configuration history and snapshot objects with generated names under ' +
          'AWSLogs/<account>/ in its dedicated bucket (pattern from the AWS Config documentation)',
        appliesTo: [{ regex: '/^Resource::<ConfigBucket[0-9A-F]+\\.Arn>\\/AWSLogs\\/(<AWS::AccountId>|\\d{12})\\/\\*$/' }],
      },
    ], true);

    return [recorder, deliveryChannel];
  }
}
