data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_subnet" "runner" {
  id = var.subnet_id
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  repository        = "${var.github_owner}/${var.github_repository}"
  parameter_prefix  = "/github-actions-runners/${var.github_owner}/${var.github_repository}"
  parameter_arn     = "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.parameter_prefix}/*"
  instance_arn      = "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"
  runner_managed_by = "github-actions-ephemeral-runner"
  oidc_provider_arn = var.existing_github_oidc_provider_arn != "" ? var.existing_github_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.existing_github_oidc_provider_arn == "" ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_security_group" "runner" {
  name        = "${var.github_repository}-ephemeral-runner"
  description = "No inbound access; outbound access for ephemeral GitHub Actions runners."
  vpc_id      = var.vpc_id

  lifecycle {
    precondition {
      condition     = data.aws_subnet.runner.vpc_id == var.vpc_id
      error_message = "The runner subnet must belong to vpc_id."
    }
  }

  egress {
    description = "Runner access to GitHub and AWS services."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.github_repository}-ephemeral-runner"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role" "runner_instance" {
  name = "${var.github_repository}-ephemeral-runner-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy" "runner_instance" {
  name = "read-and-delete-runner-registration-token"
  role = aws_iam_role.runner_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:DeleteParameter"]
        Resource = local.parameter_arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "arn:${data.aws_partition.current.partition}:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.${data.aws_partition.current.dns_suffix}"
          }
          StringLike = {
            "kms:EncryptionContext:PARAMETER_ARN" = "arn:${data.aws_partition.current.partition}:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.parameter_prefix}/*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "runner" {
  name = "${var.github_repository}-ephemeral-runner"
  role = aws_iam_role.runner_instance.name

  tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_launch_template" "runner" {
  name                   = "${var.github_repository}-ephemeral-runner"
  image_id               = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.runner.arn
  }

  network_interfaces {
    device_index                = 0
    subnet_id                   = var.subnet_id
    associate_public_ip_address = var.associate_public_ip_address
    delete_on_termination       = true
    security_groups             = [aws_security_group.runner.id]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      encrypted             = true
      volume_size           = var.root_volume_size_gib
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/runner-user-data.sh.tftpl", {
    aws_region       = var.aws_region
    repository       = local.repository
    runner_version   = var.runner_version
    parameter_prefix = local.parameter_prefix
  }))

  instance_initiated_shutdown_behavior = "terminate"

  tag_specifications {
    resource_type = "instance"
    tags = {
      ManagedBy  = local.runner_managed_by
      Repository = local.repository
    }
  }

  tags = {
    Name      = "${var.github_repository}-ephemeral-runner"
    ManagedBy = "terraform"
  }
}
