variable "aws_region" {
  description = "AWS region used for the Terraform state bucket."
  type        = string
  default     = "ap-southeast-2"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for the EKS Terraform state."
  type        = string
  default     = "makrosft-tfstate-s3"

  validation {
    condition     = length(var.state_bucket_name) >= 3 && length(var.state_bucket_name) <= 63
    error_message = "state_bucket_name must be between 3 and 63 characters."
  }
}
