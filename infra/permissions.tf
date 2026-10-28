resource "aws_iam_role" "bootstrap" {
  name = "${var.resource_name_prefix}-runner-bootstrap"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${local.repository}:ref:${var.allowed_github_ref}"
        }
      }
    }]
  })

  tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy" "bootstrap" {
  name = "${var.resource_name_prefix}-launch-and-cleanup-ephemeral-runner"
  role = aws_iam_role.bootstrap.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeLaunchTemplateVersions"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:RunInstances"]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "ec2:LaunchTemplate" = aws_launch_template.runner.arn
            "ec2:Subnet"         = aws_subnet.agent_public[var.runner_subnet_az_id].arn
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = local.instance_arn
        Condition = {
          StringEquals = {
            "ec2:CreateAction"          = "RunInstances"
            "aws:RequestTag/ManagedBy"  = local.runner_managed_by
            "aws:RequestTag/Repository" = local.repository
          }
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = ["ManagedBy", "Repository", "RunnerLabel", "RunId", "RunAttempt"]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:TerminateInstances"]
        Resource = local.instance_arn
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/ManagedBy"  = local.runner_managed_by
            "ec2:ResourceTag/Repository" = local.repository
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.runner_instance.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:PutParameter", "ssm:DeleteParameter"]
        Resource = local.parameter_arn
      }
    ]
  })
}

output "bootstrap_role_arn" {
  description = "ARN to configure as the AWS_RUNNER_ROLE_ARN GitHub Actions variable."
  value       = aws_iam_role.bootstrap.arn
}

output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN for the Terraform deployment role trust policy."
  value       = local.oidc_provider_arn
}

output "runner_launch_template_id" {
  description = "Launch template ID for the GitHub Actions bootstrap workflow."
  value       = aws_launch_template.runner.id
}

output "runner_parameter_prefix" {
  description = "SSM path used for one-time runner registration tokens."
  value       = local.parameter_prefix
}

output "agent_instance_id" {
  description = "Instance ID of the persistent S3-enabled agent."
  value       = aws_instance.agent.id
}

output "agent_instance_role_arn" {
  description = "IAM role ARN attached to the persistent agent."
  value       = aws_iam_role.agent_instance.arn
}

output "object_bucket_name" {
  description = "S3 bucket for application objects; agent access is restricted to agent_s3_prefix."
  value       = aws_s3_bucket.objects.id
}
