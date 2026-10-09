import * as cdk from 'aws-cdk-lib';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatch_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as guardduty from 'aws-cdk-lib/aws-guardduty';
import * as events from 'aws-cdk-lib/aws-events';
import * as events_targets from 'aws-cdk-lib/aws-events-targets';
import { Construct } from 'constructs';
import { KiroBankingConfig } from '../../config/environments';
import { auditTrailName } from '../naming';

export interface MonitoringStackProps extends cdk.StackProps {
  readonly config: KiroBankingConfig;
  readonly kmsKey: kms.Key;
}

/**
 * Days after which noncurrent versions in the versioned audit-log bucket are
 * removed. Object Lock still prevents removal before the lock expires.
 */
export const AUDIT_LOG_NONCURRENT_VERSION_EXPIRATION_DAYS = 90;

/**
 * Keeps only the lifecycle transitions that happen strictly before the
 * expiration. S3 rejects a lifecycle rule whose expiration is not later than
 * its transitions (e.g. a Glacier transition at 90 days with a 90-day
 * expiration). Returns undefined when no transition is left.
 */
export function transitionsBeforeExpiration(
  expirationDays: number,
  transitions: ReadonlyArray<{ storageClass: s3.StorageClass; days: number }>,
): s3.Transition[] | undefined {
  const kept = transitions
    .filter((t) => t.days < expirationDays)
    .map((t) => ({ storageClass: t.storageClass, transitionAfter: cdk.Duration.days(t.days) }));
  return kept.length > 0 ? kept : undefined;
}

function requirePositiveInteger(name: string, value: number): number {
  if (!Number.isInteger(value) || value < 1) {
    throw new Error(`${name} must be a positive whole number of days; got ${value}`);
  }
  return value;
}

/** A CloudTrail metric filter plus an alarm that notifies the security topic. */
interface SecurityAlarmProps {
  /** CloudWatch Logs filter pattern for CloudTrail events. */
  readonly filterPattern: string;
  /** Metric name in the KiroBanking/Security namespace. */
  readonly metricName: string;
  /** Middle part of the alarm name: kiro-banking-<name>-<environment>. */
  readonly alarmName: string;
  readonly alarmDescription: string;
  /** Events per 5 minutes that trigger the alarm. @default 1 */
  readonly threshold?: number;
}

/**
 * Monitoring Stack: CloudTrail audit logging and CloudWatch alarms.
 *
 * MAS TRM 12.2 (Cyber Event Monitoring and Detection):
 * - Comprehensive audit trail for all Kiro activities
 * - Log file integrity validation
 * - Encrypted log storage with customer-managed KMS key (TRM 10.2)
 * - Object Lock (GOVERNANCE) default retention on the audit-log bucket
 * - CloudWatch alarms (aligned with the CIS AWS Foundations Benchmark
 *   monitoring controls) and GuardDuty for security-relevant events
 * - SNS notifications for the security team (input to TRM 12.3 incident response)
 *
 * The logs also serve as evidence for the independent IT audit function
 * (MAS TRM 15.1). TRM Section 15 covers the audit function, not logging itself.
 */
