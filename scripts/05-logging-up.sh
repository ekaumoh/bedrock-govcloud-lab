#!/usr/bin/env bash
# Module 4 - Model invocation logging to S3 (your audit trail).
#
# WARNING: invocation logging is ONE setting per account per Region.
# Running this replaces any existing configuration.
#
# Logs contain full prompts and responses. Treat the bucket as the same
# classification as the data. Set KMS_KEY_ARN to encrypt with your own key.
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

BUCKET="${LOG_BUCKET:-$TAG-logs-$ACCOUNT}"
existing=$(aws bedrock get-model-invocation-logging-configuration --region "$REGION" \
  --query "loggingConfig.s3Config.bucketName" --output text 2>/dev/null || true)
if [ -n "$existing" ] && [ "$existing" != "None" ] && [ "$existing" != "$BUCKET" ]; then
  die "Account already logs to s3://$existing. Refusing to overwrite. Set LOG_BUCKET=$existing to reuse it."
fi

log "Bucket s3://$BUCKET"
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
  fi
  aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging "TagSet=[{Key=Project,Value=$TAG}]"
fi
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

if [ -n "${KMS_KEY_ARN:-}" ]; then
  enc="{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"aws:kms\",\"KMSMasterKeyID\":\"$KMS_KEY_ARN\"},\"BucketKeyEnabled\":true}]}"
else
  enc='{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  warn "Using SSE-S3. For CUI, set KMS_KEY_ARN to a customer-managed key."
fi
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration "$enc"
ok "public access blocked, encryption on"

cat > "$STATE_DIR/log-bucket-policy.json" <<EOF
{"Version":"2012-10-17","Statement":[{"Sid":"BedrockLogsWrite","Effect":"Allow",
 "Principal":{"Service":"bedrock.amazonaws.com"},"Action":"s3:PutObject",
 "Resource":"arn:$PARTITION:s3:::$BUCKET/AWSLogs/$ACCOUNT/BedrockModelInvocationLogs/*",
 "Condition":{"StringEquals":{"aws:SourceAccount":"$ACCOUNT"},
              "ArnLike":{"aws:SourceArn":"arn:$PARTITION:bedrock:$REGION:$ACCOUNT:*"}}}]}
EOF
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "file://$STATE_DIR/log-bucket-policy.json"
ok "bucket policy lets only Bedrock (for this account) write logs"

aws bedrock put-model-invocation-logging-configuration --region "$REGION" \
  --logging-config "{\"s3Config\":{\"bucketName\":\"$BUCKET\"},\"textDataDeliveryEnabled\":true}"
state_set LOG_BUCKET "$BUCKET"
ok "invocation logging on"

log "Generate a log entry"
aws bedrock-runtime converse --region "$REGION" --model-id "${BEDROCK_MODEL:?}" \
  --messages '[{"role":"user","content":[{"text":"Logging test: name three AWS Regions."}]}]' \
  --inference-config '{"maxTokens":60}' --query "output.message.content[0].text" --output text

log "Logs arrive in batches in about 5 minutes. Then run:"
echo "  aws s3 ls s3://$BUCKET --recursive | tail -3"
