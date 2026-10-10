#!/usr/bin/env bash
# verify-deploy.sh - verifies a REAL deployment of the CDK app (env=dev) in a sandbox account.
#
#   IT_REGION=ap-southeast-1 bash verify-deploy.sh [env]         # env defaults to dev
#
# Resources are discovered through CloudFormation (no hard-coded IDs). Emits
# "CHECK <id> PASS|FAIL|SKIP <detail>" lines and a final "PHASE C1 RESULT ..." line.
# Read-only except: CloudWatch alarm states are toggled (OK -> ALARM -> OK) to prove that
# alarm actions are delivered to the KMS-encrypted SNS topic, and an on-demand Config
# rule evaluation is started.

set -u
ENVN="${1:-dev}"; R="${IT_REGION:-ap-southeast-1}"
PASS=0; FAIL=0; SKIP=0
check() { echo "CHECK $1 $2 ${3:-}"; case "$2" in PASS) PASS=$((PASS+1));; FAIL) FAIL=$((FAIL+1));; *) SKIP=$((SKIP+1));; esac; }
aws_() { aws --region "$R" --output json "$@"; }
res() { # stack type [logical-id-substring] -> physical ids (one per line)
  aws_ cloudformation describe-stack-resources --stack-name "$1" \
    | jq -r --arg t "$2" --arg l "${3:-}" '.StackResources[] | select(.ResourceType == $t and (.LogicalResourceId | contains($l))) | .PhysicalResourceId'
}
S_ENC="KiroBanking-Encryption-$ENVN"; S_NET="KiroBanking-Network-$ENVN"; S_MON="KiroBanking-Monitoring-$ENVN"
S_CMP="KiroBanking-Compliance-$ENVN"; S_BAK="KiroBanking-Backup-$ENVN"

# --- stacks
for s in "$S_ENC" "$S_NET" "$S_MON" "$S_CMP" "$S_BAK"; do
  st="$(aws_ cloudformation describe-stacks --stack-name "$s" --query 'Stacks[0].StackStatus' --output text 2>/dev/null)"
  case "$st" in CREATE_COMPLETE|UPDATE_COMPLETE) check "C1.stack[$s]" PASS "$st" ;; *) check "C1.stack[$s]" FAIL "${st:-missing}" ;; esac
done

# --- KMS rotation (all customer-managed keys in our stacks)
for s in "$S_ENC" "$S_NET" "$S_BAK" "$S_CMP"; do
  for k in $(res "$s" AWS::KMS::Key); do
    rot="$(aws_ kms get-key-rotation-status --key-id "$k" --query KeyRotationEnabled --output text 2>/dev/null)"
    [ "$rot" = True ] && check "C1.kms-rotation[$s]" PASS || check "C1.kms-rotation[$s]" FAIL "rotation=$rot"
  done
done

# --- network: endpoints, NACL association, WorkSpaces SG egress, flow logs
VPC="$(res "$S_NET" AWS::EC2::VPC | head -1)"
eps="$(aws_ ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC" --query 'VpcEndpoints[].State' | jq -r '.[]' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
bad="$(aws_ ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC" --query 'VpcEndpoints[?State!=`available`].ServiceName' | jq 'length')"
[ "$bad" = 0 ] && [ -n "$eps" ] && check C1.vpc-endpoints-available PASS "$eps" || check C1.vpc-endpoints-available FAIL "$eps"
NACL="$(res "$S_NET" AWS::EC2::NetworkAcl EndpointNacl | head -1)"
nacl_subnets="$(aws_ ec2 describe-network-acls --network-acl-ids "$NACL" --query 'NetworkAcls[0].Associations[].SubnetId' | jq -r '.[]' | sort | tr '\n' ' ')"
ep_subnets="$(aws_ ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" "Name=tag:aws-cdk:subnet-name,Values=Endpoints" --query 'Subnets[].SubnetId' | jq -r '.[]' | sort | tr '\n' ' ')"
[ -n "$ep_subnets" ] && [ "$nacl_subnets" = "$ep_subnets" ] && check C1.nacl-associated PASS "Endpoints subnets" || check C1.nacl-associated FAIL "nacl=[$nacl_subnets] endpoints=[$ep_subnets]"
WSG="$(aws_ cloudformation describe-stack-resources --stack-name "$S_NET" | jq -r '.StackResources[] | select(.ResourceType=="AWS::EC2::SecurityGroup" and (.LogicalResourceId|test("Workspaces";"i"))) | .PhysicalResourceId' | head -1)"
MODE="$(aws_ ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC" "Name=state,Values=available" --query 'length(NatGateways)')"
allall="$(aws_ ec2 describe-security-group-rules --filters "Name=group-id,Values=$WSG" --query 'SecurityGroupRules[?IsEgress && IpProtocol==`-1` && CidrIpv4==`0.0.0.0/0`]' | jq 'length')"
[ "$allall" = 0 ] && check C1.workspaces-sg-no-allow-all-egress PASS "nat-gateways=$MODE" || check C1.workspaces-sg-no-allow-all-egress FAIL "allow-all egress rules=$allall"
fl="$(aws_ ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC" --query 'FlowLogs[0]')"
fl_status="$(echo "$fl" | jq -r '.FlowLogStatus + "/" + (.DeliverLogsStatus // "")')"
fl_group="$(echo "$fl" | jq -r '.LogGroupName // empty')"
[ "$fl_status" = "ACTIVE/SUCCESS" ] && check C1.flow-log-active PASS "$fl_status" || check C1.flow-log-active FAIL "$fl_status $(echo "$fl" | jq -r '.DeliverLogsErrorMessage // ""')"
if [ -n "$fl_group" ]; then
  kms="$(aws_ logs describe-log-groups --log-group-name-prefix "$fl_group" --query 'logGroups[0].kmsKeyId' --output text)"
  [ -n "$kms" ] && [ "$kms" != None ] && check C1.flow-log-cmk PASS || check C1.flow-log-cmk FAIL "log group not KMS-encrypted"
