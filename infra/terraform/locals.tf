locals {
  service_name = "my-subscription-service"
  environment  = var.environment

  region_map = {
    test       = "ap-southeast-2"
    uat        = "us-west-2"
    production = "us-east-1"
  }

  aws_region = lookup(local.region_map, local.environment, "ap-southeast-2")

  secret_prefix_map = {
    test       = "cdo1"
    uat        = "uat"
    production = "prod"
  }

  secret_prefix = lookup(local.secret_prefix_map, local.environment, "cdo1")
}