variable "region" {
  description = "AWS Region. Commercial: us-east-1. GovCloud: us-gov-west-1 or us-gov-east-1."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every resource name and the Project tag."
  type        = string
  default     = "bedrock-lab"
}

variable "model_id" {
  description = "Base model ID (no Region prefix). The us. or us-gov. prefix is derived from the partition."
  type        = string
  default     = "amazon.nova-pro-v1:0"
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for the guardrail and log bucket. Null uses AWS-owned keys (lab only)."
  type        = string
  default     = null
}

variable "enable_invocation_logging" {
  description = "Create the log bucket and turn on account-wide invocation logging. Replaces any existing config in this Region."
  type        = bool
  default     = true
}

variable "force_destroy_log_bucket" {
  description = "Allow terraform destroy to delete a non-empty log bucket. Lab: true. Production: false."
  type        = bool
  default     = true
}
