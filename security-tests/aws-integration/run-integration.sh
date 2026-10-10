#!/usr/bin/env bash
# run-integration.sh - orchestrates the isolated AWS integration test (SANDBOX ACCOUNT ONLY).
#
#   bash security-tests/aws-integration/run-integration.sh <stage> [<stage> ...]
#
# Stages (idempotent; run in this order, or use "all"):
#   preflight   read-only: identity, region, account singletons, CDK bootstrap -> state file
#   up          deploy harness.yaml (isolated VPC, SSM-only Linux + Windows runners, results bucket)
#   bundle      upload the current working tree (tracked + untracked, not ignored) to the results bucket
#   linux       run L1 (CI parity), L2 (root MDM), L3 (chaos) on the Linux runner
#   linux:<P>   run a single Linux phase (setup, L1, L2, L3) after fixing a failure
#   windows     run W1 on the Windows runner
#   deploy      cdk bootstrap (if missing) + offline cdk synth + CloudFormation deploy of all 5 stacks
#               (env=dev, singleton flags from preflight)
#   verify      verify-deploy.sh against the deployed stacks (C1)
#   egress      redeploy with egress=nat-dns-firewall + launch the probe; run C2 (probe) and K1/K2 (kiro)
#   down        delete probe, cdk destroy, clean RETAIN leftovers, remove bootstrap if we created it,
#               empty + delete the harness
#   leftovers   scan for anything left behind (expects only KMS keys pending deletion)
#
# Environment: IT_REGION (default ap-southeast-1; an inherited AWS_REGION is ignored), AWS_PROFILE (optional),
#              IT_WORKDIR (default $TMPDIR/kiro-fsi-it) for state and logs (never committed).
# Exit code: non-zero if any stage reports a failure.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
# Use IT_REGION, not an inherited AWS_REGION (shells for AI assistants or Bedrock often export one).
export AWS_REGION="${IT_REGION:-ap-southeast-1}"; export AWS_DEFAULT_REGION="$AWS_REGION"; R="$AWS_REGION"
export CDK_DISABLE_CLI_TELEMETRY=true
W="${IT_WORKDIR:-${TMPDIR:-/tmp}/kiro-fsi-it}"; mkdir -p "$W/logs"
STATE="$W/state.env"; [ -f "$STATE" ] && . "$STATE"
HARNESS=kiro-fsi-test-harness; PROBE=kiro-fsi-test-probe; ENVN=dev
STACKS="KiroBanking-Encryption-$ENVN KiroBanking-Network-$ENVN KiroBanking-Monitoring-$ENVN KiroBanking-Compliance-$ENVN KiroBanking-Backup-$ENVN"
RC=0
log() { echo "[$(date -u +%H:%M:%S)] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
save() { # key value
  touch "$STATE"; grep -v "^$1=" "$STATE" > "$STATE.tmp" 2>/dev/null || true; mv "$STATE.tmp" "$STATE"
  printf '%s=%q\n' "$1" "$2" >> "$STATE"; eval "$1=\$2"
}
aws_() { aws --region "$R" --output json "$@"; }
out() { aws_ cloudformation describe-stacks --stack-name "$1" --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text; }
mask() { sed -E 's/[0-9]{12}/<account>/g; s/i-[0-9a-f]{8,17}/<instance>/g; s/(vpc|subnet|sg|acl|vpce|nat|igw|rtb|fl|eni|eipalloc|vol)-[0-9a-f]{8,17}/\1-<id>/g; s/[0-9]{1,3}(\.[0-9]{1,3}){3}/<ip>/g'; }

# --------------------------------------------------------------------- helpers: SSM
wait_ssm_online() { # instance-id
  for _ in $(seq 1 60); do
    st="$(aws_ ssm describe-instance-information --filters "Key=InstanceIds,Values=$1" --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null)"
    [ "$st" = Online ] && { log "SSM online: $1"; return 0; }
    sleep 10
  done
  die "instance $1 never came online in SSM"
}
ssm_run() { # instance-id document label command-string timeout-seconds
  local iid="$1" doc="$2" label="$3" cmd="$4" to="${5:-3600}" cid st
  local params; params="$(jq -cn --arg c "$cmd" --arg t "$to" '{commands: [$c], executionTimeout: [$t]}')"
  cid="$(aws_ ssm send-command --instance-ids "$iid" --document-name "$doc" --parameters "$params" \
        --timeout-seconds 600 --comment "kiro-fsi-test $label" \
        --output-s3-bucket-name "$BUCKET" --output-s3-key-prefix "ssm/$label" --query Command.CommandId --output text)" \
        || die "send-command failed for $label"
  log "SSM $label: command $cid"
  while :; do
    sleep 20
    st="$(aws_ ssm get-command-invocation --command-id "$cid" --instance-id "$iid" --query Status --output text 2>/dev/null)"
    case "$st" in Pending|InProgress|Delayed|"") continue ;; *) break ;; esac
  done
  # One directory per command: re-runs of a label must not mix earlier outputs into the summary.
  mkdir -p "$W/logs/$label/$cid"
  aws_ s3 cp --recursive --only-show-errors "s3://$BUCKET/ssm/$label/$cid/" "$W/logs/$label/$cid/" || true
  find "$W/logs/$label/$cid" -name stdout -exec cat {} + > "$W/logs/$label.stdout" 2>/dev/null
  find "$W/logs/$label/$cid" -name stderr -exec cat {} + > "$W/logs/$label.stderr" 2>/dev/null
  echo "$cid" > "$W/logs/$label.command-id"
  log "SSM $label: status=$st"
  grep -E '^(CHECK .* (FAIL|SKIP)|PHASE )' "$W/logs/$label.stdout" | mask || true
  [ "$st" = Success ]
}
linux_cmd() { # phase
  cat <<EOF
set -e
mkdir -p /opt/kiro-test && cd /opt/kiro-test && rm -rf repo && mkdir repo
aws s3 cp --only-show-errors --region $R s3://$BUCKET/bundle/repo.tgz repo.tgz
tar -xzf repo.tgz -C repo
set +e
bash repo/security-tests/aws-integration/linux-suite.sh $1 /opt/kiro-test/repo
EOF
}
windows_cmd() {
  cat <<EOF
\$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force C:\\kiro-test | Out-Null
if (Test-Path C:\\kiro-test\\repo) { Remove-Item C:\\kiro-test\\repo -Recurse -Force }
New-Item -ItemType Directory C:\\kiro-test\\repo | Out-Null
Read-S3Object -BucketName $BUCKET -Key bundle/repo.tgz -File C:\\kiro-test\\repo.tgz -Region $R | Out-Null
tar.exe -xzf C:\\kiro-test\\repo.tgz -C C:\\kiro-test\\repo
\$ErrorActionPreference = 'Continue'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\kiro-test\\repo\\security-tests\\aws-integration\\windows-suite.ps1 -RepoDir C:\\kiro-test\\repo
exit \$LASTEXITCODE
EOF
}

