variable "aws_region" {
  description = "AWS region for the Terraform state bucket and lock table."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID allowed to receive the state bucket and lock table."
  type        = string
  default     = "783161622588"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit AWS account ID."
  }
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state."
  type        = string
}
