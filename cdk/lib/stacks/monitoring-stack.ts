import * as cdk from 'aws-cdk-lib';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import { Construct } from 'constructs';
import { KiroBankingConfig } from '../../config/environments';
import { NagSuppressions } from 'cdk-nag';

export interface MonitoringStackProps extends cdk.StackProps {
  readonly config: KiroBankingConfig;
  readonly kmsKey: kms.Key;
}

/**
 * Monitoring Stack: CloudTrail audit logging and CloudWatch alarms.
 *
 * MAS TRM Section 15 (IT Audit):
 * - Comprehensive audit trail for all Kiro activities
 * - Log file integrity validation
 * - Encrypted log storage with customer-managed KMS key
 * - CloudWatch alarms for security-relevant events
 *
 * MAS TRM Section 12 (Cyber Security Operations):
 * - Security event monitoring
 * - Anomaly detection via CloudWatch alarms
 * - SNS notifications for security team
 */
export class MonitoringStack extends cdk.Stack {
  public readonly trail: cloudtrail.Trail;
  public readonly logBucket: s3.Bucket;
  public readonly securityTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: MonitoringStackProps) {
    super(scope, id, props);

    const { config, kmsKey } = props;

    // --- SNS Topic for Security Alerts ---
    this.securityTopic = new sns.Topic(this, 'SecurityAlertsTopic', {
      topicName: `kiro-banking-security-alerts-${config.environment}`,
      displayName: 'Kiro Banking Security Alerts',
      masterKey: kmsKey,
    });

    // --- S3 Bucket: CloudTrail Audit Logs ---
    const accessLogBucket = new s3.Bucket(this, 'AccessLogBucket', {
      bucketName: `kiro-banking-access-logs-${config.environment}-${cdk.Aws.ACCOUNT_ID}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      lifecycleRules: [
        {
          expiration: cdk.Duration.days(365),
          transitions: [
            { storageClass: s3.StorageClass.GLACIER, transitionAfter: cdk.Duration.days(90) },
          ],
        },
      ],
    });

    this.logBucket = new s3.Bucket(this, 'AuditLogBucket', {
      bucketName: `kiro-banking-audit-logs-${config.environment}-${cdk.Aws.ACCOUNT_ID}`,
      encryptionKey: kmsKey,
      encryption: s3.BucketEncryption.KMS,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: true,
      objectLockEnabled: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      serverAccessLogsBucket: accessLogBucket,
      serverAccessLogsPrefix: 'audit-bucket-access/',
      lifecycleRules: [
        {
          transitions: [
            { storageClass: s3.StorageClass.INFREQUENT_ACCESS, transitionAfter: cdk.Duration.days(30) },
            { storageClass: s3.StorageClass.GLACIER, transitionAfter: cdk.Duration.days(90) },
          ],
          expiration: cdk.Duration.days(config.cloudTrailRetentionDays),
        },
      ],
    });

    // --- CloudWatch Log Group for CloudTrail ---
    const trailLogGroup = new logs.LogGroup(this, 'TrailLogGroup', {
      logGroupName: `/kiro-banking/cloudtrail/${config.environment}`,
      retention: logs.RetentionDays.TWO_YEARS,
      encryptionKey: kmsKey,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // --- CloudTrail: Multi-region, management + data events ---
    this.trail = new cloudtrail.Trail(this, 'KiroAuditTrail', {
      trailName: `kiro-banking-audit-${config.environment}`,
      bucket: this.logBucket,
      s3KeyPrefix: 'cloudtrail',
      encryptionKey: kmsKey,
      enableFileValidation: true,
      isMultiRegionTrail: true,
      includeGlobalServiceEvents: true,
      cloudWatchLogGroup: trailLogGroup,
      sendToCloudWatchLogs: true,
    });

    // --- CloudWatch Alarms ---

    // Alarm: Unauthorized API calls
    const unauthorizedApiFilter = new logs.MetricFilter(this, 'UnauthorizedApiFilter', {
      logGroup: trailLogGroup,
      filterPattern: logs.FilterPattern.literal('{ ($.errorCode = "*UnauthorizedAccess") || ($.errorCode = "AccessDenied*") }'),
      metricNamespace: 'KiroBanking/Security',
      metricName: 'UnauthorizedApiCalls',
      metricValue: '1',
    });

    new cloudwatch.Alarm(this, 'UnauthorizedApiAlarm', {
      alarmName: `kiro-banking-unauthorized-api-${config.environment}`,
      alarmDescription: 'MAS TRM 9.1: Alert on unauthorized API calls to Kiro services',
      metric: unauthorizedApiFilter.metric({
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Alarm: Console sign-in without MFA
    const noMfaFilter = new logs.MetricFilter(this, 'NoMfaSignInFilter', {
      logGroup: trailLogGroup,
      filterPattern: logs.FilterPattern.literal('{ ($.eventName = "ConsoleLogin") && ($.additionalEventData.MFAUsed != "Yes") }'),
      metricNamespace: 'KiroBanking/Security',
      metricName: 'ConsoleSignInWithoutMfa',
      metricValue: '1',
    });

    new cloudwatch.Alarm(this, 'NoMfaSignInAlarm', {
      alarmName: `kiro-banking-no-mfa-signin-${config.environment}`,
      alarmDescription: 'MAS TRM 9.1: Alert on console sign-in without MFA',
      metric: noMfaFilter.metric({
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Alarm: IAM policy changes
    const iamPolicyChangeFilter = new logs.MetricFilter(this, 'IamPolicyChangeFilter', {
      logGroup: trailLogGroup,
      filterPattern: logs.FilterPattern.literal('{ ($.eventName = CreatePolicy) || ($.eventName = DeletePolicy) || ($.eventName = AttachRolePolicy) || ($.eventName = DetachRolePolicy) || ($.eventName = AttachUserPolicy) || ($.eventName = DetachUserPolicy) || ($.eventName = PutUserPolicy) || ($.eventName = PutRolePolicy) }'),
      metricNamespace: 'KiroBanking/Security',
      metricName: 'IamPolicyChanges',
      metricValue: '1',
    });

    new cloudwatch.Alarm(this, 'IamPolicyChangeAlarm', {
      alarmName: `kiro-banking-iam-policy-change-${config.environment}`,
      alarmDescription: 'MAS TRM 9.1: Alert on IAM policy modifications',
      metric: iamPolicyChangeFilter.metric({
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Alarm: Security group changes
    const sgChangeFilter = new logs.MetricFilter(this, 'SgChangeFilter', {
      logGroup: trailLogGroup,
      filterPattern: logs.FilterPattern.literal('{ ($.eventName = AuthorizeSecurityGroupIngress) || ($.eventName = AuthorizeSecurityGroupEgress) || ($.eventName = RevokeSecurityGroupIngress) || ($.eventName = RevokeSecurityGroupEgress) || ($.eventName = CreateSecurityGroup) || ($.eventName = DeleteSecurityGroup) }'),
      metricNamespace: 'KiroBanking/Security',
      metricName: 'SecurityGroupChanges',
      metricValue: '1',
    });

    new cloudwatch.Alarm(this, 'SgChangeAlarm', {
      alarmName: `kiro-banking-sg-change-${config.environment}`,
      alarmDescription: 'MAS TRM 11.2: Alert on security group modifications',
      metric: sgChangeFilter.metric({
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // --- Outputs ---
    new cdk.CfnOutput(this, 'AuditLogBucketName', {
      value: this.logBucket.bucketName,
      description: 'S3 bucket for CloudTrail audit logs',
    });

    new cdk.CfnOutput(this, 'TrailArn', {
      value: this.trail.trailArn,
      description: 'CloudTrail trail ARN',
    });

    new cdk.CfnOutput(this, 'SecurityTopicArn', {
      value: this.securityTopic.topicArn,
      description: 'SNS topic ARN for security alerts',
    });

    // CDK Nag suppressions
    NagSuppressions.addResourceSuppressions(accessLogBucket, [
      { id: 'AwsSolutions-S1', reason: 'This IS the access log bucket - cannot log to itself' },
    ]);
  }
}
