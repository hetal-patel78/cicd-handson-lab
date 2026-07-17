terraform {
  required_version = "~> 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.83"
    }
  }
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

provider "aws" {
  region = var.region
}

resource "aws_iam_role" "deployment_role" {
  name = "billing-chargebee-buyflow-deployment-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

data "aws_caller_identity" "current" {}

output "deployment_role_arn" {
  value = aws_iam_role.deployment_role.arn
}