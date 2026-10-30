output "state_bucket_name" {
  description = "Configure as the GitHub Actions TF_STATE_BUCKET variable."
  value       = aws_s3_bucket.terraform_state.bucket
}
