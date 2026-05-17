import * as cdk from 'aws-cdk-lib';
import * as backup from 'aws-cdk-lib/aws-backup';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as events from 'aws-cdk-lib/aws-events';
import { Construct } from 'constructs';
import { NagSuppressions } from 'cdk-nag';
import { KiroBankingConfig } from '../../config/environments';

/**
 * Backup Stack: AWS Backup vault and plan for business continuity.
 *
 * MAS TRM Section 8 (Business Continuity):
 * - Daily automated backups with 35-day retention
 * - Encrypted backup vault with customer-managed KMS key
 * - Supports regulatory data retention requirements
 */
export interface BackupStackProps extends cdk.StackProps {
  readonly config: KiroBankingConfig;
}

export class BackupStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: BackupStackProps) {
    super(scope, id, props);

    const { config } = props;

    // --- KMS Key for Backup Vault Encryption ---
    const backupKey = new kms.Key(this, 'BackupVaultKey', {
      alias: `kiro-banking-backup-key-${config.environment}`,
      description: 'KMS key for encrypting AWS Backup vault (MAS TRM Section 8)',
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
      scheduleExpression: events.Schedule.expression('cron(0 5 * * ? *)'),
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
    NagSuppressions.addResourceSuppressions(backupKey, [
      { id: 'AwsSolutions-KMS5', reason: 'Key rotation is enabled via enableKeyRotation property' },
    ]);

    NagSuppressions.addResourceSuppressions(plan, [
      {
        id: 'AwsSolutions-IAM4',
        reason: 'AWS Backup service role requires AWS managed policy AWSBackupServiceRolePolicyForBackup to function correctly',
        appliesTo: ['Policy::arn:<AWS::Partition>:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup'],
      },
    ], true);
  }
}
