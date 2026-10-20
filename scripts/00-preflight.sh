#!/usr/bin/env bash
# Module 0 - Preflight: prove which partition, Region and identity you are using.
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

need python3
log "Identity"
echo "  Partition : $PARTITION  (profile prefix: ${GEO}.)"
echo "  Region    : $REGION"
echo "  Account   : ****${ACCOUNT: -4}"
echo "  Caller    : ${CALLER_ARN#*:*:*:*:*:}"

if [ "$PARTITION" = "aws-us-gov" ]; then
  ok "GovCloud credentials (arn:aws-us-gov)"
else
  warn "Commercial credentials (arn:aws). Fine for the lab; never send CUI here."
fi

log "Lab model"
if [ -z "${BEDROCK_MODEL:-}" ]; then
  die "BEDROCK_MODEL is not set. Run: cp .env.example .env && source .env"
fi
echo "  BEDROCK_MODEL=$BEDROCK_MODEL  (base model: $(base_model_id "$BEDROCK_MODEL"))"

log "Inference profiles available in $REGION (first 15)"
aws bedrock list-inference-profiles --region "$REGION" \
  --query "inferenceProfileSummaries[].inferenceProfileId" --output text | tr '\t' '\n' | awk 'NR<=15{print "  " $0}'

log "Next: make smoke"