export class MonitoringStack extends cdk.Stack {
  public readonly trail: cloudtrail.Trail;
  public readonly logBucket: s3.Bucket;
  public readonly securityTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: MonitoringStackProps) {
    super(scope, id, props);

    const { config, kmsKey } = props;

    const retentionDays = requirePositiveInteger('cloudTrailRetentionDays', config.cloudTrailRetentionDays);
    const objectLockDays = requirePositiveInteger('auditLogObjectLockDays', config.auditLogObjectLockDays ?? 30);
    const accessLogRetentionDays = requirePositiveInteger('accessLogRetentionDays', config.accessLogRetentionDays ?? 365);
    if (objectLockDays > retentionDays) {
      throw new Error(
        `auditLogObjectLockDays (${objectLockDays}) must not exceed cloudTrailRetentionDays (${retentionDays})`,
      );
    }

    // --- SNS Topic for Security Alerts ---
    this.securityTopic = new sns.Topic(this, 'SecurityAlertsTopic', {
      topicName: `kiro-banking-security-alerts-${config.environment}`,
      displayName: 'Kiro Banking Security Alerts',
      masterKey: kmsKey,
    });
    // NOTE: Subscriptions (email, Lambda, chatbot) are managed externally per organization requirements

    // --- S3 Bucket: server access logs of the audit-log bucket ---
    // These logs record reads and changes of the audit logs. They expire after
    // accessLogRetentionDays (default 365), which can be shorter than the audit
    // log retention; raise it if your record-keeping policy requires.
    const accessLogBucket = new s3.Bucket(this, 'AccessLogBucket', {
      bucketName: `kiro-banking-access-logs-${config.environment}-${cdk.Aws.ACCOUNT_ID}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      lifecycleRules: [
        {
          expiration: cdk.Duration.days(accessLogRetentionDays),
          transitions: transitionsBeforeExpiration(accessLogRetentionDays, [
            { storageClass: s3.StorageClass.GLACIER, days: 90 },
          ]),
        },
      ],
    });

    // --- S3 Bucket: CloudTrail Audit Logs ---
    this.logBucket = new s3.Bucket(this, 'AuditLogBucket', {
      bucketName: `kiro-banking-audit-logs-${config.environment}-${cdk.Aws.ACCOUNT_ID}`,
      encryptionKey: kmsKey,
      encryption: s3.BucketEncryption.KMS,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: true,
      objectLockEnabled: true,
      // GOVERNANCE mode can be lifted by principals with s3:BypassGovernanceRetention.
      // COMPLIANCE mode cannot be shortened or removed by anyone (including root)
      // until each object's retention expires: switch only after legal review.
      objectLockDefaultRetention: s3.ObjectLockRetention.governance(cdk.Duration.days(objectLockDays)),
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      serverAccessLogsBucket: accessLogBucket,
      serverAccessLogsPrefix: 'audit-bucket-access/',
      lifecycleRules: [
        {
          transitions: transitionsBeforeExpiration(retentionDays, [
            { storageClass: s3.StorageClass.INFREQUENT_ACCESS, days: 30 },
            { storageClass: s3.StorageClass.GLACIER, days: 90 },
          ]),
          expiration: cdk.Duration.days(retentionDays),
          noncurrentVersionExpiration: cdk.Duration.days(AUDIT_LOG_NONCURRENT_VERSION_EXPIRATION_DAYS),
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
      // The AuditKey policy (EncryptionStack) refers to this trail by name.
      trailName: auditTrailName(config.environment),
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
    const addSecurityAlarm = (id: string, alarmProps: SecurityAlarmProps): cloudwatch.Alarm => {
      const filter = new logs.MetricFilter(this, `${id}Filter`, {
        logGroup: trailLogGroup,
        filterPattern: logs.FilterPattern.literal(alarmProps.filterPattern),
        metricNamespace: 'KiroBanking/Security',
        metricName: alarmProps.metricName,
        metricValue: '1',
      });

      const alarm = new cloudwatch.Alarm(this, `${id}Alarm`, {
        alarmName: `kiro-banking-${alarmProps.alarmName}-${config.environment}`,
        alarmDescription: alarmProps.alarmDescription,
        metric: filter.metric({
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: alarmProps.threshold ?? 1,
        evaluationPeriods: 1,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });
      alarm.addAlarmAction(new cloudwatch_actions.SnsAction(this.securityTopic));
      return alarm;
    };

    addSecurityAlarm('UnauthorizedApi', {
      filterPattern: '{ ($.errorCode = "*UnauthorizedAccess") || ($.errorCode = "AccessDenied*") }',
      metricName: 'UnauthorizedApiCalls',
      alarmName: 'unauthorized-api',
      alarmDescription: 'MAS TRM 12.2 / 9.1: Alert on unauthorized API calls to Kiro services',
      threshold: 5,
    });

    // CIS AWS Foundations 4.2: successful IAM user console sign-in without MFA.
    // Federated sign-ins (IAM Identity Center, external IdP) are excluded: their
    // MFA is enforced by the identity provider and CloudTrail reports them with
    // MFAUsed = "No".
    addSecurityAlarm('NoMfaSignIn', {
      filterPattern:
        '{ ($.eventName = "ConsoleLogin") && ($.additionalEventData.MFAUsed != "Yes") && ' +
        '($.userIdentity.type = "IAMUser") && ($.responseElements.ConsoleLogin = "Success") }',
      metricName: 'ConsoleSignInWithoutMfa',
      alarmName: 'no-mfa-signin',
      alarmDescription: 'MAS TRM 12.2 / 9.1 (CIS 4.2): Alert on IAM user console sign-in without MFA',
    });

    // CIS AWS Foundations 4.4: IAM policy changes.
    addSecurityAlarm('IamPolicyChange', {
      filterPattern:
        '{ ($.eventSource = "iam.amazonaws.com") && (' +
        [
          'DeleteGroupPolicy', 'DeleteRolePolicy', 'DeleteUserPolicy',
          'PutGroupPolicy', 'PutRolePolicy', 'PutUserPolicy',
          'CreatePolicy', 'DeletePolicy',
          'CreatePolicyVersion', 'DeletePolicyVersion', 'SetDefaultPolicyVersion',
          'AttachRolePolicy', 'DetachRolePolicy',
          'AttachUserPolicy', 'DetachUserPolicy',
          'AttachGroupPolicy', 'DetachGroupPolicy',
        ].map((name) => `($.eventName = ${name})`).join(' || ') +
        ') }',
      metricName: 'IamPolicyChanges',
      alarmName: 'iam-policy-change',
      alarmDescription: 'MAS TRM 12.2 / 9.2 (CIS 4.4): Alert on IAM policy modifications',
    });

    addSecurityAlarm('SgChange', {
      filterPattern: '{ ($.eventName = AuthorizeSecurityGroupIngress) || ($.eventName = AuthorizeSecurityGroupEgress) || ($.eventName = RevokeSecurityGroupIngress) || ($.eventName = RevokeSecurityGroupEgress) || ($.eventName = CreateSecurityGroup) || ($.eventName = DeleteSecurityGroup) }',
      metricName: 'SecurityGroupChanges',
      alarmName: 'sg-change',
      alarmDescription: 'MAS TRM 12.2 / 11.2: Alert on security group modifications',
    });

    // CIS AWS Foundations 4.3: use of the root user (excluding AWS service events).
    addSecurityAlarm('RootAccountUsage', {
      filterPattern:
        '{ ($.userIdentity.type = "Root") && ($.userIdentity.invokedBy NOT EXISTS) && ($.eventType != "AwsServiceEvent") }',
      metricName: 'RootAccountUsage',
      alarmName: 'root-account-usage',
      alarmDescription: 'MAS TRM 12.2 / 9.2 (CIS 4.3): Alert on root user activity',
    });

    // CIS AWS Foundations 4.5: CloudTrail configuration changes.
    addSecurityAlarm('CloudTrailChange', {
      filterPattern:
        '{ ($.eventName = CreateTrail) || ($.eventName = UpdateTrail) || ($.eventName = DeleteTrail) || ' +
        '($.eventName = StartLogging) || ($.eventName = StopLogging) }',
      metricName: 'CloudTrailConfigChanges',
      alarmName: 'cloudtrail-change',
      alarmDescription: 'MAS TRM 12.2 (CIS 4.5): Alert on CloudTrail configuration changes',
    });

    // CIS AWS Foundations 4.7: customer managed KMS keys disabled or scheduled for deletion.
    addSecurityAlarm('KmsKeyDisableOrDeletion', {
      filterPattern:
        '{ ($.eventSource = "kms.amazonaws.com") && (($.eventName = DisableKey) || ($.eventName = ScheduleKeyDeletion)) }',
      metricName: 'KmsKeyDisableOrScheduledDeletion',
      alarmName: 'kms-key-disable-or-deletion',
      alarmDescription: 'MAS TRM 12.2 / 10.2 (CIS 4.7): Alert when a KMS key is disabled or scheduled for deletion',
    });

    // --- GuardDuty ---
    // One detector per account and region: skip it where GuardDuty is enabled by
    // a delegated administrator (enableGuardDuty: false).
    if (config.enableGuardDuty ?? true) {
      new guardduty.CfnDetector(this, 'GuardDutyDetector', {
        enable: true,
        findingPublishingFrequency: 'FIFTEEN_MINUTES',
      });
    }

    // Route GuardDuty findings to the SNS security topic via EventBridge. This
    // works for a detector created here or one enabled for the organization.
    const guardDutyRule = new events.Rule(this, 'GuardDutyFindingsRule', {
      ruleName: `kiro-banking-guardduty-findings-${config.environment}`,
      description: 'Route GuardDuty findings to SNS security alerts topic',
      eventPattern: {
        source: ['aws.guardduty'],
        detailType: ['GuardDuty Finding'],
      },
    });
    guardDutyRule.addTarget(new events_targets.SnsTopic(this.securityTopic));

    // The EventBridge target above replaces the default topic policy with one
    // that only allows EventBridge, so allow CloudWatch alarms in this account
    // and region explicitly.
    // https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Notify_Users_Alarm_Changes.html
    this.securityTopic.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowCloudWatchAlarmsPublish',
        principals: [new iam.ServicePrincipal('cloudwatch.amazonaws.com')],
        actions: ['sns:Publish'],
        resources: [this.securityTopic.topicArn],
        conditions: {
          StringEquals: { 'aws:SourceAccount': this.account },
          ArnLike: {
            'aws:SourceArn': this.formatArn({
              service: 'cloudwatch',
              resource: 'alarm',
              resourceName: '*',
              arnFormat: cdk.ArnFormat.COLON_RESOURCE_NAME,
            }),
          },
        },
      }),
    );

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
  }
}
