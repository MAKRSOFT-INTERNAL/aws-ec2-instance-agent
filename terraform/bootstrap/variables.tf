variable "aws_region" {
  description = "AWS region used for the EKS deployment and Terraform state bucket."
  type        = string
  default     = "ap-southeast-2"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for the EKS Terraform state."
  type        = string

  validation {
    condition     = length(var.state_bucket_name) >= 3 && length(var.state_bucket_name) <= 63
    error_message = "state_bucket_name must be between 3 and 63 characters."
  }
}

variable "github_owner" {
  description = "GitHub owner allowed to assume the deployment role."
  type        = string
  default     = "MAKRSOFT-INTERNAL"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the deployment role."
  type        = string
  default     = "aws-ec2-instance-agent"
}

variable "existing_github_oidc_provider_arn" {
  description = "Optional ARN of an existing GitHub Actions OIDC provider in this AWS account."
  type        = string
  default     = ""
}

variable "resource_name_prefix" {
  description = "Prefix allowed for IAM roles managed by the deployment role."
  type        = string
  default     = "makrsoft-eks-"
}

variable "cluster_name" {
  description = "EKS cluster name whose resources the GitHub deployment role may manage."
  type        = string
  default     = "makrsoft-eks"

  validation {
    condition     = length(var.cluster_name) >= 1 && length(var.cluster_name) <= 51 && can(regex("^[A-Za-z0-9][A-Za-z0-9-]*$", var.cluster_name))
    error_message = "cluster_name must be 1-51 characters and contain only letters, numbers, and hyphens."
  }
}
