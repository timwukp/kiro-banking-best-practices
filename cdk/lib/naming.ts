/**
 * Physical names that more than one stack needs to know.
 *
 * Do not change these values for an existing environment: a new name replaces
 * the deployed resource.
 */

/** Name of the CloudTrail trail in MonitoringStack (referenced by the AuditKey policy). */
export function auditTrailName(environment: string): string {
  return `kiro-banking-audit-${environment}`;
}
