#!/usr/bin/env bash
# Module 3 - Least-privilege IAM: a role that can call exactly one model.
#
# Creates role "$TAG-app", then assumes it and proves:
#   - $BEDROCK_MODEL           -> allowed
#   - $DENY_TEST_MODEL         -> AccessDeniedException
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

: "${BEDROCK_MODEL:?BEDROCK_MODEL is not set}"
ROLE="$TAG-app"
BASE=$(base_model_id "$BEDROCK_MODEL")
DENY_TEST_MODEL="${DENY_TEST_MODEL:-amazon.nova-lite-v1:0}"
tmp="$STATE_DIR/iam"; mkdir -p "$tmp"

cat > "$tmp/trust.json" <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
 "Principal":{"AWS":"arn:$PARTITION:iam::$ACCOUNT:root"},"Action":"sts:AssumeRole"}]}
EOF

# Two ARNs: the inference profile you call, and the base model it can route to
# in any Region of its geography (hence the * Region).
cat > "$tmp/invoke-one-model.json" <<EOF
{"Version":"2012-10-17","Statement":[{"Sid":"InvokeOneModel","Effect":"Allow",
 "Action":["bedrock:InvokeModel","bedrock:InvokeModelWithResponseStream"],
 "Resource":["arn:$PARTITION:bedrock:$REGION:$ACCOUNT:inference-profile/$BEDROCK_MODEL",
             "arn:$PARTITION:bedrock:*::foundation-model/$BASE"]}]}
EOF

log "Role $ROLE"
if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" --assume-role-policy-document "file://$tmp/trust.json" \
    --tags Key=Project,Value="$TAG" >/dev/null
  ok "created"
fi
aws iam put-role-policy --role-name "$ROLE" --policy-name invoke-one-model \
  --policy-document "file://$tmp/invoke-one-model.json"
ok "policy allows only $BEDROCK_MODEL"

log "Waiting 15s for IAM to propagate"; sleep 15
read -r AK SK ST < <(aws sts assume-role --role-arn "arn:$PARTITION:iam::$ACCOUNT:role/$ROLE" \
  --role-session-name lab-test --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" --output text)

as_role() { env -u AWS_PROFILE AWS_ACCESS_KEY_ID="$AK" AWS_SECRET_ACCESS_KEY="$SK" AWS_SESSION_TOKEN="$ST" "$@"; }
try() {
  as_role aws bedrock-runtime converse --region "$REGION" --model-id "$1" \
    --messages '[{"role":"user","content":[{"text":"hi"}]}]' --inference-config '{"maxTokens":5}' \
    --query stopReason --output text 2>&1
}

log "Testing as the role"
if out=$(try "$BEDROCK_MODEL"); then ok "allowed: $BEDROCK_MODEL ($out)"; else bad "expected allow: $out"; exit 1; fi
if out=$(try "$DENY_TEST_MODEL"); then bad "expected deny, got: $out"; exit 1
elif grep -q AccessDenied <<< "$out"; then ok "denied: $DENY_TEST_MODEL"
else bad "unexpected error: $out"; exit 1; fi
