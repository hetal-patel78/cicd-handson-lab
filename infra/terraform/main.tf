terraform {
  required_version = "~> 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.83"
    }
  }
  backend "s3" {
    key            = "my-subscription-service/terraform.tfstate"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = local.aws_region
}

data "aws_iam_policy_document" "exec_role_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${local.aws_region}.amazonaws.com/id/${var.oidc_provider_id}"]
    }
    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${local.aws_region}.amazonaws.com/id/${var.oidc_provider_id}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${local.service_name}"]
    }
  }
}

resource "aws_iam_role" "exec_role" {
  name                = "svc-exec-${local.environment}-${local.service_name}"
  assume_role_policy  = data.aws_iam_policy_document.exec_role_trust.json
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/XeroDeveloperPermissionsBoundary"
}

resource "aws_iam_policy" "secrets_read" {
  name   = "${local.service_name}-${local.environment}-secrets-read"
  policy = data.aws_iam_policy_document.secrets_read.json
}

data "aws_iam_policy_document" "secrets_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      "arn:aws:secretsmanager:${local.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${local.secret_prefix}/${local.service_name}/*"
    ]
  }
}

resource "aws_iam_role_policy_attachment" "exec_role_secrets" {
  role       = aws_iam_role.exec_role.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

data "aws_caller_identity" "current" {}

output "exec_role_arn" {
  value = aws_iam_role.exec_role.arn
}