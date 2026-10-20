terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60, < 7.0"
    }
  }

  # Remote state. State holds account IDs and ARNs: keep GovCloud state in a
  # GovCloud bucket, encrypted with KMS, with locking. Never in commercial storage.
  #
  # backend "s3" {
  #   bucket       = "REPLACE_ME-tfstate"
  #   key          = "bedrock-lab/terraform.tfstate"
  #   region       = "us-gov-west-1"
  #   encrypt      = true
  #   kms_key_id   = "REPLACE_ME"
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name_prefix
      ManagedBy = "terraform"
    }
  }
}
