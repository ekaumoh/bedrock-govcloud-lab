#!/usr/bin/env bash
# Module 1 - Smoke test: prove each model is actually callable.
#
# Status APIs can report AVAILABLE/AUTHORIZED while invoke still fails, so the
# only trustworthy access check is a real 5-token call.
#
# Usage: scripts/01-smoke-test.sh [MODEL_OR_PROFILE_ID ...]   (default: $BEDROCK_MODEL)
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

models=("$@")
if [ "${#models[@]}" -eq 0 ]; then models=("${BEDROCK_MODEL:?set BEDROCK_MODEL or pass model IDs}"); fi

log "Smoke test in $REGION"
fail=0
for m in "${models[@]}"; do
  if out=$(aws bedrock-runtime converse --region "$REGION" --model-id "$m" \
      --messages '[{"role":"user","content":[{"text":"hi"}]}]' \
      --inference-config '{"maxTokens":5}' --query stopReason --output text 2>&1); then
    ok "$m ($out)"
  else
    bad "$m -> $(echo "$out" | tr '\n' ' ' | sed -E 's/.*(\([A-Za-z]+Exception\))/\1/' | cut -c1-150)"
    fail=1
  fi
done

# Claude needs an account-wide Anthropic use-case form on top of the per-model agreement.
if printf '%s\n' "${models[@]}" | grep -q anthropic; then
  log "Anthropic use-case form"
  if aws bedrock get-use-case-for-model-access --region "$REGION" >/dev/null 2>&1; then
    ok "use-case form is on file"
  else
    bad "use-case form missing. Console: Bedrock > Playgrounds > Chat > pick a Claude model."
    [ "$PARTITION" = "aws-us-gov" ] && warn "In GovCloud, file the form in the LINKED STANDARD account."
  fi
fi

exit "$fail"
