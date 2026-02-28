import * as cdk from 'aws-cdk-lib';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { KiroBankingConfig } from '../../config/environments';
import { NagSuppressions } from 'cdk-nag';

export interface EncryptionStackProps extends cdk.StackProps {
  readonly config: KiroBankingConfig;
}

/**
 * KMS Customer-Managed Keys for Kiro Banking Environment.
 *
 * MAS TRM Section 10 (Cryptography):
 * - Customer-managed encryption keys for data at rest
 * - Key rotation enabled
 * - Strict key policies following least privilege
 */
export class EncryptionStack extends cdk.Stack {
  public readonly auditKey: kms.Key;
  public readonly dataKey: kms.Key;
  public readonly workspacesKey: kms.Key;

  constructor(scope: Construct, id: string, props: EncryptionStackProps) {
    super(scope, id, props);

    const { config } = props;

    // --- KMS Key: Audit Logs (CloudTrail, S3 log bucket) ---
    this.auditKey = new kms.Key(this, 'AuditKey', {
      alias: `kiro-banking-audit-${config.environment}`,
      description: 'Encrypts CloudTrail logs and audit data (MAS TRM Section 15)',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      pendingWindow: cdk.Duration.days(30),
    });

    // Allow CloudTrail to use the key
    this.auditKey.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowCloudTrailEncrypt',
        principals: [new iam.ServicePrincipal('cloudtrail.amazonaws.com')],
        actions: ['kms:GenerateDataKey*', 'kms:DescribeKey'],
        resources: ['*'],
        conditions: {
          StringLike: {
            'kms:EncryptionContext:aws:cloudtrail:arn': `arn:aws:cloudtrail:${config.region}:*:trail/*`,
          },
        },
      }),
    );

    // Allow CloudWatch Logs to use the key
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
      description: 'Encrypts WorkSpaces root and user volumes (MAS TRM Section 8.5)',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      pendingWindow: cdk.Duration.days(30),
    });

    // Allow WorkSpaces service to use the key
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

    // CDK Nag suppressions with justification
    NagSuppressions.addResourceSuppressions(this.auditKey, [
      {
        id: 'AwsSolutions-KMS5',
        reason: 'Key rotation is enabled via enableKeyRotation: true',
      },
    ]);
  }
}
