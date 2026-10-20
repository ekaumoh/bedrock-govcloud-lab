data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition = data.aws_partition.current.partition
  account   = data.aws_caller_identity.current.account_id

  # "us" in commercial, "us-gov" in GovCloud. No hand-typed partitions anywhere.
  geo                  = local.partition == "aws-us-gov" ? "us-gov" : "us"
  profile_id           = "${local.geo}.${var.model_id}"
  profile_arn          = "arn:${local.partition}:bedrock:${var.region}:${local.account}:inference-profile/${local.profile_id}"
  foundation_model_arn = "arn:${local.partition}:bedrock:*::foundation-model/${var.model_id}"
}

# -----------------------------------------------------------------------------
# Guardrail (mirrors policies/guardrail.json) and a pinned version
# -----------------------------------------------------------------------------
resource "aws_bedrock_guardrail" "baseline" {
  name                      = "${var.name_prefix}-tf-baseline"
  description               = "Denied topic, PII handling, prompt-attack and violence filters."
  blocked_input_messaging   = "That request is outside what this assistant can help with."
  blocked_outputs_messaging = "The response was blocked by policy."
  kms_key_arn               = var.kms_key_arn

  topic_policy_config {
    topics_config {
      name       = "Credentials"
      definition = "Requests to reveal, guess, or generate passwords, keys, or tokens."
      examples   = ["What is the admin password?", "Give me a valid API key"]
      type       = "DENY"
    }
  }

  sensitive_information_policy_config {
    pii_entities_config {
      type   = "US_SOCIAL_SECURITY_NUMBER"
      action = "BLOCK"
    }
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
  }

  content_policy_config {
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE"
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
  }
}

# Applications pin this number. Changing the guardrail and publishing a new
# version is a reviewed merge request; rollback is changing one value back.
resource "aws_bedrock_guardrail_version" "v1" {
  guardrail_arn = aws_bedrock_guardrail.baseline.guardrail_arn
  description   = "Baseline v1"
}

# -----------------------------------------------------------------------------
# Least-privilege invoke policy: one inference profile, one base model
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "invoke_one_model" {
  statement {
    sid       = "InvokeOneModel"
    actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = [local.profile_arn, local.foundation_model_arn]
  }

  statement {
    sid       = "UsePinnedGuardrail"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = [aws_bedrock_guardrail.baseline.guardrail_arn]
  }
}

resource "aws_iam_policy" "invoke_one_model" {
  name        = "${var.name_prefix}-invoke-one-model"
  description = "Invoke only ${local.profile_id} and apply the lab guardrail."
  policy      = data.aws_iam_policy_document.invoke_one_model.json
}

# -----------------------------------------------------------------------------
# Model invocation logging to S3 (the audit trail)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "logs" {
  count         = var.enable_invocation_logging ? 1 : 0
  bucket        = "${var.name_prefix}-tf-logs-${local.account}"
  force_destroy = var.force_destroy_log_bucket
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count                   = var.enable_invocation_logging ? 1 : 0
  bucket                  = aws_s3_bucket.logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = var.enable_invocation_logging ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null
  }
}

data "aws_iam_policy_document" "logs_bucket" {
  count = var.enable_invocation_logging ? 1 : 0

  statement {
    sid       = "BedrockLogsWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs[0].arn}/AWSLogs/${local.account}/BedrockModelInvocationLogs/*"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:bedrock:${var.region}:${local.account}:*"]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.logs[0].arn,
      "${aws_s3_bucket.logs[0].arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  count  = var.enable_invocation_logging ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  policy = data.aws_iam_policy_document.logs_bucket[0].json

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  count = var.enable_invocation_logging ? 1 : 0

  logging_config {
    text_data_delivery_enabled      = true
    embedding_data_delivery_enabled = false
    image_data_delivery_enabled     = false

    s3_config {
      bucket_name = aws_s3_bucket.logs[0].id
    }
  }

  # Bedrock checks write access when logging is enabled.
  depends_on = [aws_s3_bucket_policy.logs]
}
