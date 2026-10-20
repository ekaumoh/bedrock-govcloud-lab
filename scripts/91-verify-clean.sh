#!/usr/bin/env bash
# Verify the account is back to zero lab resources. Exits non-zero if anything remains.
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

fail=0
check() { if [ "$2" = "0" ]; then ok "$1: 0"; else bad "$1: $2"; fail=1; fi; }

log "Lab resources in $REGION"
check "Knowledge Bases ($TAG*)" "$(aws bedrock-agent list-knowledge-bases --region "$REGION" \
  --query "length(knowledgeBaseSummaries[?starts_with(name,'$TAG')])" --output text)"
check "Guardrails ($TAG*)" "$(aws bedrock list-guardrails --region "$REGION" \
  --query "length(guardrails[?starts_with(name,'$TAG')])" --output text)"
check "VPC endpoints (Project=$TAG, not deleted)" "$(aws ec2 describe-vpc-endpoints --region "$REGION" \
  --filters Name=tag:Project,Values="$TAG" Name=vpc-endpoint-state,Values=available,pending,pendingAcceptance \
  --query "length(VpcEndpoints)" --output text)"
check "S3 buckets ($TAG-*)" "$(aws s3api list-buckets --query "length(Buckets[?starts_with(Name,'$TAG-')])" --output text)"
check "IAM role $TAG-app" "$(aws iam get-role --role-name "$TAG-app" >/dev/null 2>&1 && echo 1 || echo 0)"

log "Note: the Resource Groups Tagging API can list deleted resources for a few hours. Trust the counts above."
exit "$fail"
