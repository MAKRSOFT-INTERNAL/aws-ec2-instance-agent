variable "aws_region" {
  description = "AWS region for the Terraform state bucket and lock table."
  type        = string
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state."
  type        = string
}
