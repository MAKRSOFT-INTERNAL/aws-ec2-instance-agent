resource "aws_iam_role" "janitor" {
  name = "${var.resource_name_prefix}-runner-janitor"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "janitor_logs" {
  role       = aws_iam_role.janitor.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "janitor" {
  name = "${var.resource_name_prefix}-terminate-stale-runners-and-delete-stale-parameters"
  role = aws_iam_role.janitor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
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
        Action   = ["ssm:GetParametersByPath", "ssm:DeleteParameter"]
        Resource = local.parameter_arn
      }
    ]
  })
}

data "archive_file" "janitor" {
  type        = "zip"
  source_file = "${path.module}/janitor.py"
  output_path = "${path.module}/.terraform/janitor.zip"
}

resource "aws_lambda_function" "janitor" {
  function_name    = "${var.resource_name_prefix}-runner-janitor"
  role             = aws_iam_role.janitor.arn
  handler          = "janitor.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  filename         = data.archive_file.janitor.output_path
  source_code_hash = data.archive_file.janitor.output_base64sha256

  environment {
    variables = {
      MAX_INSTANCE_AGE_SECONDS = tostring(var.runner_max_lifetime_minutes * 60)
      PARAMETER_PREFIX         = local.parameter_prefix
      REPOSITORY               = local.repository
      RUNNER_MANAGED_BY        = local.runner_managed_by
    }
  }

  depends_on = [aws_iam_role_policy_attachment.janitor_logs]

  tags = {
    ManagedBy = "terraform"
  }
}

resource "aws_cloudwatch_event_rule" "janitor" {
  name                = "${var.resource_name_prefix}-runner-janitor"
  description         = "Remove abandoned EC2 runners and stale registration token parameters."
  schedule_expression = "rate(15 minutes)"
}

resource "aws_cloudwatch_event_target" "janitor" {
  rule      = aws_cloudwatch_event_rule.janitor.name
  target_id = "runner-janitor"
  arn       = aws_lambda_function.janitor.arn
}

resource "aws_lambda_permission" "janitor_events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.janitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.janitor.arn
}
