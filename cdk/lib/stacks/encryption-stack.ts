import * as cdk from 'aws-cdk-lib';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { KiroBankingConfig } from '../../config/environments';
import { auditTrailName } from '../naming';

export interface EncryptionStackProps extends cdk.StackProps {
  readonly config: KiroBankingConfig;
}

/**
 * KMS Customer-Managed Keys for Kiro Banking Environment.
 *
 * MAS TRM Section 10 (Cryptography), 10.2 (Cryptographic Key Management):
 * - Customer-managed encryption keys for data at rest
 * - Key rotation enabled
 * - Strict key policies following least privilege: every service-principal
 *   statement is scoped to this account (and, where the service supports it,
 *   to the specific source resource) to prevent confused-deputy use
 */
export class EncryptionStack extends cdk.Stack {
  public readonly auditKey: kms.Key;
  public readonly dataKey: kms.Key;
  public readonly workspacesKey: kms.Key;

  constructor(scope: Construct, id: string, props: EncryptionStackProps) {
    super(scope, id, props);

    const { config } = props;

    // --- KMS Key: Audit Logs (CloudTrail, S3 log bucket, CloudTrail log group, SNS alerts) ---
    this.auditKey = new kms.Key(this, 'AuditKey', {
      alias: `kiro-banking-audit-${config.environment}`,
      description: 'Encrypts CloudTrail logs and audit data (MAS TRM 10.2, 12.2)',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      pendingWindow: cdk.Duration.days(30),
    });

    // CloudTrail: key policy pattern from
    // https://docs.aws.amazon.com/awscloudtrail/latest/userguide/create-kms-key-policy-for-cloudtrail.html
    // aws:SourceArn limits the key to this app's trail; the encryption context
    // limits it to trails owned by this account (any region, because the trail
    // is multi-region).
    const trailArn = this.formatArn({
      service: 'cloudtrail',
      resource: 'trail',
      resourceName: auditTrailName(config.environment),
    });
    const accountTrailsArn = this.formatArn({
      service: 'cloudtrail',
      region: '*',
      resource: 'trail',
      resourceName: '*',
    });

    this.auditKey.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowCloudTrailEncrypt',
        principals: [new iam.ServicePrincipal('cloudtrail.amazonaws.com')],
        actions: ['kms:GenerateDataKey*'],
        resources: ['*'],
        conditions: {
          StringEquals: { 'aws:SourceArn': trailArn },
          StringLike: { 'kms:EncryptionContext:aws:cloudtrail:arn': accountTrailsArn },
        },
      }),
    );

    // DescribeKey carries no encryption context, so it gets its own statement.
    this.auditKey.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowCloudTrailDescribeKey',
        principals: [new iam.ServicePrincipal('cloudtrail.amazonaws.com')],
        actions: ['kms:DescribeKey'],
        resources: ['*'],
        conditions: {
          StringEquals: { 'aws:SourceArn': trailArn },
        },
      }),
    );

    // CloudWatch Logs (the CloudTrail log group): key policy pattern from
    // https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html
    // The encryption context limits the key to log groups in this account and region.
    this.auditKey.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowCloudWatchLogs',
        principals: [new iam.ServicePrincipal(`logs.${config.region}.amazonaws.com`)],
        actions: [
          'kms:Encrypt*',
          'kms:Decrypt*',
          'kms:ReEncrypt*',
          'kms:GenerateDataKey*',
          'kms:Describe*',
        ],
        resources: ['*'],
        conditions: {
          ArnLike: {
            'kms:EncryptionContext:aws:logs:arn': this.formatArn({
              service: 'logs',
              resource: 'log-group',
              resourceName: '*',
              arnFormat: cdk.ArnFormat.COLON_RESOURCE_NAME,
            }),
          },
        },
      }),
    );

    // CloudWatch alarms publish to the SNS security topic, which is encrypted
    // with this key. Without this statement the alarm notifications fail.
    // https://docs.aws.amazon.com/sns/latest/dg/sns-key-management.html
    // (EventBridge, the other publisher, is granted by the SnsTopic target in
    // MonitoringStack; SNS does not support source conditions for EventBridge.)
    this.auditKey.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowCloudWatchAlarmsToEncryptedSns',
        principals: [new iam.ServicePrincipal('cloudwatch.amazonaws.com')],
        actions: ['kms:Decrypt', 'kms:GenerateDataKey*'],
        resources: ['*'],
        conditions: {
          StringEquals: { 'aws:SourceAccount': this.account },
        },
      }),
    );

    // --- KMS Key: Data Encryption (Kiro data, S3 artifacts) ---
    this.dataKey = new kms.Key(this, 'DataKey', {
      alias: `kiro-banking-data-${config.environment}`,
      description: 'Encrypts Kiro data and code artifacts (MAS TRM Section 11.1)',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      pendingWindow: cdk.Duration.days(30),
    });

    // --- KMS Key: WorkSpaces Encryption ---
    this.workspacesKey = new kms.Key(this, 'WorkspacesKey', {
      alias: `kiro-banking-workspaces-${config.environment}`,
      description: 'Encrypts WorkSpaces root and user volumes (MAS TRM 11.1, 11.4)',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      pendingWindow: cdk.Duration.days(30),
    });

    // WorkSpaces uses this key through grants that it creates on behalf of the
    // WorkSpaces administrator (via the account statement above), see
    // https://docs.aws.amazon.com/workspaces/latest/adminguide/encrypt-workspaces.html.
    // The service-principal statement is limited to requests made on behalf of
    // this account.
    this.workspacesKey.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowWorkSpacesEncrypt',
        principals: [new iam.ServicePrincipal('workspaces.amazonaws.com')],
        actions: [
          'kms:Encrypt',
          'kms:Decrypt',
          'kms:ReEncrypt*',
          'kms:GenerateDataKey*',
          'kms:CreateGrant',
          'kms:DescribeKey',
        ],
        resources: ['*'],
        conditions: {
          StringEquals: { 'aws:SourceAccount': this.account },
        },
      }),
    );

    // --- Outputs ---
    new cdk.CfnOutput(this, 'AuditKeyArn', {
      value: this.auditKey.keyArn,
      description: 'KMS key ARN for audit log encryption',
      exportName: `KiroBanking-AuditKeyArn-${config.environment}`,
    });

    new cdk.CfnOutput(this, 'DataKeyArn', {
      value: this.dataKey.keyArn,
      description: 'KMS key ARN for data encryption',
      exportName: `KiroBanking-DataKeyArn-${config.environment}`,
    });

    new cdk.CfnOutput(this, 'WorkspacesKeyArn', {
      value: this.workspacesKey.keyArn,
      description: 'KMS key ARN for WorkSpaces encryption',
      exportName: `KiroBanking-WorkspacesKeyArn-${config.environment}`,
    });
  }
}
