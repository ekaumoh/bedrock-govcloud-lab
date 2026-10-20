#!/usr/bin/env bash
# Delete everything this lab created, in dependency order.
# Only touches resources named or tagged with $TAG (default: bedrock-lab).
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

read -r -p "Delete all '$TAG' lab resources in $REGION? [y/N] " yn
[[ "$yn" =~ ^[Yy]$ ]] || exit 0

log "1. Invocation logging (only if it points at a lab bucket)"
cur=$(aws bedrock get-model-invocation-logging-configuration --region "$REGION" \
  --query "loggingConfig.s3Config.bucketName" --output text 2>/dev/null || true)
if [[ "$cur" == "$TAG"-* ]]; then
  aws bedrock delete-model-invocation-logging-configuration --region "$REGION"; ok "logging off"
else ok "skipped (current target: ${cur:-none})"; fi

log "2. Knowledge Bases named $TAG*"
for kb in $(aws bedrock-agent list-knowledge-bases --region "$REGION" \
    --query "knowledgeBaseSummaries[?starts_with(name,'$TAG')].knowledgeBaseId" --output text); do
  aws bedrock-agent delete-knowledge-base --region "$REGION" --knowledge-base-id "$kb" >/dev/null && ok "deleting $kb"
done

log "3. Guardrails named $TAG*"
for g in $(aws bedrock list-guardrails --region "$REGION" \
    --query "guardrails[?starts_with(name,'$TAG')].id" --output text); do
  aws bedrock delete-guardrail --region "$REGION" --guardrail-identifier "$g" && ok "deleted $g"
done

log "4. IAM role $TAG-app"
if aws iam get-role --role-name "$TAG-app" >/dev/null 2>&1; then
  aws iam delete-role-policy --role-name "$TAG-app" --policy-name invoke-one-model 2>/dev/null || true
  aws iam delete-role --role-name "$TAG-app" && ok "deleted"
else ok "not present"; fi

log "5. VPC endpoints"
"$(dirname "$0")/03-vpce-down.sh"

log "6. KB application log groups"
for lg in $(aws logs describe-log-groups --region "$REGION" \
    --log-group-name-prefix /aws/vendedlogs/bedrock/knowledge-base --query "logGroups[].logGroupName" --output text); do
  aws logs delete-log-group --region "$REGION" --log-group-name "$lg" && ok "deleted $lg"
done

log "7. S3 buckets $TAG-*-$ACCOUNT (waiting 60s for KB deletion first)"
sleep 60
for b in $(aws s3api list-buckets --query "Buckets[?starts_with(Name,'$TAG-')].Name" --output text); do
  # Versioned buckets: delete every version and delete marker, then the bucket.
  aws s3api delete-objects --bucket "$b" --delete "$(aws s3api list-object-versions --bucket "$b" \
    --query '{Objects: [Versions[], DeleteMarkers[]][][].{Key:Key,VersionId:VersionId}, Quiet: `true`}' \
    --output json)" >/dev/null 2>&1 || true
  aws s3 rb "s3://$b" --force >/dev/null && ok "deleted $b"
done

rm -f "$STATE_FILE"
warn "Console-created KB service roles are NOT deleted automatically. Review them:"
echo "  aws iam list-roles --query \"Roles[?starts_with(RoleName,'AmazonBedrockExecutionRoleForKnowledgeBase')].[RoleName,CreateDate]\" --output table"
log "Done. Verify: make verify"
