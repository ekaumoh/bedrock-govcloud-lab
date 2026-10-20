#!/usr/bin/env bash
# Module 6 - Knowledge Base (RAG).
#
# Usage:
#   scripts/07-kb.sh upload            Create the documents bucket and upload sample-docs/
#   scripts/07-kb.sh sync <KB_ID>      Sync EVERY data source of the KB and wait
#   scripts/07-kb.sh canary [KB_ID]    One known question per document; check the right file returns
#
# Create the KB itself in the console between "upload" and "sync". The console defaults to a
# Managed Knowledge Base, whose data-source API shape differs from the classic S3 config.
# shellcheck source-path=SCRIPTDIR source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

BUCKET="${KB_BUCKET:-$TAG-kb-$ACCOUNT}"
cmd="${1:-}"; KB_ID="${2:-$(state_get KB_ID)}"

case "$cmd" in
  upload)
    log "Bucket s3://$BUCKET"
    if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
      if [ "$REGION" = "us-east-1" ]; then aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
      else aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" --create-bucket-configuration LocationConstraint="$REGION" >/dev/null; fi
      aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging "TagSet=[{Key=Project,Value=$TAG}]"
      aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
    fi
    aws s3 cp "$REPO_ROOT/sample-docs/" "s3://$BUCKET/" --recursive --exclude "*" --include "*.md"
    state_set KB_BUCKET "$BUCKET"
    log "Next: console > Bedrock > Knowledge Bases > Create. Data source: S3 URI s3://$BUCKET/ (bucket root,"
    echo "      not a single file). Embeddings: Titan Text Embeddings V2. Then: scripts/07-kb.sh sync <KB_ID>"
    ;;

  sync)
    [ -n "$KB_ID" ] || die "usage: $0 sync <KB_ID>"
    state_set KB_ID "$KB_ID"
    type=$(aws bedrock-agent get-knowledge-base --region "$REGION" --knowledge-base-id "$KB_ID" \
      --query "knowledgeBase.knowledgeBaseConfiguration.type" --output text)
    log "KB $KB_ID (type: $type)"
    for ds in $(aws bedrock-agent list-data-sources --region "$REGION" --knowledge-base-id "$KB_ID" \
        --query "dataSourceSummaries[].dataSourceId" --output text); do
      aws bedrock-agent start-ingestion-job --region "$REGION" --knowledge-base-id "$KB_ID" \
        --data-source-id "$ds" >/dev/null
      while :; do
        read -r st scanned new failed < <(aws bedrock-agent list-ingestion-jobs --region "$REGION" \
          --knowledge-base-id "$KB_ID" --data-source-id "$ds" \
          --query "ingestionJobSummaries[0].[status,statistics.numberOfDocumentsScanned,statistics.numberOfNewDocumentsIndexed,statistics.numberOfDocumentsFailed]" \
          --output text)
        case "$st" in COMPLETE|FAILED|STOPPED) break ;; esac
        sleep 10
      done
      # Scanned (not new) proves the job looked at your files; 0 new is correct when nothing changed.
      if [ "$st" = "COMPLETE" ] && [ "$failed" = "0" ]; then ok "$ds: scanned=$scanned new=$new failed=$failed"
      else bad "$ds: status=$st scanned=$scanned failed=$failed"; fi
    done
    ;;

  canary)
    [ -n "$KB_ID" ] || die "usage: $0 canary <KB_ID>"
    log "Canary queries (one known question per document)"
    fail=0
    while IFS='|' read -r question expected; do
      top=$(aws bedrock-agent-runtime retrieve --region "$REGION" --knowledge-base-id "$KB_ID" \
        --retrieval-query "{\"text\":\"$question\"}" \
        --query "retrievalResults[0].location.s3Location.uri" --output text)
      if [[ "$top" == *"$expected" ]]; then ok "$expected <- \"$question\""
      else bad "expected $expected, got ${top##*/} <- \"$question\""; fail=1; fi
    done <<'EOF'
How often do TLS certificates rotate?|tls-rotation.md
When must a Severity 1 postmortem be written?|incident-escalation.md
EOF
    exit "$fail"
    ;;

  *) die "usage: $0 upload | sync <KB_ID> | canary [KB_ID]" ;;
esac
