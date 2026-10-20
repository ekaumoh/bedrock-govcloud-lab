#!/usr/bin/env bash
# Module 2a - Private network path: interface VPC endpoint(s) for Bedrock.
#
# Cost: about $0.01 per hour per Availability Zone per endpoint, plus data.
# Run scripts/03-vpce-down.sh when you pause.
#
# Env:
#   VPC_ID     VPC to use. Default: the default VPC (GovCloud usually has none; set this).
#   SERVICES   Space-separated Bedrock services. Default: bedrock-runtime.
#              Knowledge Bases from inside the VPC also need: bedrock bedrock-agent bedrock-agent-runtime
#   ENDPOINT_MODEL_ALLOWLIST=1  Attach an endpoint policy to bedrock-runtime that only
#              allows InvokeModel* on $BEDROCK_MODEL. Note: this also blocks ApplyGuardrail
#              through the endpoint unless you add bedrock:ApplyGuardrail.
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

SERVICES="${SERVICES:-bedrock-runtime}"

# 1. VPC
VPC_ID="${VPC_ID:-$(aws ec2 describe-vpcs --region "$REGION" --filters Name=is-default,Values=true \
  --query "Vpcs[0].VpcId" --output text)}"
[ "$VPC_ID" = "None" ] && die "No default VPC. Set VPC_ID=<VPC_ID>, or run: aws ec2 create-default-vpc --region $REGION"
CIDR=$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlock" --output text)
log "VPC $VPC_ID ($CIDR)"

# 2. Private DNS needs both VPC DNS attributes on.
for attr in enableDnsSupport enableDnsHostnames; do
  key="$(tr '[:lower:]' '[:upper:]' <<< "${attr:0:1}")${attr:1}"
  val=$(aws ec2 describe-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --attribute "$attr" \
    --query "$key.Value" --output text)
  [ "$val" = "True" ] || [ "$val" = "true" ] || die "$attr is off on $VPC_ID; private DNS will not work."
done
ok "VPC DNS support and hostnames are on"

# 3. Security group: HTTPS from inside the VPC only.
SG_ID=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters Name=group-name,Values="$TAG-vpce-sg" Name=vpc-id,Values="$VPC_ID" \
  --query "SecurityGroups[0].GroupId" --output text)
if [ "$SG_ID" = "None" ]; then
  SG_ID=$(aws ec2 create-security-group --region "$REGION" --group-name "$TAG-vpce-sg" \
    --description "HTTPS from VPC to Bedrock endpoints" --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=$TAG}]" \
    --query GroupId --output text)
  aws ec2 authorize-security-group-ingress --region "$REGION" --group-id "$SG_ID" \
    --protocol tcp --port 443 --cidr "$CIDR" >/dev/null
fi
state_set SG_ID "$SG_ID"
log "Security group $SG_ID"

# 4. One endpoint per service, spread across two supported AZs.
ids="$(state_get VPCE_IDS)"
for svc in $SERVICES; do
  name="com.amazonaws.$REGION.$svc"
  azs=$(aws ec2 describe-vpc-endpoint-services --region "$REGION" --service-names "$name" \
    --query "ServiceDetails[0].AvailabilityZones" --output text | tr '\t' ',')
  # shellcheck disable=SC2207
  subnets=($(aws ec2 describe-subnets --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" Name=availability-zone,Values="$azs" \
    --query "Subnets[:2].SubnetId" --output text))
  [ "${#subnets[@]}" -ge 1 ] || die "no subnets in a supported AZ for $svc"

  policy_args=()
  if [ "$svc" = "bedrock-runtime" ] && [ "${ENDPOINT_MODEL_ALLOWLIST:-0}" = "1" ]; then
    base=$(base_model_id "${BEDROCK_MODEL:?}")
    policy_file="$STATE_DIR/vpce-policy.json"
    cat > "$policy_file" <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*",
 "Action":["bedrock:InvokeModel","bedrock:InvokeModelWithResponseStream"],
 "Resource":["arn:$PARTITION:bedrock:$REGION:$ACCOUNT:inference-profile/$BEDROCK_MODEL",
             "arn:$PARTITION:bedrock:*::foundation-model/$base"]}]}
EOF
    policy_args=(--policy-document "file://$policy_file")
    log "Endpoint policy: only $BEDROCK_MODEL"
  fi

  vpce=$(aws ec2 create-vpc-endpoint --region "$REGION" --vpc-id "$VPC_ID" --vpc-endpoint-type Interface \
    --service-name "$name" --subnet-ids "${subnets[@]}" --security-group-ids "$SG_ID" --private-dns-enabled \
    ${policy_args[@]+"${policy_args[@]}"} \
    --tag-specifications "ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$TAG-$svc},{Key=Project,Value=$TAG}]" \
    --query "VpcEndpoint.VpcEndpointId" --output text)
  ids="$ids $vpce"
  state_set VPCE_IDS "${ids# }"

  until [ "$(aws ec2 describe-vpc-endpoints --region "$REGION" --vpc-endpoint-ids "$vpce" \
      --query "VpcEndpoints[0].State" --output text)" = "available" ]; do
    echo "  waiting on $vpce ..."; sleep 15
  done
  ok "$svc endpoint $vpce is available (subnets: ${subnets[*]})"
done

log "Test from INSIDE the VPC (CloudShell VPC environment or an instance):"
echo "  nslookup bedrock-runtime.$REGION.amazonaws.com   # expect private IPs in $CIDR"
