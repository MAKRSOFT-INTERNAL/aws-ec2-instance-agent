output "state_bucket_name" {
  description = "S3 bucket name to use in the main infrastructure backend configuration."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_lock_table_name" {
  description = "DynamoDB table name to use for Terraform state locking."
  value       = aws_dynamodb_table.terraform_state_lock.name
}
