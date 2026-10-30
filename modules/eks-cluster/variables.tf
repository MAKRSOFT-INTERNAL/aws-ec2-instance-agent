variable "aws_region" {
  description = "AWS region for the cluster resources."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes control-plane version."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR range for the dedicated cluster VPC."
  type        = string
}

variable "availability_zone_count" {
  description = "Number of availability zones for subnets."
  type        = number
}

variable "node_instance_types" {
  description = "EC2 instance types used by the managed node group."
  type        = list(string)
}

variable "node_min_size" {
  description = "Minimum number of managed nodes."
  type        = number
}

variable "node_desired_size" {
  description = "Initial desired number of managed nodes."
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of managed nodes."
  type        = number
}

variable "cluster_endpoint_public_access" {
  description = "Whether to enable public access to the Kubernetes API endpoint."
  type        = bool
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR allowlist for the public Kubernetes API endpoint."
  type        = list(string)
}

variable "cluster_admin_iam_role_arn" {
  description = "Optional IAM role to grant EKS cluster-admin access."
  type        = string
}

variable "cluster_view_iam_principal_arn" {
  description = "IAM principal to grant EKS admin-view access."
  type        = string
}
