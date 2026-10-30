output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = module.eks.cluster_arn
}

output "vpc_id" {
  description = "VPC containing the EKS cluster."
  value       = module.eks.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnets used by the EKS control plane and worker nodes."
  value       = module.eks.private_subnet_ids
}

output "node_group_name" {
  description = "Managed node group name."
  value       = module.eks.node_group_name
}

output "configure_kubectl" {
  description = "Run this command with AWS credentials for an IAM principal granted EKS access."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
