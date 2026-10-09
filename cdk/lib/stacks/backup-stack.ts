import * as cdk from 'aws-cdk-lib';
import * as backup from 'aws-cdk-lib/aws-backup';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as events from 'aws-cdk-lib/aws-events';
import { Construct } from 'constructs';
import { NagSuppressions } from 'cdk-nag';
import { DEFAULT_BACKUP_SCHEDULE_CRON, KiroBankingConfig } from '../../config/environments';

/**
 * Backup Stack: AWS Backup vault and plan for system backup and recovery.
 *
 * MAS TRM Section 8 (IT Resilience), 8.4 (System Backup and Recovery):
 * - Daily automated backups with 35-day retention, scheduled by
 *   backupScheduleCron (UTC; default 18:00 UTC = 02:00 Singapore time)
 * - Encrypted backup vault with customer-managed KMS key (TRM 10.2)
 * - Supports regulatory data retention requirements
 */
export interface BackupStackProps extends cdk.StackProps {
  readonly config: KiroBankingConfig;
}

export class BackupStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: BackupStackProps) {
    super(scope, id, props);

    const { config } = props;

    // AWS Backup cron expressions are evaluated in UTC.
    const scheduleCron = config.backupScheduleCron ?? DEFAULT_BACKUP_SCHEDULE_CRON;
    if (!/^cron\(\S+( \S+){5}\)$/.test(scheduleCron)) {
      throw new Error(`backupScheduleCron must be an AWS cron expression with six fields, e.g. ${DEFAULT_BACKUP_SCHEDULE_CRON}; got '${scheduleCron}'`);
    }

    // --- KMS Key for Backup Vault Encryption ---
    const backupKey = new kms.Key(this, 'BackupVaultKey', {
      alias: `kiro-banking-backup-key-${config.environment}`,
      description: 'KMS key for encrypting AWS Backup vault (MAS TRM 8.4, 10.2)',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // --- Backup Vault ---
    const vault = new backup.BackupVault(this, 'BackupVault', {
      backupVaultName: `kiro-banking-vault-${config.environment}`,
      encryptionKey: backupKey,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // --- Backup Plan ---
    const plan = new backup.BackupPlan(this, 'BackupPlan', {
      backupPlanName: `kiro-banking-daily-${config.environment}`,
    });

    plan.addRule(new backup.BackupPlanRule({
      ruleName: 'DailyBackup',
      backupVault: vault,
      scheduleExpression: events.Schedule.expression(scheduleCron),
      deleteAfter: cdk.Duration.days(35),
      startWindow: cdk.Duration.hours(1),
      completionWindow: cdk.Duration.hours(2),
    }));

    plan.addSelection('TaggedResources', {
      resources: [backup.BackupResource.fromTag('Backup', 'daily')],
    });

    // --- Outputs ---
    new cdk.CfnOutput(this, 'BackupVaultName', {
      value: vault.backupVaultName,
      description: 'AWS Backup vault name',
    });

    new cdk.CfnOutput(this, 'BackupPlanId', {
      value: plan.backupPlanId,
      description: 'AWS Backup plan ID',
    });

    // CDK Nag suppressions
    NagSuppressions.addResourceSuppressions(plan, [
      {
        id: 'AwsSolutions-IAM4',
        reason: 'AWS Backup service role requires AWS managed policy AWSBackupServiceRolePolicyForBackup to function correctly',
        appliesTo: ['Policy::arn:<AWS::Partition>:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup'],
      },
    ], true);
  }
}
