output "deployment_role_arn" {
  description = "Configure as the GitHub Actions AWS_DEPLOY_ROLE_ARN repository variable."
  value       = aws_iam_role.github_deploy.arn
}

output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN."
  value       = local.github_oidc_provider_arn
}

output "state_bucket_name" {
  description = "Configure as the GitHub Actions TF_STATE_BUCKET repository variable."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "cluster_name" {
  description = "EKS cluster name allowed by the GitHub deployment role's scoped permissions."
  value       = var.cluster_name
}
