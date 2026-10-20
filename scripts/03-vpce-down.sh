#!/usr/bin/env bash
# Module 2b - Delete the endpoints and security group created by 02-vpce-up.sh.
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

ids="$(state_get VPCE_IDS)"
sg="$(state_get SG_ID)"

if [ -n "$ids" ]; then
  log "Deleting endpoints: $ids"
  # shellcheck disable=SC2086
  aws ec2 delete-vpc-endpoints --region "$REGION" --vpc-endpoint-ids $ids >/dev/null
  for id in $ids; do
    until [ "$(aws ec2 describe-vpc-endpoints --region "$REGION" --filters Name=vpc-endpoint-id,Values="$id" \
        --query "VpcEndpoints[?State!='deleted'] | length(@)" --output text)" = "0" ]; do
      echo "  waiting on $id ..."; sleep 15
    done
  done
  state_del VPCE_IDS
  ok "endpoints deleted"
else
  ok "no endpoints recorded"
fi

# The security group cannot be deleted until the endpoint network interfaces are gone.
if [ -n "$sg" ]; then
  for _ in 1 2 3 4 5 6; do
    if aws ec2 delete-security-group --region "$REGION" --group-id "$sg" 2>/dev/null; then
      state_del SG_ID; ok "security group $sg deleted"; break
    fi
    echo "  security group still in use; retrying in 15s ..."; sleep 15
  done
fi
log "Hourly endpoint cost stopped."
