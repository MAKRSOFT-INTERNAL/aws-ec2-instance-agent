output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "vpc_id" {
  description = "VPC containing the cluster."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by the control plane and worker nodes."
  value       = values(aws_subnet.private)[*].id
}

output "node_group_name" {
  description = "Managed node group name."
  value       = aws_eks_node_group.this.node_group_name
}

output "cluster_role_arn" {
  description = "IAM role assumed by the EKS control plane."
  value       = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  description = "IAM role assumed by the worker nodes."
  value       = aws_iam_role.nodes.arn
}
