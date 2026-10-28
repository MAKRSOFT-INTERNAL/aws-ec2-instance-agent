variable "aws_region" {
  description = "AWS region for the runner infrastructure."
  type        = string
}

variable "github_owner" {
  description = "GitHub organization or user that owns the repository."
  type        = string
}

variable "github_repository" {
  description = "Repository name, without the owner."
  type        = string
}

variable "allowed_github_ref" {
  description = "Only this GitHub ref may assume the bootstrap role."
  type        = string
  default     = "refs/heads/main"
}

variable "existing_github_oidc_provider_arn" {
  description = "Optional ARN of an existing token.actions.githubusercontent.com OIDC provider. Leave empty to create one."
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC in which to create the runner security group."
  type        = string
}

variable "subnet_id" {
  description = "Subnet used by runner instances. It must have outbound internet access through a public IP or NAT."
  type        = string
}

variable "associate_public_ip_address" {
  description = "Associate a public IPv4 address with runners. Keep false when the subnet has NAT egress."
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "EC2 instance type for x86_64 Amazon Linux 2023 runners."
  type        = string
  default     = "t3.large"
}

variable "runner_version" {
  description = "Pinned GitHub Actions runner release version, without the leading v."
  type        = string
}

variable "runner_max_lifetime_minutes" {
  description = "Maximum allowed runner instance age before the scheduled janitor terminates it."
  type        = number
  default     = 360
}

variable "root_volume_size_gib" {
  description = "Encrypted EC2 root volume size."
  type        = number
  default     = 50
}