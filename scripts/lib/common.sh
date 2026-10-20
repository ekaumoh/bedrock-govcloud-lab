#!/usr/bin/env bash
# Shared helpers for every lab script. Source this file; do not execute it.
#
# Everything here is partition-aware: the same scripts run in AWS commercial
# (arn:aws) and AWS GovCloud (US) (arn:aws-us-gov) without edits.

set -euo pipefail
export AWS_PAGER=""

# ---- Settings (override with environment variables) ------------------------
export REGION="${AWS_REGION:-us-east-1}"
export TAG="${LAB_TAG:-bedrock-lab}"
export STATE_DIR="${STATE_DIR:-$HOME/.bedrock-lab}"
export STATE_FILE="$STATE_DIR/state-$REGION.env"
export REPO_ROOT
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

mkdir -p "$STATE_DIR"
touch "$STATE_FILE"

# ---- Output helpers --------------------------------------------------------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[1;32mPASS\033[0m %s\n' "$*"; }
bad()  { printf '  \033[1;31mFAIL\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

# ---- Identity and partition ------------------------------------------------
need aws
read -r ACCOUNT CALLER_ARN < <(aws sts get-caller-identity --query "[Account,Arn]" --output text) \
  || die "no valid AWS credentials. Run: aws sso login --profile <LAB_PROFILE>"
export ACCOUNT CALLER_ARN
export PARTITION="${CALLER_ARN#arn:}"; PARTITION="${PARTITION%%:*}"   # aws | aws-us-gov
if [ "$PARTITION" = "aws-us-gov" ]; then export GEO="us-gov"; else export GEO="us"; fi

# Strip a cross-Region prefix (us. / us-gov. / global. ...) to get the base model ID.
base_model_id() {
  local id="$1"
  if [[ "$id" =~ ^(us|us-gov|eu|apac|jp|au|ca|global)\. ]]; then echo "${id#*.}"; else echo "$id"; fi
}

# ---- Tiny state store: IDs of resources this lab created --------------------
state_set() {
  local k="$1" v="$2"
  { grep -v "^${k}=" "$STATE_FILE" || true; printf '%s=%s\n' "$k" "$v"; } > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
}
state_get() { grep "^${1}=" "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2- || true; }
state_del() { { grep -v "^${1}=" "$STATE_FILE" || true; } > "$STATE_FILE.tmp"; mv "$STATE_FILE.tmp" "$STATE_FILE"; }
