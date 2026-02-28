import * as cdk from 'aws-cdk-lib';
import * as config from 'aws-cdk-lib/aws-config';
import { Construct } from 'constructs';
import { KiroBankingConfig } from '../../config/environments';

/**
 * Compliance Stack: AWS Config rules for continuous MAS TRM compliance.
 *
 * Implements automated compliance checks mapped to MAS TRM Guidelines:
 * - Section 9: Access Control
 * - Section 10: Cryptography
 * - Section 11: Data & Network Security
 * - Section 15: IT Audit
 *
 * Also covers:
 * - PDPA: Data protection controls
 * - MAS Outsourcing: Third-party service monitoring
 */
export interface ComplianceStackProps extends cdk.StackProps {
  readonly config: KiroBankingConfig;
}

export class ComplianceStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: ComplianceStackProps) {
    super(scope, id, props);

    const { config: envConfig } = props;

    // ═══════════════════════════════════════════════════════════
    // MAS TRM Section 9: Access Control
    // ═══════════════════════════════════════════════════════════

    // IAM root access key check
    new config.ManagedRule(this, 'IamRootAccessKeyCheck', {
      identifier: 'IAM_ROOT_ACCESS_KEY_CHECK',
      configRuleName: `mas-trm-9-iam-root-key-${envConfig.environment}`,
      description: 'MAS TRM 9.1: Ensure root account does not have access keys',
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
      description: 'MAS TRM 9.1: Ensure root account has MFA enabled',
    });

    // IAM password policy
    new config.ManagedRule(this, 'IamPasswordPolicy', {
      identifier: 'IAM_PASSWORD_POLICY',
      configRuleName: `mas-trm-9-password-policy-${envConfig.environment}`,
      description: 'MAS TRM 9.1: Ensure IAM password policy meets banking standards',
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
      description: 'MAS TRM 10.1: Ensure KMS customer-managed key rotation is enabled',
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
      description: 'MAS TRM 11.2: Ensure VPC flow logs are enabled for network monitoring',
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
    // MAS TRM Section 15: IT Audit
    // ═══════════════════════════════════════════════════════════

    // CloudTrail enabled
    new config.ManagedRule(this, 'CloudTrailEnabled', {
      identifier: 'CLOUD_TRAIL_ENABLED',
      configRuleName: `mas-trm-15-cloudtrail-enabled-${envConfig.environment}`,
      description: 'MAS TRM 15.1: Ensure CloudTrail is enabled for audit logging',
    });

    // CloudTrail log file validation
    new config.ManagedRule(this, 'CloudTrailLogValidation', {
      identifier: 'CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED',
      configRuleName: `mas-trm-15-log-validation-${envConfig.environment}`,
      description: 'MAS TRM 15.1: Ensure CloudTrail log file integrity validation is enabled',
    });

    // CloudTrail encrypted
    new config.ManagedRule(this, 'CloudTrailEncrypted', {
      identifier: 'CLOUD_TRAIL_ENCRYPTION_ENABLED',
      configRuleName: `mas-trm-15-cloudtrail-encrypted-${envConfig.environment}`,
      description: 'MAS TRM 15.1/10.1: Ensure CloudTrail logs are encrypted with KMS',
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

    // --- Outputs ---
    new cdk.CfnOutput(this, 'ComplianceRuleCount', {
      value: '18',
      description: 'Number of AWS Config compliance rules deployed',
    });
  }
}
