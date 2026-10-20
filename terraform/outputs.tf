output "partition" {
  description = "aws (commercial) or aws-us-gov (GovCloud)."
  value       = local.partition
}

output "inference_profile_id" {
  description = "Use as BEDROCK_MODEL."
  value       = local.profile_id
}

output "guardrail_id" {
  value = aws_bedrock_guardrail.baseline.guardrail_id
}

output "guardrail_version" {
  value = aws_bedrock_guardrail_version.v1.version
}

output "invoke_policy_arn" {
  description = "Attach to the role your application runs as."
  value       = aws_iam_policy.invoke_one_model.arn
}

output "log_bucket" {
  value = var.enable_invocation_logging ? aws_s3_bucket.logs[0].id : null
}
