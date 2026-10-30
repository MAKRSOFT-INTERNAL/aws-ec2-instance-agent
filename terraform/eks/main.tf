provider "aws" {
  region = var.aws_region
}

module "eks" {
  source = "../../modules/eks-cluster"

  aws_region                           = var.aws_region
  cluster_name                         = var.cluster_name
  kubernetes_version                   = var.kubernetes_version
  vpc_cidr                             = var.vpc_cidr
  availability_zone_count              = var.availability_zone_count
  node_instance_types                  = var.node_instance_types
  node_min_size                        = var.node_min_size
  node_desired_size                    = var.node_desired_size
  node_max_size                        = var.node_max_size
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  cluster_admin_iam_role_arn           = var.cluster_admin_iam_role_arn
  cluster_view_iam_principal_arn       = var.cluster_view_iam_principal_arn
}