else check C1.flow-log-cmk FAIL "no flow log group"; fi

# --- CloudTrail delivery
TRAIL="$(res "$S_MON" AWS::CloudTrail::Trail | head -1)"
ts="$(aws_ cloudtrail get-trail-status --name "$TRAIL")"
[ "$(echo "$ts" | jq -r .IsLogging)" = true ] && check C1.cloudtrail-logging PASS || check C1.cloudtrail-logging FAIL "IsLogging=false"
for k in LatestDeliveryError LatestCloudWatchLogsDeliveryError LatestDigestDeliveryError; do
  e="$(echo "$ts" | jq -r --arg k "$k" '.[$k] // empty')"
  [ -z "$e" ] && check "C1.cloudtrail-no-$k" PASS || check "C1.cloudtrail-no-$k" FAIL "$e"
done
[ -n "$(echo "$ts" | jq -r '.LatestDeliveryTime // empty')" ] && check C1.cloudtrail-delivered-s3 PASS || check C1.cloudtrail-delivered-s3 FAIL "no S3 delivery yet"
[ -n "$(echo "$ts" | jq -r '.LatestCloudWatchLogsDeliveryTime // empty')" ] && check C1.cloudtrail-delivered-cwl PASS || check C1.cloudtrail-delivered-cwl FAIL "no CloudWatch Logs delivery yet"

# --- audit bucket: Object Lock default retention, versioning, PAB, encryption, noncurrent expiration
AUDIT="$(aws_ cloudformation describe-stack-resources --stack-name "$S_MON" | jq -r '.StackResources[] | select(.ResourceType=="AWS::S3::Bucket" and (.LogicalResourceId|test("Audit";"i"))) | .PhysicalResourceId' | head -1)"
ol="$(aws_ s3api get-object-lock-configuration --bucket "$AUDIT" 2>/dev/null | jq -r '.ObjectLockConfiguration.Rule.DefaultRetention | "\(.Mode) \(.Days)"')"
case "$ol" in "GOVERNANCE "[0-9]*) check C1.audit-object-lock PASS "$ol" ;; *) check C1.audit-object-lock FAIL "${ol:-none}" ;; esac
[ "$(aws_ s3api get-bucket-versioning --bucket "$AUDIT" --query Status --output text)" = Enabled ] && check C1.audit-versioning PASS || check C1.audit-versioning FAIL
pab="$(aws_ s3api get-public-access-block --bucket "$AUDIT" --query 'PublicAccessBlockConfiguration' | jq '[.[]] | all')"
[ "$pab" = true ] && check C1.audit-public-access-block PASS || check C1.audit-public-access-block FAIL
enc="$(aws_ s3api get-bucket-encryption --bucket "$AUDIT" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)"
[ "$enc" = "aws:kms" ] && check C1.audit-sse-kms PASS || check C1.audit-sse-kms FAIL "$enc"
nve="$(aws_ s3api get-bucket-lifecycle-configuration --bucket "$AUDIT" | jq '[.Rules[] | select(.NoncurrentVersionExpiration != null)] | length')"
[ "${nve:-0}" -ge 1 ] && check C1.audit-noncurrent-expiration PASS || check C1.audit-noncurrent-expiration FAIL

