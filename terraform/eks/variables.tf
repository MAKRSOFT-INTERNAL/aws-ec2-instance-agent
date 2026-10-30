variable "aws_region" {
  description = "AWS region where the EKS cluster is provisioned."
  type        = string
  default     = "ap-southeast-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster and prefix for its IAM roles."
  type        = string
  default     = "makrsoft-eks"

  validation {
    condition     = length(var.cluster_name) >= 1 && length(var.cluster_name) <= 51 && can(regex("^[A-Za-z0-9][A-Za-z0-9-]*$", var.cluster_name))
    error_message = "cluster_name must be 1-51 characters and contain only letters, numbers, and hyphens."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes control-plane version."
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR range for the dedicated EKS VPC."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(cidrsubnet(var.vpc_cidr, 8, 18)) && can(regex("/(1[6-9]|20)$", var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR with a prefix between /16 and /20 so the generated AWS subnets are valid."
  }
}

variable "availability_zone_count" {
  description = "Number of availability zones for the EKS subnets."
  type        = number
  default     = 3

  validation {
    condition     = var.availability_zone_count >= 2 && var.availability_zone_count <= 3
    error_message = "availability_zone_count must be 2 or 3."
  }
}

variable "node_instance_types" {
  description = "EC2 instance types used by the managed node group."
  type        = list(string)
  default     = ["t3.micro"]

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "Provide at least one node instance type."
  }
}

variable "node_min_size" {
  description = "Minimum number of managed worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.node_min_size >= 1
    error_message = "node_min_size must be at least 1."
  }
}

variable "node_desired_size" {
  description = "Initial desired number of managed worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.node_desired_size >= var.node_min_size && var.node_desired_size <= var.node_max_size
    error_message = "Node group sizes must satisfy node_min_size <= node_desired_size <= node_max_size."
  }
}

variable "node_max_size" {
  description = "Maximum number of managed worker nodes."
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_size >= 1
    error_message = "node_max_size must be at least 1."
  }
}

variable "cluster_endpoint_public_access" {
  description = "Whether to enable public access to the Kubernetes API endpoint."
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR allowlist for the public Kubernetes API endpoint. Required if public access is enabled."
  type        = list(string)
  default     = []

  validation {
    condition = (
      alltrue([for cidr in var.cluster_endpoint_public_access_cidrs : can(cidrhost(cidr, 0))]) &&
      (!var.cluster_endpoint_public_access || length(var.cluster_endpoint_public_access_cidrs) > 0)
    )
    error_message = "Every endpoint CIDR must be valid, and at least one CIDR is required when public endpoint access is enabled."
  }
}

variable "cluster_admin_iam_role_arn" {
  description = "Optional existing IAM role to grant EKS cluster-admin access."
  type        = string
  default     = ""
}

variable "cluster_view_iam_principal_arn" {
  description = "IAM user or role to grant EKS admin-view access."
  type        = string
  default     = "arn:aws:iam::783161622588:user/makrsoft-admin"
}