# --------------------------------------------------------------------- stages
st_preflight() {
  local id; id="$(aws_ sts get-caller-identity)" || die "no AWS credentials / network"
  save ACCOUNT "$(echo "$id" | jq -r .Account)"
  log "identity: $(echo "$id" | jq -r .Arn | mask) region=$R"
  aws_ guardduty list-detectors --query 'DetectorIds' | jq -e 'length > 0' >/dev/null && save HAS_GD true || save HAS_GD false
  aws_ securityhub describe-hub >/dev/null 2>&1 && save HAS_SH true || save HAS_SH false
  aws_ accessanalyzer list-analyzers --type ACCOUNT --query 'analyzers' | jq -e 'length > 0' >/dev/null && save HAS_AA true || save HAS_AA false
  aws_ configservice describe-configuration-recorders --query 'ConfigurationRecorders' | jq -e 'length > 0' >/dev/null && save HAS_REC true || save HAS_REC false
  aws_ cloudformation describe-stacks --stack-name CDKToolkit >/dev/null 2>&1 && save HAS_BOOT true || save HAS_BOOT false
  org="$(aws organizations describe-organization --query Organization.Id --output text 2>/dev/null || echo none)"
  log "singletons: guardduty=$HAS_GD securityhub=$HAS_SH access-analyzer=$HAS_AA config-recorder=$HAS_REC cdk-bootstrap=$HAS_BOOT organization=$( [ "$org" = none ] && echo none || echo member)"
  for s in $STACKS $HARNESS $PROBE; do
    st="$(aws_ cloudformation describe-stacks --stack-name "$s" --query 'Stacks[0].StackStatus' --output text 2>/dev/null)"
    [ -n "$st" ] && log "existing stack $s: $st"
  done
}
st_up() {
  aws_ cloudformation deploy --stack-name "$HARNESS" --template-file "$HERE/harness.yaml" \
    --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset --tags Project=kiro-fsi-test || die "harness deploy failed"
  save BUCKET "$(out "$HARNESS" ResultsBucketName)"; save LINUX_ID "$(out "$HARNESS" LinuxInstanceId)"
  save WIN_ID "$(out "$HARNESS" WindowsInstanceId)"; save PROFILE_NAME "$(out "$HARNESS" RunnerProfileName)"
  wait_ssm_online "$LINUX_ID"; [ -n "${WIN_ID:-}" ] && [ "$WIN_ID" != None ] && wait_ssm_online "$WIN_ID"
}
st_bundle() {
  # COPYFILE_DISABLE / --no-mac-metadata: macOS tar would otherwise add AppleDouble "._<file>" entries
  # for extended attributes, which the hook-manifest checks rightly reject as unsafe file names.
  # Stage a copy so cdk/cdk.context.json always comes from git HEAD: a concurrent `cdk deploy` adds
  # real-account lookups to the working copy until it restores the file.
  rm -rf "$W/stage" && mkdir -p "$W/stage"
  ( cd "$REPO" && git ls-files -co --exclude-standard -z | COPYFILE_DISABLE=1 tar --null -cf - -T - ) | ( cd "$W/stage" && tar -xf - ) \
    || die "bundle staging failed"
  ( cd "$REPO" && git show HEAD:cdk/cdk.context.json ) > "$W/stage/cdk/cdk.context.json" || die "cannot read cdk.context.json from HEAD"
  ( cd "$W/stage" && COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs -czf "$W/repo.tgz" . ) 2>/dev/null \
    || ( cd "$W/stage" && COPYFILE_DISABLE=1 tar -czf "$W/repo.tgz" . ) || die "bundle failed"
  if tar -tzf "$W/repo.tgz" | grep -q -E '(^|/)\._'; then die "bundle contains AppleDouble ._ files"; fi
  aws_ s3 cp --only-show-errors "$W/repo.tgz" "s3://$BUCKET/bundle/repo.tgz" || die "bundle upload failed"
  log "bundle uploaded ($(du -h "$W/repo.tgz" | cut -f1))"
}
st_linux() {
  ssm_run "$LINUX_ID" AWS-RunShellScript linux-setup "$(linux_cmd setup)" 1200 || RC=1
  for p in L1 L2 L3; do ssm_run "$LINUX_ID" AWS-RunShellScript "linux-$p" "$(linux_cmd "$p")" 3600 || RC=1; done
}
st_windows() {
  [ -n "${WIN_ID:-}" ] && [ "$WIN_ID" != None ] || { log "no Windows runner"; return; }
  ssm_run "$WIN_ID" AWS-RunPowerShellScript windows-W1 "$(windows_cmd)" 3600 || RC=1
}
cdk_flags() {
  local f="-c env=$ENVN"
  [ "${HAS_GD:-false}" = true ] && f="$f -c enableGuardDuty=false"
  [ "${HAS_SH:-false}" = true ] && f="$f -c enableSecurityHub=false"
  [ "${HAS_AA:-false}" = true ] && f="$f -c enableAccessAnalyzer=false"
  [ "${HAS_REC:-false}" = true ] || f="$f -c createConfigRecorder=true"
  echo "$f"
}
cdk_() { # args...
  ( cd "$REPO/cdk" && cp cdk.context.json "$W/cdk.context.json.bak" \
    && CDK_DEFAULT_ACCOUNT="$ACCOUNT" CDK_DEFAULT_REGION="$R" npx cdk "$@" --no-notices; rc=$?; \
    cp "$W/cdk.context.json.bak" cdk.context.json; exit $rc )   # never keep real-account lookups
}
# Makes the KiroBanking stacks safe to redeploy after an interrupted CLI run: waits for in-progress
# operations to finish and removes empty REVIEW_IN_PROGRESS / ROLLBACK_COMPLETE stacks.
settle_stacks() {
  local s st
  for s in $STACKS; do
    for _ in $(seq 1 90); do
      st="$(aws_ cloudformation describe-stacks --stack-name "$s" --query 'Stacks[0].StackStatus' --output text 2>/dev/null)"
      case "$st" in *_IN_PROGRESS) [ "$st" = REVIEW_IN_PROGRESS ] && break; sleep 20 ;; *) break ;; esac
    done
    case "$st" in
      REVIEW_IN_PROGRESS|ROLLBACK_COMPLETE|CREATE_FAILED)
        log "removing $s ($st) before retrying"
        aws_ cloudformation delete-stack --stack-name "$s" && aws_ cloudformation wait stack-delete-complete --stack-name "$s" ;;
    esac
  done
}
# Synthesizes the CDK app OFFLINE for the real account: the real availability zones are read with the
# AWS CLI and injected into cdk.context.json for this run only (restored afterwards, so real-account
# lookups are never committed). Credentials are hidden from the CDK CLI, so it makes no AWS calls.
synth_real() { # out-dir cdk-args...
  local out="$1"; shift; local azs rc
  azs="$(aws_ ec2 describe-availability-zones --filters Name=state,Values=available Name=zone-type,Values=availability-zone \
          --query 'AvailabilityZones[].ZoneName' | jq -c 'sort')" || return 1
  ( cd "$REPO/cdk" && cp cdk.context.json "$W/cdk.context.json.bak" \
    && jq --arg k "availability-zones:account=$ACCOUNT:region=$R" --argjson v "$azs" '.[$k] = $v' "$W/cdk.context.json.bak" > cdk.context.json \
    && rm -rf "$out" \
    && env -u AWS_PROFILE -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
         AWS_SHARED_CREDENTIALS_FILE=/dev/null AWS_CONFIG_FILE=/dev/null AWS_EC2_METADATA_DISABLED=true \
         CDK_DEFAULT_ACCOUNT="$ACCOUNT" CDK_DEFAULT_REGION="$R" npx cdk synth --quiet --no-notices "$@" -o "$out"; rc=$?; \
    cp "$W/cdk.context.json.bak" cdk.context.json; exit $rc )
}
# Deploys the synthesized assembly with the AWS CLI (CloudFormation), in dependency order, through the
# CDK bootstrap bucket and CloudFormation execution role - the same role `cdk deploy` uses. Used instead
# of `cdk deploy` because the CDK CLI's Node.js HTTP connections were repeatedly dropped ("aborted")
# by an intermediate egress proxy; the Python AWS CLI is not affected. The assembly has no Lambda or
# Docker assets, so publishing the templates is all `cdk deploy` would add.
cfn_deploy_all() { # name cdk-args...
  local name="$1"; shift; local out="$W/cdk.out.$name" s tags
  local bucket="cdk-hnb659fds-assets-$ACCOUNT-$R" role="arn:aws:iam::$ACCOUNT:role/cdk-hnb659fds-cfn-exec-role-$ACCOUNT-$R"
  synth_real "$out" "$@" > "$W/logs/synth-$name.log" 2>&1 || { grep -v 'trust settings' "$W/logs/synth-$name.log" | tail -20 | mask; die "synth failed"; }
  # Only template files may be assets here (no Lambda zips or Docker images to publish).
  jq -s -e '([.[].dockerImages // {} | length] | add) == 0 and ([.[].files // {} | .[] | .source.path | endswith(".template.json")] | all)' \
    "$out"/*.assets.json >/dev/null || die "assembly has non-template assets; use cdk deploy to publish them"
  settle_stacks
  for s in $STACKS; do
    # shellcheck disable=SC2207
    tags=($(jq -r --arg s "$s" '.artifacts[$s].properties.tags // {} | to_entries[] | "\(.key)=\(.value)"' "$out/manifest.json"))
    log "deploying $s"
    if ! aws_ cloudformation deploy --stack-name "$s" --template-file "$out/$s.template.json" \
          --s3-bucket "$bucket" --s3-prefix kiro-fsi-test --role-arn "$role" \
          --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM --no-fail-on-empty-changeset \
          ${tags[@]:+--tags "${tags[@]}"} >> "$W/logs/cfn-$name.log" 2>&1; then
      aws_ cloudformation describe-stack-events --stack-name "$s" --max-items 40 \
        --query 'StackEvents[?contains(ResourceStatus, `FAILED`)].[LogicalResourceId,ResourceStatusReason]' --output text | mask | head -10
      die "deploy of $s failed"
    fi
  done
  log "all stacks deployed ($name)"
}
st_deploy() {
  if [ "${HAS_BOOT:-false}" != true ]; then
    cdk_ bootstrap "aws://$ACCOUNT/$R" || die "bootstrap failed"; save WE_BOOTSTRAPPED true
  fi
  # shellcheck disable=SC2046
  cfn_deploy_all default $(cdk_flags)
}
st_verify() {
  # First CloudTrail / flow-log deliveries take a few minutes after a fresh deploy; re-runs
  # against long-lived stacks can shorten the wait with IT_VERIFY_WAIT=<seconds>.
  local wait="${IT_VERIFY_WAIT:-360}"
  log "waiting ${wait}s for first CloudTrail / flow-log deliveries"; sleep "$wait"
  bash "$HERE/verify-deploy.sh" "$ENVN" > "$W/logs/C1.stdout" 2>&1 || RC=1
  grep -E '^(CHECK .* (FAIL|SKIP)|PHASE )' "$W/logs/C1.stdout" | mask
}
snapshot_retained() { # record physical ids of RETAIN resources before destroy
  : > "$W/retained.tsv"
  for s in $STACKS; do
    tpl="$(aws_ cloudformation get-template --stack-name "$s" --query TemplateBody 2>/dev/null)" || continue
    echo "$tpl" | jq -r 'if type=="string" then fromjson else . end | .Resources | to_entries[] | select(.value.DeletionPolicy=="Retain" or .value.UpdateReplacePolicy=="Retain") | .key' \
    | while read -r lid; do
        phys="$(aws_ cloudformation describe-stack-resource --stack-name "$s" --logical-resource-id "$lid" --query 'StackResourceDetail.[ResourceType,PhysicalResourceId]' --output text 2>/dev/null)"
        [ -n "$phys" ] && printf '%s\t%s\n' "$s" "$phys" >> "$W/retained.tsv"
      done
  done
  log "retained resources recorded: $(wc -l < "$W/retained.tsv" | tr -d ' ')"
}
st_egress() {
  # Test-only additions to the Kiro allowlist: SSM (to drive the probe), the results bucket, and the
  # AL2023 package mirrors (git/jq for the end-to-end test). Production allowlists do not need these.
  local extra="ssm.$R.amazonaws.com,ssmmessages.$R.amazonaws.com,ec2messages.$R.amazonaws.com,s3.$R.amazonaws.com,$BUCKET.s3.$R.amazonaws.com,cdn.amazonlinux.com,*.s3.dualstack.$R.amazonaws.com"
  # shellcheck disable=SC2046
  cfn_deploy_all egress $(cdk_flags) -c egress=nat-dns-firewall -c "egressAllowedDomains=$extra"
  local net="KiroBanking-Network-$ENVN" vpc subnet
  vpc="$(aws_ cloudformation describe-stack-resources --stack-name "$net" | jq -r '.StackResources[] | select(.ResourceType=="AWS::EC2::VPC") | .PhysicalResourceId')"
  subnet="$(aws_ ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" "Name=tag:aws-cdk:subnet-name,Values=Workspaces" --query 'Subnets[0].SubnetId' --output text)"
  aws_ cloudformation deploy --stack-name "$PROBE" --template-file "$HERE/probe.yaml" --no-fail-on-empty-changeset \
    --parameter-overrides "VpcId=$vpc" "SubnetId=$subnet" "InstanceProfileName=$PROFILE_NAME" --tags Project=kiro-fsi-test || die "probe deploy failed"
  save PROBE_ID "$(out "$PROBE" ProbeInstanceId)"
  wait_ssm_online "$PROBE_ID"
  ssm_run "$PROBE_ID" AWS-RunShellScript probe-setup "$(linux_cmd probe-setup)" 900 || RC=1
  ssm_run "$PROBE_ID" AWS-RunShellScript probe-C2 "$(linux_cmd probe)" 900 || RC=1
  ssm_run "$PROBE_ID" AWS-RunShellScript probe-kiro "$(linux_cmd kiro)" 2400 || RC=1
}
empty_bucket() { # bucket (versioned / Object Lock aware)
  local b="$1" bypass="" resp
  aws_ s3api head-bucket --bucket "$b" >/dev/null 2>&1 || return 0
  # S3 rejects --bypass-governance-retention on buckets without Object Lock.
  aws_ s3api get-object-lock-configuration --bucket "$b" >/dev/null 2>&1 && bypass="--bypass-governance-retention"
  while :; do
    batch="$(aws_ s3api list-object-versions --bucket "$b" --max-items 500 \
      | jq -c '{Objects: ([(.Versions // [])[], (.DeleteMarkers // [])[]] | map({Key, VersionId})), Quiet: true}')"
    [ "$(echo "$batch" | jq '.Objects | length')" = 0 ] && break
    # shellcheck disable=SC2086
    resp="$(aws_ s3api delete-objects --bucket "$b" --delete "$batch" $bypass)" || return 1
    # Per-object failures (e.g. COMPLIANCE-mode retention) return exit 0 with an Errors list.
    [ "$(printf '%s' "$resp" | jq -s 'map((.Errors // []) | length) | add // 0')" = 0 ] \
      || { printf '%s' "$resp" | jq -r '.Errors[0].Code' >&2; return 1; }
  done
  aws_ s3api delete-bucket --bucket "$b"
}
st_down() {
  aws_ cloudformation describe-stacks --stack-name "$PROBE" >/dev/null 2>&1 && {
    aws_ cloudformation delete-stack --stack-name "$PROBE"; aws_ cloudformation wait stack-delete-complete --stack-name "$PROBE"; log "probe deleted"; }
  snapshot_retained
  local role="arn:aws:iam::$ACCOUNT:role/cdk-hnb659fds-cfn-exec-role-$ACCOUNT-$R" s
  for s in KiroBanking-Backup-$ENVN KiroBanking-Compliance-$ENVN KiroBanking-Monitoring-$ENVN KiroBanking-Network-$ENVN KiroBanking-Encryption-$ENVN; do
    aws_ cloudformation describe-stacks --stack-name "$s" >/dev/null 2>&1 || continue
    aws_ cloudformation delete-stack --stack-name "$s" --role-arn "$role" \
      && aws_ cloudformation wait stack-delete-complete --stack-name "$s" && log "deleted $s" || { log "FAILED to delete $s"; RC=1; }
  done
  while IFS=$'\t' read -r _stack typ phys; do
    case "$typ" in
      AWS::S3::Bucket) empty_bucket "$phys" && log "deleted bucket (retained)" || { log "FAILED to delete a retained bucket"; RC=1; } ;;
      AWS::KMS::Key) aws_ kms schedule-key-deletion --key-id "$phys" --pending-window-in-days 7 >/dev/null 2>&1 && log "KMS key scheduled for deletion (7 days)" ;;
      AWS::Logs::LogGroup) aws_ logs delete-log-group --log-group-name "$phys" 2>/dev/null && log "deleted log group (retained)" ;;
      AWS::Backup::BackupVault)
        for rp in $(aws_ backup list-recovery-points-by-backup-vault --backup-vault-name "$phys" --query 'RecoveryPoints[].RecoveryPointArn' | jq -r '.[]'); do
          aws_ backup delete-recovery-point --backup-vault-name "$phys" --recovery-point-arn "$rp"; done
        aws_ backup delete-backup-vault --backup-vault-name "$phys" && log "deleted backup vault (retained)" ;;
      *) log "retained resource left for review: $typ" ;;
    esac
  done < "$W/retained.tsv"
  if [ "${WE_BOOTSTRAPPED:-false}" = true ]; then
    boot_bucket="$(aws_ cloudformation describe-stacks --stack-name CDKToolkit --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text 2>/dev/null)"
    [ -n "$boot_bucket" ] && [ "$boot_bucket" != None ] && empty_bucket "$boot_bucket"
    aws_ cloudformation delete-stack --stack-name CDKToolkit && aws_ cloudformation wait stack-delete-complete --stack-name CDKToolkit && log "CDK bootstrap removed (we created it)"
    for repo in $(aws_ ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `cdk-hnb659fds-container-assets`)].repositoryName' | jq -r '.[]' 2>/dev/null); do
      aws_ ecr delete-repository --repository-name "$repo" --force >/dev/null && log "deleted bootstrap ECR repository"; done
  fi
  if aws_ cloudformation describe-stacks --stack-name "$HARNESS" >/dev/null 2>&1; then
    b="$(out "$HARNESS" ResultsBucketName)"
    aws_ s3 rm --recursive --only-show-errors "s3://$b" || true
    aws_ cloudformation delete-stack --stack-name "$HARNESS"; aws_ cloudformation wait stack-delete-complete --stack-name "$HARNESS" && log "harness deleted (instances terminated)"
  fi
}
live_state() { # arn -> "gone", "PendingDeletion" or a live state. The tagging API lists deleted
  # resources for a while, so every tagged ARN is checked against its own service.
  local arn="$1" id="${1##*/}" out
  case "$arn" in
    arn:aws:kms:*) out="$(aws_ kms describe-key --key-id "$arn" --query KeyMetadata.KeyState --output text 2>&1)" ;;
    *:instance/*) out="$(aws_ ec2 describe-instances --instance-ids "$id" --query 'Reservations[0].Instances[0].State.Name' --output text 2>&1)" ;;
    *:natgateway/*) out="$(aws_ ec2 describe-nat-gateways --nat-gateway-ids "$id" --query 'NatGateways[0].State' --output text 2>&1)" ;;
    *:vpc-endpoint/*) out="$(aws_ ec2 describe-vpc-endpoints --vpc-endpoint-ids "$id" --query 'VpcEndpoints[0].State' --output text 2>&1)" ;;
    *:subnet/*) out="$(aws_ ec2 describe-subnets --subnet-ids "$id" --query 'Subnets[0].State' --output text 2>&1)" ;;
    *:vpc/*) out="$(aws_ ec2 describe-vpcs --vpc-ids "$id" --query 'Vpcs[0].State' --output text 2>&1)" ;;
    *:vpc-flow-log/*) out="$(aws_ ec2 describe-flow-logs --flow-log-ids "$id" --query 'FlowLogs[0].FlowLogStatus' --output text 2>&1)" ;;
    arn:aws:s3:::*) aws_ s3api head-bucket --bucket "${arn#arn:aws:s3:::}" >/dev/null 2>&1 && out=present || out=NotFound ;;
    *) out=unchecked ;;   # unknown type: reported as a leftover for a human to check
  esac
  case "$out" in
    *NotFound*|*NotFoundException*|terminated|deleted|None|"") echo gone ;;
    *) echo "$out" | tail -1 ;;
  esac
}
name_scan() { # name-prefix scan for retained or untagged resources the tag scan can miss
  local pat='kiro-banking|KiroBanking|kiro-fsi-test'
  aws_ s3api list-buckets --query 'Buckets[].Name' | jq -r '.[]' | grep -E "^($pat)" | sed 's/^/LEFTOVER s3-bucket /'
  aws_ logs describe-log-groups --query 'logGroups[].logGroupName' | jq -r '.[]' | grep -E "$pat" | sed 's/^/LEFTOVER log-group /'
  aws_ kms list-aliases --query 'Aliases[].AliasName' | jq -r '.[]' | grep -E "$pat" | sed 's/^/LEFTOVER kms-alias /'
  aws_ backup list-backup-vaults --query 'BackupVaultList[].BackupVaultName' | jq -r '.[]' | grep -E "$pat" | sed 's/^/LEFTOVER backup-vault /'
  aws_ backup list-backup-plans --query 'BackupPlansList[].BackupPlanName' | jq -r '.[]' | grep -E "$pat" | sed 's/^/LEFTOVER backup-plan /'
  aws_ sns list-topics --query 'Topics[].TopicArn' | jq -r '.[]' | grep -E "$pat" | sed -E 's/.*:/LEFTOVER sns-topic /'
  aws_ cloudwatch describe-alarms --alarm-name-prefix kiro-banking --query 'MetricAlarms[].AlarmName' | jq -r '.[]' | sed 's/^/LEFTOVER alarm /'
  aws_ configservice describe-config-rules --query 'ConfigRules[].ConfigRuleName' | jq -r '.[]' | grep -E '^(mas-trm-|pdpa-rds-)' | sed 's/^/LEFTOVER config-rule /'
  aws_ cloudtrail describe-trails --query 'trailList[].Name' | jq -r '.[]' | grep -E "$pat" | sed 's/^/LEFTOVER trail /'
  aws_ accessanalyzer list-analyzers --query 'analyzers[].name' | jq -r '.[]' | grep -E "$pat" | sed 's/^/LEFTOVER access-analyzer /'
  aws_ events list-rules --query 'Rules[].Name' | jq -r '.[]' | grep -E "$pat" | sed 's/^/LEFTOVER event-rule /'
  aws_ route53resolver list-firewall-rule-groups --query 'FirewallRuleGroups[].Name' | jq -r '.[]' | grep -E "$pat" | sed 's/^/LEFTOVER dns-firewall-rule-group /'
  aws_ route53resolver list-firewall-domain-lists --query 'FirewallDomainLists[].Name' | jq -r '.[]' | grep -E "$pat" | sed 's/^/LEFTOVER dns-firewall-domain-list /'
  aws_ iam list-roles --query 'Roles[].RoleName' | jq -r '.[]' | grep -E "^($pat)" | sed 's/^/LEFTOVER iam-role /'
  aws_ ssm describe-parameters --parameter-filters Key=Name,Option=BeginsWith,Values=/kiro-fsi-test/ --query 'Parameters[].Name' | jq -r '.[]' | sed 's/^/LEFTOVER ssm-parameter /'
}
st_leftovers() {
  local n=0
  for s in $STACKS $HARNESS $PROBE; do
    st="$(aws_ cloudformation describe-stacks --stack-name "$s" --query 'Stacks[0].StackStatus' --output text 2>/dev/null)"
    [ -n "$st" ] && { echo "LEFTOVER stack $s $st"; n=$((n+1)); }
  done
  {
    for tag in kiro-fsi-test kiro-banking; do
      aws_ resourcegroupstaggingapi get-resources --tag-filters "Key=Project,Values=$tag" --query 'ResourceTagMappingList[].ResourceARN' \
        | jq -r '.[]' | while read -r arn; do
          ls="$(live_state "$arn")"; typ="$(echo "$arn" | cut -d: -f3,6 | sed -E 's#/.*##; s#^s3:.*#s3:bucket#')"
          case "$ls" in
            gone) echo "STALE $typ (deleted; tagging API not yet updated)" ;;
            PendingDeletion) echo "EXPECTED $typ PendingDeletion" ;;
            *) echo "LEFTOVER $typ ($ls)" ;;
          esac
        done
    done
    name_scan
  } | mask | tee "$W/logs/leftovers.txt"
  n=$((n + $(grep -c '^LEFTOVER' "$W/logs/leftovers.txt" || true)))
  aws_ ec2 describe-instances --filters "Name=tag:Project,Values=kiro-fsi-test" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'length(Reservations[].Instances[])' \
    | grep -q '^0$' || { echo "LEFTOVER running test instances"; n=$((n+1)); }
  echo "LEFTOVERS total=$n"; [ "$n" -eq 0 ] || RC=1
}

# --------------------------------------------------------------------- main
[ $# -ge 1 ] || { sed -n '2,24p' "$0"; exit 1; }
for stage in "$@"; do
  case "$stage" in
    all) set -- preflight up bundle linux windows deploy verify egress ;;
  esac
done
for stage in "$@"; do
  log "===== stage: $stage"
  case "$stage" in
    preflight) st_preflight ;; up) st_up ;; bundle) st_bundle ;; linux) st_linux ;; windows) st_windows ;;
    linux:*) ssm_run "$LINUX_ID" AWS-RunShellScript "linux-${stage#linux:}" "$(linux_cmd "${stage#linux:}")" 3600 || RC=1 ;;
    deploy) st_deploy ;; verify) st_verify ;; egress) st_egress ;; down) st_down ;; leftovers) st_leftovers ;;
    *) die "unknown stage: $stage" ;;
  esac
done
log "done (rc=$RC); logs in $W/logs"
exit $RC