# --- alarm delivery to the KMS-encrypted SNS topic
for a in $(res "$S_MON" AWS::CloudWatch::Alarm); do
  # An alarm that real activity has already put into ALARM would not transition (and so not
  # fire its action) on set-alarm-state ALARM; force OK first so the check always sees a fresh
  # OK -> ALARM transition.
  prior="$(aws_ cloudwatch describe-alarms --alarm-names "$a" --query 'MetricAlarms[0].StateValue' --output text)"
  aws_ cloudwatch set-alarm-state --alarm-name "$a" --state-value OK --state-reason "kiro-fsi-test: reset before delivery check" >/dev/null
  sleep 5
  start="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  aws_ cloudwatch set-alarm-state --alarm-name "$a" --state-value ALARM --state-reason "kiro-fsi-test: alarm action delivery check" >/dev/null
  ok=""
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 10
    h="$(aws_ cloudwatch describe-alarm-history --alarm-name "$a" --history-item-type Action --start-date "$start" --query 'AlarmHistoryItems[].HistorySummary' | jq -r '.[]')"
    if echo "$h" | grep -q 'Successfully executed action'; then ok=1; break; fi
    if echo "$h" | grep -q 'Failed to execute action'; then break; fi
  done
  aws_ cloudwatch set-alarm-state --alarm-name "$a" --state-value OK --state-reason "kiro-fsi-test: reset" >/dev/null
  [ -n "$ok" ] && check "C1.alarm-action-delivered[$a]" PASS "prior-state=$prior" || check "C1.alarm-action-delivered[$a]" FAIL "prior-state=$prior $(echo "$h" | head -2 | tr '\n' ' ')"
done

# --- AWS Config rules
rules="$(res "$S_CMP" AWS::Config::ConfigRule)"
n="$(echo "$rules" | grep -c . || true)"
[ "$n" = 19 ] && check C1.config-rules-19 PASS || check C1.config-rules-19 FAIL "count=$n"
recording="$(aws_ configservice describe-configuration-recorder-status --query 'ConfigurationRecordersStatus[0].recording' --output text 2>/dev/null)"
if [ "$recording" = True ]; then
  # shellcheck disable=SC2086
  aws_ configservice start-config-rules-evaluation --config-rule-names $(echo "$rules" | head -25 | tr '\n' ' ') >/dev/null 2>&1 || true
  sleep 90
  # shellcheck disable=SC2086
  status="$(aws_ configservice describe-config-rule-evaluation-status --config-rule-names $(echo "$rules" | tr '\n' ' '))"
  errs="$(echo "$status" | jq -r '.ConfigRulesEvaluationStatus[] | select(.LastErrorCode != null) | "\(.ConfigRuleName):\(.LastErrorCode)"' | tr '\n' ' ')"
  # A rule that has not started is acceptable only if it is explicitly scoped and the account
  # holds no resources of the scoped types (nothing to evaluate); anything else fails.
  na=""
  for r in $(echo "$status" | jq -r '.ConfigRulesEvaluationStatus[] | select(.LastErrorCode == null and .FirstEvaluationStarted != true) | .ConfigRuleName'); do
    types="$(aws_ configservice describe-config-rules --config-rule-names "$r" --query 'ConfigRules[0].Scope.ComplianceResourceTypes' | jq -r '.[]?')"
    [ -n "$types" ] || { errs="$errs $r:not-started-unscoped"; continue; }
    total=0
    for t in $types; do
      case "$t" in
        AWS::RDS::DBInstance) c="$(aws_ rds describe-db-instances --query 'length(DBInstances)')" ;;
        *) c="$(aws_ configservice list-discovered-resources --resource-type "$t" --query 'length(resourceIdentifiers)')" ;;
      esac
      total=$((total + ${c:-1}))
    done
    if [ "$total" = 0 ]; then na="$na $r"; else errs="$errs $r:not-started($total-in-scope)"; fi
  done
  [ -z "$errs" ] && check C1.config-rules-evaluate PASS "${na:+not-applicable(0 in-scope resources):$na}" || check C1.config-rules-evaluate FAIL "$errs"
else
  check C1.config-rules-evaluate SKIP "no active configuration recorder in $R"
fi

# --- backup schedule
PLAN="$(res "$S_BAK" AWS::Backup::BackupPlan | head -1)"
cron="$(aws_ backup get-backup-plan --backup-plan-id "${PLAN%%|*}" --query 'BackupPlan.Rules[0].ScheduleExpression' --output text 2>/dev/null)"
[ "$cron" = "cron(0 18 * * ? *)" ] && check C1.backup-schedule PASS "$cron" || check C1.backup-schedule FAIL "$cron"

echo "PHASE C1 RESULT pass=$PASS fail=$FAIL skip=$SKIP"
[ "$FAIL" -eq 0 ]
