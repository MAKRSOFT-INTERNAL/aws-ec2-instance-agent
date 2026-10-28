locals {
  public_subnets = {
    "apse2-az1" = {
      name = "ap-southeast-2a"
      cidr = "10.42.1.0/24"
    }
    "apse2-az3" = {
      name = "ap-southeast-2b"
      cidr = "10.42.2.0/24"
    }
    "apse2-az2" = {
      name = "ap-southeast-2c"
      cidr = "10.42.3.0/24"
    }
  }
}

resource "aws_vpc" "agent" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = "${var.resource_name_prefix}-vpc"
    ManagedBy = "terraform"
  }
}

resource "aws_internet_gateway" "agent" {
  vpc_id = aws_vpc.agent.id

  tags = {
    Name      = "${var.resource_name_prefix}-igw"
    ManagedBy = "terraform"
  }
}

resource "aws_subnet" "agent_public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.agent.id
  cidr_block              = each.value.cidr
  availability_zone_id    = each.key
  map_public_ip_on_launch = true

  tags = {
    Name               = "${var.resource_name_prefix}-public-${each.value.name}"
    AvailabilityZone   = each.value.name
    AvailabilityZoneID = each.key
    ManagedBy          = "terraform"
  }
}

resource "aws_route_table" "agent_public" {
  vpc_id = aws_vpc.agent.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.agent.id
  }

  tags = {
    Name      = "${var.resource_name_prefix}-public-rt"
    ManagedBy = "terraform"
  }
}

resource "aws_route_table_association" "agent_public" {
  for_each = aws_subnet.agent_public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.agent_public.id
}

resource "aws_security_group" "agent" {
  name        = "${var.resource_name_prefix}-agent-sg"
  description = "No inbound access; outbound internet for GitHub Actions and AWS Systems Manager."
  vpc_id      = aws_vpc.agent.id

  egress {
    description = "Outbound HTTPS and required service access."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.resource_name_prefix}-agent-sg"
    ManagedBy = "terraform"
  }
}

output "vpc_id" {
  description = "VPC created for the persistent agent and ephemeral runners."
  value       = aws_vpc.agent.id
}

output "public_subnet_id" {
  description = "Public subnet selected for the persistent agent and ephemeral runners."
  value       = aws_subnet.agent_public[var.runner_subnet_az_id].id
}

output "public_subnet_ids_by_az_id" {
  description = "Public subnet IDs keyed by the account-independent AWS Availability Zone IDs."
  value       = { for az_id, subnet in aws_subnet.agent_public : az_id => subnet.id }
}
